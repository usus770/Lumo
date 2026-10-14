import Foundation

/// Entry in a playlist, linking to a track by ID with an order index.
struct PlaylistEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    
    /// Position in the playlist (0-based).
    var orderIndex: Int
    
    /// When this entry was added.
    var addedAt: Date
    
    /// ID of the referenced track.
    var trackId: UUID
    
    init(orderIndex: Int, trackId: UUID) {
        self.id = UUID()
        self.orderIndex = orderIndex
        self.addedAt = Date()
        self.trackId = trackId
    }
}
