import Foundation

/// Backward-compatible wrapper delegating to ArtworkPipeline.
actor ArtworkResolver {
    static let shared = ArtworkResolver()
    private init() {}
    
    func resolveArtwork(url: URL, metadata: MetadataParser.ParsedMetadata, artist: String? = nil, title: String? = nil, album: String? = nil) async -> Data? {
        // 1. If embedded artwork is already in metadata, square-crop and return
        if let data = metadata.artworkData, !data.isEmpty {
            return ArtworkPipeline.squareCropIfNeeded(data: data)
        }
        
        let chosenArtist = (artist?.isEmpty == false && artist?.lowercased() != "unknown") ? artist! : metadata.artist
        let chosenTitle = (title?.isEmpty == false && title?.lowercased() != "unknown") ? title! : metadata.title
        let chosenAlbum = (album?.isEmpty == false && album?.lowercased() != "unknown") ? album! : metadata.album
        
        let stableId = NowPlayingSnapshot.stableIDForLocal(filePath: url.path)
        return await ArtworkPipeline.shared.resolveArtwork(
            fileURL: url,
            artist: chosenArtist,
            title: chosenTitle,
            album: chosenAlbum,
            duration: metadata.duration,
            extensionArtworkURL: nil,
            stableId: stableId
        )
    }
}
