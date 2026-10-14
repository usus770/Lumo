import Foundation
import AppKit

/// Native Swift provider for YouTube Music search, video lookup, lyrics, and high-resolution album art.
/// Communicates directly via HTTP with the YouTube Music Innertube API without external dependencies.
public actor YouTubeMusicProvider: MetadataProvider {
    public static let shared = YouTubeMusicProvider()
    
    public let name = "YouTube Music"
    private let session: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 15.0
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - API Headers & Context
    
    private func makeRequest(url: URL, body: [String: Any]) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        req.setValue("https://music.youtube.com", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
    
    private var clientContext: [String: Any] {
        [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20230515.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ]
        ]
    }
    
    // MARK: - Search
    
    public func search(query: String) async throws -> [MetadataSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/search") else { return [] }
        
        var payload = clientContext
        payload["query"] = query
        // Songs filter chip param: returns clean list of songs first
        payload["params"] = "EgWKAQIIAWoSEAQQAxAFEAkQChAVEBAQDhAR"
        
        let request = try makeRequest(url: url, body: payload)
        let (data, response) = try await session.data(for: request)
        
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            return []
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = (json["contents"] as? [String: Any])?["tabbedSearchResultsRenderer"] as? [String: Any],
              let tabs = contents["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let sectionList = content["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]] else {
            return []
        }
        
        var results: [MetadataSearchResult] = []
        
        for section in sections {
            let shelf = section["musicShelfRenderer"] as? [String: Any]
            let items = shelf?["contents"] as? [[String: Any]] ?? []
            
            for item in items {
                guard let mrr = item["musicResponsiveListItemRenderer"] as? [String: Any] else { continue }
                
                var videoId: String? = (mrr["playlistItemData"] as? [String: Any])?["videoId"] as? String
                var title = ""
                var artist = ""
                var album = ""
                var duration: TimeInterval = 0
                
                // Parse flex columns
                if let flexCols = mrr["flexColumns"] as? [[String: Any]] {
                    // Column 0: Title
                    if let firstCol = flexCols.first,
                       let r = firstCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                       let runs = (r["text"] as? [String: Any])?["runs"] as? [[String: Any]] {
                        title = runs.compactMap { $0["text"] as? String }.joined()
                        if videoId == nil {
                            for run in runs {
                                if let we = (run["navigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any],
                                   let vid = we["videoId"] as? String {
                                    videoId = vid
                                    break
                                }
                            }
                        }
                    }
                    
                    // Column 1: Artist, Album, Duration separated by bullet
                    if flexCols.count > 1 {
                        let secCol = flexCols[1]
                        if let r = secCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                           let runs = (r["text"] as? [String: Any])?["runs"] as? [[String: Any]] {
                            let parts = runs.compactMap { $0["text"] as? String }.joined().components(separatedBy: " • ")
                            if parts.count >= 3 {
                                artist = parts[0].trimmingCharacters(in: .whitespaces)
                                album = parts[1].trimmingCharacters(in: .whitespaces)
                                duration = Self.parseDuration(parts[2].trimmingCharacters(in: .whitespaces))
                            } else if parts.count == 2 {
                                artist = parts[0].trimmingCharacters(in: .whitespaces)
                                if parts[1].contains(":") {
                                    duration = Self.parseDuration(parts[1].trimmingCharacters(in: .whitespaces))
                                } else {
                                    album = parts[1].trimmingCharacters(in: .whitespaces)
                                }
                            } else if let only = parts.first {
                                artist = only.trimmingCharacters(in: .whitespaces)
                            }
                        }
                    }
                }
                
                guard !title.isEmpty else { continue }
                
                // Parse thumbnail
                var thumbUrl: String?
                var isSquare = true
                if let thumbRenderer = (mrr["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any],
                   let thumbs = (thumbRenderer["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]],
                   let lastThumb = thumbs.last,
                   let u = lastThumb["url"] as? String {
                    thumbUrl = u
                    if u.contains("i.ytimg.com") {
                        isSquare = false
                    }
                }
                
                let highRes = thumbUrl.map { Self.rewriteToHighRes($0, videoId: videoId) }
                
                results.append(MetadataSearchResult(
                    id: videoId ?? UUID().uuidString,
                    videoId: videoId,
                    title: title,
                    artist: artist,
                    album: album,
                    duration: duration,
                    thumbnailURL: thumbUrl,
                    highResArtworkURL: highRes,
                    matchScore: 0.0,
                    isSquareArtwork: isSquare,
                    source: "YouTube Music"
                ))
                
                if results.count >= 12 { break }
            }
            if results.count >= 10 { break }
        }
        
        return results
    }
    
    // MARK: - Direct Video ID Lookup
    
    public func lookupVideoId(_ videoId: String) async throws -> MetadataSearchResult? {
        guard !videoId.isEmpty else { return nil }
        
        // 1. Try Innertube player API first
        if let playerHit = try? await lookupViaPlayer(videoId: videoId) {
            return playerHit
        }
        
        // 2. Resilient fallback: official public YouTube oEmbed API
        if let oembedHit = try? await lookupViaOEmbed(videoId: videoId) {
            return oembedHit
        }
        
        return nil
    }
    
    private func lookupViaPlayer(videoId: String) async throws -> MetadataSearchResult? {
        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/player") else { return nil }
        
        var payload = clientContext
        payload["videoId"] = videoId
        
        let request = try makeRequest(url: url, body: payload)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let details = json["videoDetails"] as? [String: Any] else {
            return nil
        }
        
        let rawTitle = details["title"] as? String ?? ""
        let author = details["author"] as? String ?? ""
        let lengthSec = Double(details["lengthSeconds"] as? String ?? "0") ?? 0
        
        var thumbUrl: String?
        var isSquare = true
        if let thumbs = (details["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]],
           let last = thumbs.last,
           let u = last["url"] as? String {
            thumbUrl = u
            if u.contains("i.ytimg.com") {
                isSquare = false
            }
        }
        
        let highRes = thumbUrl.map { Self.rewriteToHighRes($0, videoId: videoId) }
        
        return MetadataSearchResult(
            id: videoId,
            videoId: videoId,
            title: rawTitle,
            artist: author,
            album: "",
            duration: lengthSec,
            thumbnailURL: thumbUrl,
            highResArtworkURL: highRes,
            matchScore: 1.0,
            isSquareArtwork: isSquare,
            source: "YouTube Music"
        )
    }
    
    private func lookupViaOEmbed(videoId: String) async throws -> MetadataSearchResult? {
        guard let url = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoId)&format=json") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10.0
        
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String else {
            return nil
        }
        
        let author = json["author_name"] as? String ?? ""
        let thumbUrl = "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
        let highRes = "https://i.ytimg.com/vi/\(videoId)/maxresdefault.jpg"
        
        return MetadataSearchResult(
            id: videoId,
            videoId: videoId,
            title: title,
            artist: author,
            album: "",
            duration: 0,
            thumbnailURL: thumbUrl,
            highResArtworkURL: highRes,
            matchScore: 1.0,
            isSquareArtwork: false,
            source: "YouTube (Direct Link)"
        )
    }
    
    // MARK: - Cover Art Download & Cropping
    
    public func fetchCoverArt(for result: MetadataSearchResult) async throws -> CoverArtCandidate? {
        let urlsToTry = [
            result.highResArtworkURL,
            result.thumbnailURL,
            result.videoId.map { "https://i.ytimg.com/vi/\($0)/maxresdefault.jpg" },
            result.videoId.map { "https://i.ytimg.com/vi/\($0)/hqdefault.jpg" }
        ].compactMap { $0 }
        
        for urlStr in urlsToTry {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 10.0
            
            if let (data, resp) = try? await session.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               !data.isEmpty,
               let image = NSImage(data: data) {
                
                let isVideoThumb = urlStr.contains("ytimg.com") || (!result.isSquareArtwork && image.size.width > image.size.height * 1.3)
                let cropped = ArtworkPipeline.squareCropIfNeeded(data: data)
                
                return CoverArtCandidate(
                    data: cropped,
                    source: "YouTube Music",
                    isHighRes: image.size.width >= 500,
                    isSquare: true,
                    isVideoThumbnail: isVideoThumb
                )
            }
        }
        return nil
    }
    
    // MARK: - Lyrics Lookup
    
    public func fetchLyrics(for result: MetadataSearchResult, duration: TimeInterval?) async throws -> LyricsResultCandidate? {
        // 1. Try direct videoId if present
        if let videoId = result.videoId, !videoId.isEmpty {
            if let direct = try? await fetchLyrics(videoId: videoId) {
                return direct
            }
        }
        
        // 2. If direct video has no lyrics tab (common for music video uploads), search YouTube Music songs for the clean track
        let clean = MetadataFetcherCoordinator.cleanSearchQuery(title: result.title, artist: result.artist)
        let searchHits = (try? await search(query: clean.cleanedQuery)) ?? []
        for hit in searchHits {
            guard let hitVid = hit.videoId, hitVid != result.videoId else { continue }
            if let songLyrics = try? await fetchLyrics(videoId: hitVid) {
                return songLyrics
            }
        }
        
        return nil
    }
    
    public func fetchLyrics(videoId: String) async throws -> LyricsResultCandidate? {
        guard !videoId.isEmpty else { return nil }
        guard let urlNext = URL(string: "https://music.youtube.com/youtubei/v1/next") else { return nil }
        
        var payloadNext = clientContext
        payloadNext["videoId"] = videoId
        
        let requestNext = try makeRequest(url: urlNext, body: payloadNext)
        guard let (dataNext, respNext) = try? await session.data(for: requestNext),
              (respNext as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        
        guard let jsonNext = try? JSONSerialization.jsonObject(with: dataNext) as? [String: Any],
              let contents = jsonNext["contents"] as? [String: Any],
              let watchNext = (contents["singleColumnMusicWatchNextResultsRenderer"] as? [String: Any])?["tabbedRenderer"] as? [String: Any],
              let resultsRenderer = watchNext["watchNextTabbedResultsRenderer"] as? [String: Any],
              let tabs = resultsRenderer["tabs"] as? [[String: Any]] else {
            return nil
        }
        
        var lyricsBrowseId: String?
        for tab in tabs {
            let tr = tab["tabRenderer"] as? [String: Any]
            if (tr?["title"] as? String) == "Lyrics",
               let endpoint = tr?["endpoint"] as? [String: Any],
               let be = endpoint["browseEndpoint"] as? [String: Any],
               let bId = be["browseId"] as? String {
                lyricsBrowseId = bId
                break
            }
        }
        
        guard let browseId = lyricsBrowseId, !browseId.isEmpty else { return nil }
        guard let urlBrowse = URL(string: "https://music.youtube.com/youtubei/v1/browse") else { return nil }
        
        var payloadBrowse = clientContext
        payloadBrowse["browseId"] = browseId
        
        let requestBrowse = try makeRequest(url: urlBrowse, body: payloadBrowse)
        guard let (dataBrowse, respBrowse) = try? await session.data(for: requestBrowse),
              (respBrowse as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        
        guard let jsonBrowse = try? JSONSerialization.jsonObject(with: dataBrowse) as? [String: Any],
              let browseContents = jsonBrowse["contents"] as? [String: Any],
              let sectionList = browseContents["sectionListRenderer"] as? [String: Any],
              let secContents = sectionList["contents"] as? [[String: Any]],
              let firstSec = secContents.first,
              let shelf = firstSec["musicDescriptionShelfRenderer"] as? [String: Any],
              let runs = (shelf["description"] as? [String: Any])?["runs"] as? [[String: Any]] else {
            return nil
        }
        
        let plainLyrics = runs.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainLyrics.isEmpty else { return nil }
        
        var footerText = "YouTube Music"
        if let footRuns = (shelf["footer"] as? [String: Any])?["runs"] as? [[String: Any]],
           let firstFoot = footRuns.first?["text"] as? String {
            footerText = "YouTube Music (\(firstFoot))"
        }
        
        return LyricsResultCandidate(
            lyricsText: plainLyrics,
            isSynced: false,
            source: footerText,
            durationValid: true,
            lastTimestamp: nil,
            detectedScript: nil,
            romanizedText: nil
        )
    }
    
    // MARK: - Utilities
    
    public static func rewriteToHighRes(_ urlString: String, videoId: String?) -> String {
        if urlString.contains("googleusercontent.com") {
            // Replace size parameters like =w120-h120-l90-rj or =s120 with 1200x1200
            if let regex = try? NSRegularExpression(pattern: "=[swh]\\d+.*$", options: []) {
                let range = NSRange(urlString.startIndex..., in: urlString)
                return regex.stringByReplacingMatches(in: urlString, range: range, withTemplate: "=w1200-h1200-l90-rj")
            }
            return urlString + "=w1200-h1200-l90-rj"
        }
        if urlString.contains("i.ytimg.com"), let vid = videoId {
            return "https://i.ytimg.com/vi/\(vid)/maxresdefault.jpg"
        }
        return urlString
    }
    
    public static func parseDuration(_ string: String) -> TimeInterval {
        let parts = string.components(separatedBy: ":")
        guard !parts.isEmpty else { return 0 }
        if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
            return (m * 60.0) + s
        } else if parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) {
            return (h * 3600.0) + (m * 60.0) + s
        }
        return 0
    }
}
