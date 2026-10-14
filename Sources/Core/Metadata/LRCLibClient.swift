import Foundation

/// Client for LRCLIB API to fetch synced or plain lyrics.
public enum LRCLibClient {
    
    public struct LRCLibResponse: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }
    
    /// Fetches lyrics from LRCLIB for a given artist, title, and optional album/duration.
    /// - Returns: A tuple containing the best lyrics found (synced preferred) and a boolean indicating if it's synced.
    public static func fetchLyrics(artist: String, title: String, album: String? = nil, duration: TimeInterval = 0) async throws -> (lyrics: String, isSynced: Bool)? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ]
        
        if let album = album, !album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: album))
        }
        if duration > 1 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        
        components.queryItems = queryItems
        guard let url = components.url else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("LumoMusicPlayer/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let lrcResponse = try decoder.decode(LRCLibResponse.self, from: data)
        
        if let synced = lrcResponse.syncedLyrics, !synced.isEmpty {
            return (synced, true)
        } else if let plain = lrcResponse.plainLyrics, !plain.isEmpty {
            return (plain, false)
        }
        
        return nil
    }
    
    /// Checks for an existing .lrc file next to the given audio URL, or attempts to fetch and save one.
    public static func getOrFetchLyrics(for audioURL: URL, artist: String, title: String, album: String? = nil, duration: TimeInterval = 0) async -> (lyrics: String, isSynced: Bool)? {
        let lrcURL = audioURL.deletingPathExtension().appendingPathExtension("lrc")
        let txtURL = audioURL.deletingPathExtension().appendingPathExtension("txt")
        
        // 1. Check local cache (.lrc for synced, .txt for plain)
        if FileManager.default.fileExists(atPath: lrcURL.path), let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
            return (content, true)
        }
        
        if FileManager.default.fileExists(atPath: txtURL.path), let content = try? String(contentsOf: txtURL, encoding: .utf8) {
            return (content, false)
        }
        
        // 2. Fetch from API
        do {
            if let result = try await fetchLyrics(artist: artist, title: title, album: album, duration: duration) {
                // 3. Cache locally
                let targetURL = result.isSynced ? lrcURL : txtURL
                try? result.lyrics.write(to: targetURL, atomically: true, encoding: .utf8)
                return result
            }
        } catch {
            print("LRCLibClient fetch error: \(error)")
        }
        
        return nil
    }
}
