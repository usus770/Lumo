import Foundation

/// Provider for LRCLIB lyrics (synced LRC and plain text), with script detection and Indic transliteration.
public actor LRCLibProvider: MetadataProvider {
    public static let shared = LRCLibProvider()
    
    public let name = "LRCLIB"
    private let session: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12.0
        config.timeoutIntervalForResource = 15.0
        self.session = URLSession(configuration: config)
    }
    
    private struct LRCLibItem: Decodable {
        let id: Int?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }
    
    public func search(query: String) async throws -> [MetadataSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lrclib.net/api/search?q=\(encoded)") else {
            return []
        }
        
        var req = URLRequest(url: url)
        req.setValue("Lumo/1.0 (contact@lumo.internal)", forHTTPHeaderField: "User-Agent")
        
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let items = try? JSONDecoder().decode([LRCLibItem].self, from: data) else {
            return []
        }
        
        return items.compactMap { item in
            guard let title = item.trackName, !title.isEmpty,
                  let artist = item.artistName else { return nil }
            return MetadataSearchResult(
                id: "\(item.id ?? abs(title.hashValue))",
                videoId: nil,
                title: title,
                artist: artist,
                album: item.albumName ?? "",
                duration: item.duration ?? 0,
                thumbnailURL: nil,
                highResArtworkURL: nil,
                matchScore: 0.0,
                isSquareArtwork: true,
                source: "LRCLIB"
            )
        }
    }
    
    public func lookupVideoId(_ videoId: String) async throws -> MetadataSearchResult? {
        return nil
    }
    
    public func fetchCoverArt(for result: MetadataSearchResult) async throws -> CoverArtCandidate? {
        return nil
    }
    
    // MARK: - Lyrics Fetching
    
    public func fetchLyrics(for result: MetadataSearchResult, duration: TimeInterval?) async throws -> LyricsResultCandidate? {
        return await fetchLyrics(title: result.title, artist: result.artist, album: result.album, duration: duration ?? result.duration)
    }
    
    public func fetchLyrics(title: String, artist: String, album: String? = nil, duration: TimeInterval? = nil) async -> LyricsResultCandidate? {
        let cleanTitle = TitleCleaner.clean(title).cleanedString
        let cleanArtist = TitleCleaner.clean(artist.components(separatedBy: " (feat.").first ?? artist).cleanedString
        
        guard !cleanTitle.isEmpty else { return nil }
        
        // Extract effective title and artist using TitleParser (handles "Artist - Title", multi-segment, etc.)
        var effectiveTitle = cleanTitle
        var effectiveArtist = cleanArtist
        
        let parsedCandidates = TitleParser.parse(cleanedString: cleanTitle, uploader: cleanArtist)
        if let topCandidate = parsedCandidates.first, topCandidate.confidence >= 0.70 {
            effectiveTitle = topCandidate.title
            if effectiveArtist.isEmpty || effectiveArtist.lowercased() == "unknown" || TitleParser.isKnownLabel(effectiveArtist) {
                effectiveArtist = topCandidate.artist
            }
        }
        
        // Remove duplicated artist prefix from title if present: "Artist - Song" -> "Song"
        if !effectiveArtist.isEmpty && effectiveTitle.lowercased().hasPrefix(effectiveArtist.lowercased()) {
            effectiveTitle = String(effectiveTitle.dropFirst(effectiveArtist.count)).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—: ")))
        }
        if effectiveTitle.isEmpty { effectiveTitle = cleanTitle }
        
        // 1. Try exact /api/get if duration and artist are available
        if let dur = duration, dur > 0, !effectiveArtist.isEmpty,
           let encT = effectiveTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let encA = effectiveArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            
            var urlStr = "https://lrclib.net/api/get?track_name=\(encT)&artist_name=\(encA)&duration=\(Int(dur.rounded()))"
            if let alb = album, !alb.isEmpty, let encAlb = alb.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlStr += "&album_name=\(encAlb)"
            }
            
            if let url = URL(string: urlStr) {
                var req = URLRequest(url: url)
                req.setValue("Lumo/1.0 (contact@lumo.internal)", forHTTPHeaderField: "User-Agent")
                if let (data, resp) = try? await session.data(for: req),
                   (resp as? HTTPURLResponse)?.statusCode == 200,
                   let item = try? JSONDecoder().decode(LRCLibItem.self, from: data) {
                    if let candidate = candidateFromItem(item, targetDuration: dur) {
                        return candidate
                    }
                }
            }
        }
        
        // 2. Build search queries in descending order of precision
        var rawQueries: [String] = []
        if !effectiveArtist.isEmpty && effectiveArtist.lowercased() != "unknown" {
            rawQueries.append("\(effectiveArtist) \(effectiveTitle)")
            rawQueries.append("\(effectiveTitle) \(effectiveArtist)")
        }
        rawQueries.append(effectiveTitle)
        if cleanTitle != effectiveTitle {
            if !cleanArtist.isEmpty && cleanArtist.lowercased() != "unknown" {
                rawQueries.append("\(cleanArtist) \(cleanTitle)")
            }
            rawQueries.append(cleanTitle)
        }
        
        var seenQueries = Set<String>()
        var searchQueries: [String] = []
        for q in rawQueries {
            let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && !seenQueries.contains(t.lowercased()) {
                seenQueries.insert(t.lowercased())
                searchQueries.append(t)
            }
        }
        
        var firstPlainCandidate: LyricsResultCandidate? = nil
        
        for q in searchQueries {
            guard let encQ = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://lrclib.net/api/search?q=\(encQ)") else { continue }
            
            var req = URLRequest(url: url)
            req.setValue("Lumo/1.0 (contact@lumo.internal)", forHTTPHeaderField: "User-Agent")
            
            guard let (data, resp) = try? await session.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let items = try? JSONDecoder().decode([LRCLibItem].self, from: data),
                  !items.isEmpty else { continue }
            
            // Prefer items that have synced lyrics first, then original Indic script if present
            let sorted = items.sorted { a, b in
                let aSynced = (a.syncedLyrics != nil && !a.syncedLyrics!.isEmpty) ? 1 : 0
                let bSynced = (b.syncedLyrics != nil && !b.syncedLyrics!.isEmpty) ? 1 : 0
                if aSynced != bSynced { return aSynced > bSynced }
                
                let aScript = Self.containsIndicScript(a.syncedLyrics ?? a.plainLyrics ?? "") ? 1 : 0
                let bScript = Self.containsIndicScript(b.syncedLyrics ?? b.plainLyrics ?? "") ? 1 : 0
                return aScript > bScript
            }
            
            for item in sorted {
                if let candidate = candidateFromItem(item, targetDuration: duration) {
                    if candidate.isSynced {
                        return candidate // Immediate return for synced lyrics
                    } else if firstPlainCandidate == nil {
                        firstPlainCandidate = candidate
                    }
                }
            }
        }
        
        return firstPlainCandidate
    }
    
    // MARK: - Validation & Transformation
    
    private func candidateFromItem(_ item: LRCLibItem, targetDuration: TimeInterval?) -> LyricsResultCandidate? {
        let isSynced = (item.syncedLyrics != nil && !item.syncedLyrics!.isEmpty)
        let rawText = isSynced ? item.syncedLyrics! : (item.plainLyrics ?? "")
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Filter out junk / placeholder entries (e.g. "probe", single-word uploads)
        let lines = trimmed.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 3 else { return nil }
        
        var lastTs: TimeInterval? = nil
        var isValidDuration = true
        
        if isSynced {
            let parsed = LyricsParser.parse(rawText)
            if let lastLine = parsed.lines.last {
                lastTs = lastLine.time
                if let targetDur = targetDuration, targetDur > 30.0 {
                    // Sanity check: lyrics last timestamp cannot exceed song + 45s or be less than 30% of song
                    if lastLine.time > targetDur + 45.0 || lastLine.time < targetDur * 0.30 {
                        isValidDuration = false
                    }
                }
            }
        }
        
        // If duration validation fails for synced lyrics, fall back to plain lyrics rather than discarding
        if !isValidDuration {
            if let plain = item.plainLyrics {
                let plainTrimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
                let plainLines = plainTrimmed.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                guard plainLines.count >= 3 else { return nil }
                
                let hasIndic = Self.containsIndicScript(plainTrimmed)
                return LyricsResultCandidate(
                    lyricsText: plainTrimmed,
                    isSynced: false,
                    source: "LRCLIB (plain)",
                    durationValid: true,
                    lastTimestamp: nil,
                    detectedScript: hasIndic ? "Devanagari/Indic" : "Latin",
                    romanizedText: hasIndic ? Romanizer.romanize(text: plainTrimmed) : nil
                )
            }
            return nil
        }
        
        let hasIndic = Self.containsIndicScript(rawText)
        let detectedScript = hasIndic ? "Devanagari/Indic" : "Latin"
        var romanized: String? = nil
        if hasIndic {
            romanized = Romanizer.romanize(text: rawText)
        }
        
        let sourceName = isSynced ? "LRCLIB (synced)" : "LRCLIB (plain)"
        return LyricsResultCandidate(
            lyricsText: rawText,
            isSynced: isSynced,
            source: sourceName,
            durationValid: true,
            lastTimestamp: lastTs,
            detectedScript: detectedScript,
            romanizedText: romanized
        )
    }
    
    public static func containsIndicScript(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Devanagari range: 0x0900 - 0x097F, Gurmukhi: 0x0A00 - 0x0A7F, Bengali: 0x0980 - 0x09FF
            if (scalar.value >= 0x0900 && scalar.value <= 0x0D7F) {
                return true
            }
        }
        return false
    }
}
