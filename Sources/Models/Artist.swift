import Foundation

/// Represents a music artist.
struct Artist: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    
    /// Artist name.
    var name: String
    
    /// Sort name (e.g. "Beatles, The" for "The Beatles").
    var sortName: String
    
    /// Artwork hash (stored separately on disk).
    var artworkHash: String?
    
    /// IDs of tracks by this artist.
    var trackIds: [UUID]
    
    /// IDs of albums by this artist.
    var albumIds: [UUID]
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.sortName = name
        self.trackIds = []
        self.albumIds = []
    }
}

extension Artist {
    var displayName: String {
        name.isEmpty ? "Unknown Artist" : name
    }
    
    var trackCount: Int { trackIds.count }
    var albumCount: Int { albumIds.count }
}
