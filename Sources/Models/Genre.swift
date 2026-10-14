import Foundation

/// Represents a music genre.
struct Genre: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    
    /// Genre name.
    var name: String
    
    /// IDs of tracks in this genre.
    var trackIds: [UUID]
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.trackIds = []
    }
}

extension Genre {
    var displayName: String {
        name.isEmpty ? "Unknown Genre" : name
    }
    
    var trackCount: Int { trackIds.count }
}
