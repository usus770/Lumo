import Foundation

/// A user-created playlist.
struct Playlist: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    
    /// Playlist name.
    var name: String
    
    /// Optional description.
    var descriptionText: String
    
    /// Artwork hash for this playlist.
    var artworkHash: String?
    
    /// When the playlist was created.
    var createdAt: Date
    
    /// When the playlist was last modified.
    var modifiedAt: Date
    
    /// Ordered entries in this playlist.
    var entries: [PlaylistEntry]
    
    init(name: String, descriptionText: String = "") {
        self.id = UUID()
        self.name = name
        self.descriptionText = descriptionText
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.entries = []
    }
}

extension Playlist {
    /// Entries sorted by their order index.
    var sortedEntries: [PlaylistEntry] {
        entries.sorted { $0.orderIndex < $1.orderIndex }
    }
    
    var trackCount: Int { entries.count }
}
