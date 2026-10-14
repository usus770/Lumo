import Foundation
import AppKit

/// Retrieves artwork image from the hashed cache on disk or unified ArtworkCache.
struct ArtworkCache {
    static func load(hash: String?, filePath: String? = nil) -> Data? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if let hash = hash, !hash.isEmpty {
            let fileURL = appSupport.appendingPathComponent("Lumo/Artwork/\(hash).jpg")
            if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
                return data
            }
        }
        if let path = filePath, !path.isEmpty {
            let stableId = NowPlayingSnapshot.stableIDForLocal(filePath: path)
            let cacheURL = appSupport.appendingPathComponent("Lumo/ArtworkCache/\(stableId).jpg")
            if let data = try? Data(contentsOf: cacheURL), !data.isEmpty {
                return data
            }
        }
        return nil
    }
}
