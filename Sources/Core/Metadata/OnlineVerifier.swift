import Foundation

/// Verifies parsed metadata against online APIs (iTunes US & IN, Deezer, MusicBrainz).
actor OnlineVerifier {
    static let shared = OnlineVerifier()
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 8.0
        self.session = URLSession(configuration: config)
    }
    
    struct VerifiedMetadata: Sendable {
        let artist: String
        let title: String
        let album: String?
        let genre: String?
        let year: Int?
        let artworkUrl: URL?
        let score: Double
        var matchCount: Int = 1
    }
    
    /// Queries online sources and returns the best matching metadata with score >= 0.85, or nil.
    func verify(artist: String, title: String) async -> VerifiedMetadata? {
        let cleanTitle = TitleCleaner.clean(title).cleanedString
        let cleanArtist = TitleCleaner.clean(artist.components(separatedBy: " (feat.").first ?? artist).cleanedString
        
        guard !cleanTitle.isEmpty else { return nil }
        
        // Execute queries concurrently across providers
        async let lrclib = searchLRCLIB(artist: cleanArtist, title: cleanTitle)
        async let itunesUS = searchITunes(artist: cleanArtist, title: cleanTitle, country: nil)
        async let itunesIN = searchITunes(artist: cleanArtist, title: cleanTitle, country: "IN")
        async let deezer = searchDeezer(artist: cleanArtist, title: cleanTitle)
        async let musicBrainz = searchMusicBrainz(artist: cleanArtist, title: cleanTitle)
        
        var allCandidates: [VerifiedMetadata] = []
        allCandidates.append(contentsOf: await lrclib)
        allCandidates.append(contentsOf: await itunesUS)
        allCandidates.append(contentsOf: await itunesIN)
        allCandidates.append(contentsOf: await deezer)
        allCandidates.append(contentsOf: await musicBrainz)
        
        let validCandidates = allCandidates.filter { $0.score >= 0.85 }
        guard var best = validCandidates.max(by: { $0.score < $1.score }) else { return nil }
        best.matchCount = validCandidates.count
        
        return best
    }
    
    // MARK: - Token-Set Similarity Scoring
    
    static func normalizeTokens(_ str: String) -> [String] {
        var folded = str.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        folded = folded.replacingOccurrences(of: "(?<=\\b[a-zA-Z])\\.(?=[a-zA-Z])", with: "", options: .regularExpression)
        folded = folded.replacingOccurrences(of: "(?<=\\b[a-zA-Z]{2,6})\\.", with: "", options: .regularExpression)
        
        let mutableStr = NSMutableString(string: folded)
        CFStringTransform(mutableStr, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableStr, nil, kCFStringTransformStripDiacritics, false)
        let latin = (mutableStr as String).lowercased()
        
        return latin.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
    
    static func tokenSetSimilarity(_ s1: String, _ s2: String) -> Double {
        let t1 = Set(normalizeTokens(s1))
        let t2 = Set(normalizeTokens(s2))
        guard !t1.isEmpty && !t2.isEmpty else { return 0.0 }
        if t1 == t2 { return 1.0 }
        
        let intersection = t1.intersection(t2)
        let union = t1.union(t2)
        
        let jaccard = Double(intersection.count) / Double(union.count)
        let minCount = Double(min(t1.count, t2.count))
        let containment = minCount > 0 ? Double(intersection.count) / minCount : 0.0
        
        // If one token set is entirely contained in the other and lengths are close
        if containment >= 0.99 && union.count <= 3 {
            return (0.5 * jaccard) + (0.5 * containment)
        }
        
        return (0.7 * jaccard) + (0.3 * containment)
    }
    
    static func computeMatchScore(queryArtist: String, queryTitle: String, resultArtist: String, resultTitle: String) -> Double {
        let titleScore = tokenSetSimilarity(queryTitle, resultTitle)
        guard titleScore >= 0.70 else { return 0.0 }
        
        let isArtistUnknown = queryArtist.trimmingCharacters(in: .whitespaces).lowercased() == "unknown" || queryArtist.isEmpty
        if isArtistUnknown {
            return titleScore
        }
        
        var artistScore = tokenSetSimilarity(queryArtist, resultArtist)
        
        // Reward collaborator / singer containment (e.g. "Arijit Singh" in "Pritam, Arijit Singh")
        let qArtTokens = Set(normalizeTokens(queryArtist))
        let rArtTokens = Set(normalizeTokens(resultArtist))
        if !qArtTokens.isEmpty && qArtTokens.isSubset(of: rArtTokens) {
            artistScore = max(artistScore, 0.85)
        }
        
        guard artistScore >= 0.55 else { return 0.0 }
        return (0.6 * titleScore) + (0.4 * artistScore)
    }
    
    // MARK: - Providers
    
    private func searchITunes(artist: String, title: String, country: String?) async -> [VerifiedMetadata] {
        let isUnknown = artist.lowercased() == "unknown" || artist.isEmpty
        let term = isUnknown ? title : "\(artist) \(title)"
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        
        var urlStr = "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=5"
        if let country = country {
            urlStr += "&country=\(country)"
        }
        guard let url = URL(string: urlStr) else { return [] }
        
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { return [] }
            
            var list: [VerifiedMetadata] = []
            for item in results {
                guard let resArtist = item["artistName"] as? String,
                      let resTitle = item["trackName"] as? String else { continue }
                
                let score = Self.computeMatchScore(queryArtist: artist, queryTitle: title, resultArtist: resArtist, resultTitle: resTitle)
                guard score > 0 else { continue }
                
                var year: Int?
                if let releaseDate = item["releaseDate"] as? String, let y = Int(releaseDate.prefix(4)) {
                    year = y
                }
                
                var artworkUrl: URL?
                if let artStr = item["artworkUrl100"] as? String {
                    let highRes = artStr.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")
                    artworkUrl = URL(string: highRes)
                }
                
                list.append(VerifiedMetadata(
                    artist: resArtist,
                    title: resTitle,
                    album: item["collectionName"] as? String,
                    genre: item["primaryGenreName"] as? String,
                    year: year,
                    artworkUrl: artworkUrl,
                    score: score
                ))
            }
            return list
        } catch {
            return []
        }
    }
    
    private func searchDeezer(artist: String, title: String) async -> [VerifiedMetadata] {
        let isUnknown = artist.lowercased() == "unknown" || artist.isEmpty
        let term = isUnknown ? title : "\(artist) \(title)"
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.deezer.com/search?q=\(encoded)&limit=5") else { return [] }
        
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["data"] as? [[String: Any]] else { return [] }
            
            var list: [VerifiedMetadata] = []
            for item in items {
                guard let resTitle = item["title"] as? String,
                      let artistObj = item["artist"] as? [String: Any],
                      let resArtist = artistObj["name"] as? String else { continue }
                
                let score = Self.computeMatchScore(queryArtist: artist, queryTitle: title, resultArtist: resArtist, resultTitle: resTitle)
                guard score > 0 else { continue }
                
                let albumObj = item["album"] as? [String: Any]
                let albumTitle = albumObj?["title"] as? String
                var artworkUrl: URL?
                if let coverStr = (albumObj?["cover_xl"] ?? albumObj?["cover_big"] ?? albumObj?["cover_medium"]) as? String {
                    artworkUrl = URL(string: coverStr)
                }
                
                list.append(VerifiedMetadata(
                    artist: resArtist,
                    title: resTitle,
                    album: albumTitle,
                    genre: nil,
                    year: nil,
                    artworkUrl: artworkUrl,
                    score: score
                ))
            }
            return list
        } catch {
            return []
        }
    }
    
    private func searchMusicBrainz(artist: String, title: String) async -> [VerifiedMetadata] {
        let isUnknown = artist.lowercased() == "unknown" || artist.isEmpty
        let cleanT = TitleCleaner.clean(title).cleanedString
        let cleanA = TitleCleaner.clean(artist).cleanedString
        let queryStr = isUnknown ? "recording:\"\(cleanT)\"" : "recording:\"\(cleanT)\" AND artist:\"\(cleanA)\""
        guard let encoded = queryStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://musicbrainz.org/ws/2/recording/?query=\(encoded)&fmt=json&limit=5") else { return [] }
        
        var req = URLRequest(url: url)
        req.setValue("Lumo/1.0.0 (contact@lumo.internal)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let recordings = json["recordings"] as? [[String: Any]] else { return [] }
            
            var list: [VerifiedMetadata] = []
            for rec in recordings {
                guard let resTitle = rec["title"] as? String else { continue }
                
                var resArtist = "Unknown"
                if let credits = rec["artist-credit"] as? [[String: Any]],
                   let first = credits.first,
                   let name = first["name"] as? String {
                    resArtist = name
                }
                
                let score = Self.computeMatchScore(queryArtist: artist, queryTitle: title, resultArtist: resArtist, resultTitle: resTitle)
                guard score > 0 else { continue }
                
                var albumTitle: String?
                var year: Int?
                var artworkUrl: URL?
                if let releases = rec["releases"] as? [[String: Any]] {
                    for rel in releases.prefix(5) {
                        if albumTitle == nil { albumTitle = rel["title"] as? String }
                        if year == nil, let d = rel["date"] as? String, let y = Int(d.prefix(4)) {
                            year = y
                        }
                        if artworkUrl == nil, let relId = rel["id"] as? String {
                            artworkUrl = URL(string: "https://coverartarchive.org/release/\(relId)/front-500")
                        }
                    }
                }
                
                list.append(VerifiedMetadata(
                    artist: resArtist,
                    title: resTitle,
                    album: albumTitle,
                    genre: nil,
                    year: year,
                    artworkUrl: artworkUrl,
                    score: score
                ))
            }
            return list
        } catch {
            return []
        }
    }
    
    private func searchLRCLIB(artist: String, title: String) async -> [VerifiedMetadata] {
        let isUnknown = artist.lowercased() == "unknown" || artist.isEmpty
        var urlsToTry: [URL] = []
        
        if !isUnknown {
            if let encTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let encArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let directUrl = URL(string: "https://lrclib.net/api/search?track_name=\(encTitle)&artist_name=\(encArtist)") {
                urlsToTry.append(directUrl)
            }
            if title.count >= 2 && title.count <= 6 && title == title.uppercased() {
                let dotted = title.map { String($0) }.joined(separator: ".")
                for dStr in [dotted, dotted + "."] {
                    if let encDotted = dStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let encArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let dottedUrl = URL(string: "https://lrclib.net/api/search?track_name=\(encDotted)&artist_name=\(encArtist)") {
                        urlsToTry.append(dottedUrl)
                    }
                }
            }
        }
        
        let term = isUnknown ? title : "\(artist) \(title)"
        if let encTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let queryUrl = URL(string: "https://lrclib.net/api/search?q=\(encTerm)") {
            urlsToTry.append(queryUrl)
        }
        
        var list: [VerifiedMetadata] = []
        for url in urlsToTry {
            var req = URLRequest(url: url)
            req.setValue("Lumo/1.0.0 (contact@lumo.internal)", forHTTPHeaderField: "User-Agent")
            
            do {
                var (data, response) = try await session.data(for: req)
                if (response as? HTTPURLResponse)?.statusCode == 503 || (response as? HTTPURLResponse)?.statusCode == 429 {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if let retried = try? await session.data(for: req) {
                        data = retried.0
                        response = retried.1
                    }
                }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
                
                for item in items {
                    guard let resTitle = item["trackName"] as? String ?? item["name"] as? String,
                          let resArtist = item["artistName"] as? String else { continue }
                    
                    let score = Self.computeMatchScore(queryArtist: artist, queryTitle: title, resultArtist: resArtist, resultTitle: resTitle)
                    guard score > 0 else { continue }
                    
                    let albumTitle = item["albumName"] as? String
                    list.append(VerifiedMetadata(
                        artist: resArtist,
                        title: resTitle,
                        album: albumTitle,
                        genre: nil,
                        year: nil,
                        artworkUrl: nil,
                        score: score
                    ))
                }
                if !list.isEmpty { break }
            } catch {
                continue
            }
        }
        return list
    }
}
