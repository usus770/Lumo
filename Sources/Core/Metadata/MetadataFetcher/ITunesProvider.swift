import Foundation
import AppKit

/// Fallback provider for high-resolution 1200x1200 album artwork and Apple Music catalog metadata.
public actor ITunesProvider: MetadataProvider {
    public static let shared = ITunesProvider()
    
    public let name = "iTunes / Apple Music"
    private let session: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 12.0
        self.session = URLSession(configuration: config)
    }
    
    public func search(query: String) async throws -> [MetadataSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=10") else {
            return []
        }
        
        var req = URLRequest(url: url)
        req.setValue("Lumo/1.0", forHTTPHeaderField: "User-Agent")
        
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        
        return results.compactMap { item in
            guard let trackName = item["trackName"] as? String,
                  let artistName = item["artistName"] as? String else { return nil }
            
            let album = item["collectionName"] as? String ?? ""
            let millis = item["trackTimeMillis"] as? Double ?? 0
            let duration = millis / 1000.0
            let art100 = item["artworkUrl100"] as? String
            let highRes = art100?.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")
            let trackId = item["trackId"].map { "\($0)" } ?? UUID().uuidString
            
            return MetadataSearchResult(
                id: trackId,
                videoId: nil,
                title: trackName,
                artist: artistName,
                album: album,
                duration: duration,
                thumbnailURL: art100,
                highResArtworkURL: highRes,
                matchScore: 0.0,
                isSquareArtwork: true,
                source: "iTunes"
            )
        }
    }
    
    public func lookupVideoId(_ videoId: String) async throws -> MetadataSearchResult? {
        return nil
    }
    
    public func fetchCoverArt(for result: MetadataSearchResult) async throws -> CoverArtCandidate? {
        guard let urlStr = result.highResArtworkURL ?? result.thumbnailURL,
              let url = URL(string: urlStr) else { return nil }
        
        var req = URLRequest(url: url)
        req.timeoutInterval = 10.0
        
        if let (data, resp) = try? await session.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           !data.isEmpty,
           let image = NSImage(data: data) {
            
            let cropped = ArtworkPipeline.squareCropIfNeeded(data: data)
            return CoverArtCandidate(
                data: cropped,
                source: "iTunes",
                isHighRes: image.size.width >= 500,
                isSquare: true,
                isVideoThumbnail: false
            )
        }
        return nil
    }
    
    public func fetchLyrics(for result: MetadataSearchResult, duration: TimeInterval?) async throws -> LyricsResultCandidate? {
        // iTunes Search API does not provide lyrics
        return nil
    }
}
