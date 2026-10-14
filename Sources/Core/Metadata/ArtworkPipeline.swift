import Foundation
import AppKit
import AVFoundation
import CommonCrypto
import OSLog

/// Unified Artwork Pipeline for Lumo (Phase 4).
/// Provides prioritized artwork resolution across embedded tags, sidecar images,
/// yt-dlp thumbnails, browser extension artwork (with upscale rewrites), iTunes (IN & US),
/// Deezer, and MusicBrainz + Cover Art Archive.
/// Validates online matches (token-set score >= 0.85) and automatically square-crops 16:9 thumbnails.
public actor ArtworkPipeline {
    public static let shared = ArtworkPipeline()
    
    private let cacheDirectory: URL
    private let session: URLSession
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.cacheDirectory = appSupport.appendingPathComponent("Lumo/ArtworkCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 12.0
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public Resolution Entrypoint
    
    public func resolveArtwork(
        fileURL: URL?,
        artist: String,
        title: String,
        album: String = "",
        duration: TimeInterval? = nil,
        extensionArtworkURL: String? = nil,
        stableId: String
    ) async -> Data? {
        let cleanTitle = TitleCleaner.clean(title).cleanedString
        let cleanArtist = TitleCleaner.clean(artist.components(separatedBy: " (feat.").first ?? artist).cleanedString
        let cleanAlbum = TitleCleaner.clean(album).cleanedString
        
        // 0. Disk Cache Check
        if let cached = checkDiskCache(stableId: stableId, artist: cleanArtist, album: cleanAlbum) {
            return cached
        }
        
        // 1. Embedded Artwork (Local Audio)
        if let fileURL = fileURL, fileURL.isFileURL {
            if let embeddedData = await extractEmbeddedArtwork(from: fileURL) {
                let processed = Self.squareCropIfNeeded(data: embeddedData)
                saveToDiskCache(data: processed, stableId: stableId, artist: cleanArtist, album: cleanAlbum)
                return processed
            }
        }
        
        // 2. Sidecar Image (cover.jpg, folder.png, <name>.jpg, etc.)
        if let fileURL = fileURL, fileURL.isFileURL {
            if let sidecarData = checkSidecarImage(fileURL: fileURL) {
                let processed = Self.squareCropIfNeeded(data: sidecarData)
                saveToDiskCache(data: processed, stableId: stableId, artist: cleanArtist, album: cleanAlbum)
                return processed
            }
        }
        
        // 3. yt-dlp .info.json Thumbnail
        if let fileURL = fileURL, fileURL.isFileURL {
            if let ytDlpData = await checkYtDlpThumbnail(fileURL: fileURL) {
                let processed = Self.squareCropIfNeeded(data: ytDlpData)
                saveToDiskCache(data: processed, stableId: stableId, artist: cleanArtist, album: cleanAlbum)
                return processed
            }
        }
        
        // 4. Browser Extension Artwork (Upscaled)
        var lowResFallback: Data? = nil
        if let extArtUrl = extensionArtworkURL, !extArtUrl.isEmpty {
            let rewritten = Self.rewriteArtworkURL(extArtUrl)
            if let extData = await downloadImage(from: rewritten) {
                let processed = Self.squareCropIfNeeded(data: extData)
                if Self.isHighResolution(data: processed) {
                    saveToDiskCache(data: processed, stableId: stableId, artist: cleanArtist, album: cleanAlbum)
                    return processed
                } else {
                    lowResFallback = processed
                }
            }
        }
        
        // 5. iTunes Search (Pass 1: country=IN, Pass 2: country=US, limit=5)
        if !cleanTitle.isEmpty {
            if let itunesData = await fetchFromITunes(artist: cleanArtist, title: cleanTitle) {
                let processed = Self.squareCropIfNeeded(data: itunesData)
                saveToDiskCache(data: processed, stableId: stableId, artist: cleanArtist, album: cleanAlbum)
                return processed
            }
        }
        
        // 6. Deezer Search (limit=5)
        if !cleanTitle.isEmpty {
            if let deezerData = await fetchFromDeezer(artist: cleanArtist, title: cleanTitle) {
                let processed = Self.squareCropIfNeeded(data: deezerData)
                saveToDiskCache(data: processed, stableId: stableId, artist: cleanArtist, album: cleanAlbum)
                return processed
            }
        }
        
        // 7. MusicBrainz + Cover Art Archive
        if !cleanTitle.isEmpty {
            if let mbData = await fetchFromMusicBrainz(artist: cleanArtist, title: cleanTitle) {
                let processed = Self.squareCropIfNeeded(data: mbData)
                saveToDiskCache(data: processed, stableId: stableId, artist: cleanArtist, album: cleanAlbum)
                return processed
            }
        }
        
        // 8. Return low-res fallback if found
        if let fallback = lowResFallback {
            saveToDiskCache(data: fallback, stableId: stableId, artist: cleanArtist, album: cleanAlbum)
            return fallback
        }
        
        return nil
    }
    
    // MARK: - URL Rewriting & Resizing
    
    public static func rewriteArtworkURL(_ urlString: String) -> String {
        var str = urlString
        // 1. Google / YouTube Music thumbnail size parameters:
        // e.g. =w60-h60-l90-rj -> =w1200-h1200-l90-rj
        str = str.replacingOccurrences(of: "(?i)=w\\d+-h\\d+", with: "=w1200-h1200", options: .regularExpression)
        str = str.replacingOccurrences(of: "(?i)=s\\d+(-c)?", with: "=s1200$1", options: .regularExpression)
        
        // 2. YouTube standard thumbnail size suffixes:
        str = str.replacingOccurrences(of: "hqdefault.jpg", with: "maxresdefault.jpg")
        str = str.replacingOccurrences(of: "mqdefault.jpg", with: "maxresdefault.jpg")
        str = str.replacingOccurrences(of: "sddefault.jpg", with: "maxresdefault.jpg")
        return str
    }
    
    public static func isHighResolution(data: Data) -> Bool {
        guard let image = NSImage(data: data) else { return false }
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return image.size.width >= 300 && image.size.height >= 300
        }
        return cgImage.width >= 300 && cgImage.height >= 300
    }
    
    /// Detects non-square aspect ratios (e.g. 16:9 YouTube video thumbnails) and crops a square from the center.
    public static func squareCropIfNeeded(data: Data) -> Data {
        guard let image = NSImage(data: data) else { return data }
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return data
        }
        
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return data }
        
        let ratio = Double(width) / Double(height)
        // If aspect ratio is significantly non-square (outside 0.90 ... 1.10)
        if ratio > 1.10 || ratio < 0.90 {
            let side = min(width, height)
            let xOffset = (width - side) / 2
            let yOffset = (height - side) / 2
            let cropRect = CGRect(x: xOffset, y: yOffset, width: side, height: side)
            
            if let cropped = cgImage.cropping(to: cropRect) {
                let rep = NSBitmapImageRep(cgImage: cropped)
                if let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                    return jpegData
                }
            }
        }
        return data
    }
    
    // MARK: - Embedded & Sidecar Artwork
    
    private func extractEmbeddedArtwork(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        
        for item in metadata {
            if item.commonKey == .commonKeyArtwork ||
               item.identifier?.rawValue.lowercased().contains("covr") == true ||
               item.identifier?.rawValue.lowercased().contains("apic") == true {
                if let data = try? await item.load(.dataValue), !data.isEmpty {
                    return data
                }
            }
        }
        return nil
    }
    
    private func checkSidecarImage(fileURL: URL) -> Data? {
        let parentDir = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        
        let candidateNames = [
            "\(baseName).jpg", "\(baseName).jpeg", "\(baseName).png", "\(baseName).webp",
            "cover.jpg", "cover.jpeg", "cover.png", "cover.webp",
            "folder.jpg", "folder.jpeg", "folder.png", "folder.webp",
            "front.jpg", "front.jpeg", "front.png"
        ]
        
        for name in candidateNames {
            let imgURL = parentDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: imgURL.path),
               let data = try? Data(contentsOf: imgURL), !data.isEmpty {
                return data
            }
        }
        return nil
    }
    
    private func checkYtDlpThumbnail(fileURL: URL) async -> Data? {
        let jsonURL = fileURL.deletingPathExtension().appendingPathExtension("info.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // 1. Look for highest resolution in thumbnails array
        if let thumbnails = json["thumbnails"] as? [[String: Any]], !thumbnails.isEmpty {
            // Sort by width/height or preference for maxresdefault
            let sorted = thumbnails.sorted { a, b in
                let wA = a["width"] as? Int ?? 0
                let wB = b["width"] as? Int ?? 0
                return wA > wB
            }
            for thumb in sorted {
                if let urlStr = thumb["url"] as? String, !urlStr.isEmpty {
                    let rewritten = Self.rewriteArtworkURL(urlStr)
                    if let imgData = await downloadImage(from: rewritten) {
                        return imgData
                    }
                }
            }
        }
        
        // 2. Fall back to "thumbnail" field
        if let thumbStr = json["thumbnail"] as? String, !thumbStr.isEmpty {
            let rewritten = Self.rewriteArtworkURL(thumbStr)
            if let imgData = await downloadImage(from: rewritten) {
                return imgData
            }
        }
        
        return nil
    }
    
    // MARK: - Online Providers (Validated with Token-Set Score >= 0.85)
    
    private func fetchFromITunes(artist: String, title: String) async -> Data? {
        let isUnknown = artist.lowercased() == "unknown" || artist.isEmpty
        let term = isUnknown ? title : "\(artist) \(title)"
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        
        // Try India store first for Indic / regional content, then US
        for country in ["IN", "US"] {
            let urlStr = "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&country=\(country)&limit=5"
            guard let url = URL(string: urlStr) else { continue }
            
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                continue
            }
            
            for item in results {
                guard let resTitle = item["trackName"] as? String,
                      let resArtist = item["artistName"] as? String else { continue }
                
                let score = OnlineVerifier.computeMatchScore(
                    queryArtist: artist,
                    queryTitle: title,
                    resultArtist: resArtist,
                    resultTitle: resTitle
                )
                
                guard score >= 0.85 else { continue }
                
                if let artStr = item["artworkUrl100"] as? String {
                    let highRes = artStr.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")
                    if let imgData = await downloadImage(from: highRes) {
                        return imgData
                    }
                }
            }
        }
        return nil
    }
    
    private func fetchFromDeezer(artist: String, title: String) async -> Data? {
        let isUnknown = artist.lowercased() == "unknown" || artist.isEmpty
        let term = isUnknown ? title : "\(artist) \(title)"
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.deezer.com/search?q=\(encoded)&limit=5") else {
            return nil
        }
        
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            return nil
        }
        
        for item in items {
            guard let resTitle = item["title"] as? String,
                  let artistObj = item["artist"] as? [String: Any],
                  let resArtist = artistObj["name"] as? String else { continue }
            
            let score = OnlineVerifier.computeMatchScore(
                queryArtist: artist,
                queryTitle: title,
                resultArtist: resArtist,
                resultTitle: resTitle
            )
            
            guard score >= 0.85 else { continue }
            
            let albumObj = item["album"] as? [String: Any]
            if let coverUrlStr = (albumObj?["cover_xl"] ?? albumObj?["cover_big"] ?? albumObj?["cover_medium"]) as? String {
                if let imgData = await downloadImage(from: coverUrlStr) {
                    return imgData
                }
            }
        }
        return nil
    }
    
    private func fetchFromMusicBrainz(artist: String, title: String) async -> Data? {
        let isUnknown = artist.lowercased() == "unknown" || artist.isEmpty
        let queryStr = isUnknown ? "recording:\(title)" : "recording:\(title) AND artist:\(artist)"
        guard let encoded = queryStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://musicbrainz.org/ws/2/recording/?query=\(encoded)&fmt=json&limit=5") else {
            return nil
        }
        
        var req = URLRequest(url: url)
        req.setValue("Lumo/1.0.0 (contact@lumo.internal)", forHTTPHeaderField: "User-Agent")
        
        guard let (data, response) = try? await session.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recordings = json["recordings"] as? [[String: Any]] else {
            return nil
        }
        
        for rec in recordings {
            guard let resTitle = rec["title"] as? String else { continue }
            var resArtist = "Unknown"
            if let credits = rec["artist-credit"] as? [[String: Any]],
               let first = credits.first,
               let name = first["name"] as? String {
                resArtist = name
            }
            
            let score = OnlineVerifier.computeMatchScore(
                queryArtist: artist,
                queryTitle: title,
                resultArtist: resArtist,
                resultTitle: resTitle
            )
            
            guard score >= 0.85 else { continue }
            
            if let releases = rec["releases"] as? [[String: Any]] {
                for rel in releases.prefix(10) {
                    if let relId = rel["id"] as? String {
                        let caaUrl = "https://coverartarchive.org/release/\(relId)/front-500"
                        if let imgData = await downloadImage(from: caaUrl) {
                            return imgData
                        }
                    }
                }
            }
        }
        
        // If not found and artist is known, try swapped query
        if !isUnknown {
            let swappedQuery = "recording:\(artist) AND artist:\(title)"
            if let encSwapped = swappedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let swappedUrl = URL(string: "https://musicbrainz.org/ws/2/recording/?query=\(encSwapped)&fmt=json&limit=5") {
                var sReq = URLRequest(url: swappedUrl)
                sReq.setValue("Lumo/1.0.0 (contact@lumo.internal)", forHTTPHeaderField: "User-Agent")
                if let (sData, sResp) = try? await session.data(for: sReq),
                   (sResp as? HTTPURLResponse)?.statusCode == 200,
                   let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
                   let sRecordings = sJson["recordings"] as? [[String: Any]] {
                    for sRec in sRecordings {
                        if let sReleases = sRec["releases"] as? [[String: Any]] {
                            for sRel in sReleases.prefix(5) {
                                if let sRelId = sRel["id"] as? String {
                                    let caaUrl = "https://coverartarchive.org/release/\(sRelId)/front-500"
                                    if let imgData = await downloadImage(from: caaUrl) {
                                        return imgData
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Helpers & Disk Cache
    
    private func downloadImage(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty else {
            // If maxresdefault failed (404), fall back to hqdefault
            if urlString.contains("maxresdefault.jpg") {
                let fallback = urlString.replacingOccurrences(of: "maxresdefault.jpg", with: "hqdefault.jpg")
                return await downloadImage(from: fallback)
            }
            return nil
        }
        return data
    }
    
    public func checkDiskCache(stableId: String, artist: String, album: String) -> Data? {
        if !stableId.isEmpty {
            let idFile = cacheDirectory.appendingPathComponent("\(sanitizeFilename(stableId)).jpg")
            if FileManager.default.fileExists(atPath: idFile.path),
               let data = try? Data(contentsOf: idFile), !data.isEmpty {
                return data
            }
        }
        
        let metaKey = normalizedKey(artist: artist, album: album)
        if !metaKey.isEmpty {
            let metaFile = cacheDirectory.appendingPathComponent("\(sanitizeFilename(metaKey)).jpg")
            if FileManager.default.fileExists(atPath: metaFile.path),
               let data = try? Data(contentsOf: metaFile), !data.isEmpty {
                return data
            }
        }
        return nil
    }
    
    public func saveToDiskCache(data: Data, stableId: String, artist: String, album: String) {
        if !stableId.isEmpty {
            let idFile = cacheDirectory.appendingPathComponent("\(sanitizeFilename(stableId)).jpg")
            try? data.write(to: idFile, options: .atomic)
        }
        let metaKey = normalizedKey(artist: artist, album: album)
        if !metaKey.isEmpty {
            let metaFile = cacheDirectory.appendingPathComponent("\(sanitizeFilename(metaKey)).jpg")
            try? data.write(to: metaFile, options: .atomic)
        }
    }
    
    public func clearDiskCache(for stableId: String) {
        if !stableId.isEmpty {
            let idFile = cacheDirectory.appendingPathComponent("\(sanitizeFilename(stableId)).jpg")
            try? FileManager.default.removeItem(at: idFile)
        }
    }
    
    public func setManualArtwork(data: Data, stableId: String, artist: String, album: String) {
        let processed = Self.squareCropIfNeeded(data: data)
        saveToDiskCache(data: processed, stableId: stableId, artist: artist, album: album)
    }
    
    public func setManualArtworkFromURL(_ url: URL, stableId: String, artist: String, album: String) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty else { return nil }
        let processed = Self.squareCropIfNeeded(data: data)
        saveToDiskCache(data: processed, stableId: stableId, artist: artist, album: album)
        return processed
    }
    
    private func normalizedKey(artist: String, album: String) -> String {
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let alb = album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if a.isEmpty && alb.isEmpty { return "" }
        return "\(a)_\(alb)"
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet.alphanumerics.inverted
        let sanitized = name.components(separatedBy: invalid).joined(separator: "_")
        return sanitized.isEmpty ? "artwork" : sanitized
    }
}
