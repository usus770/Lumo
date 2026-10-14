import Foundation

/// Represents an album, grouping tracks with the same album title and album artist.
struct Album: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    
    /// Album title.
    var title: String
    
    /// Album artist name (may differ from track artist for compilations).
    var albumArtist: String
    
    /// Release year.
    var year: Int
    
    /// Number of discs.
    var discCount: Int
    
    /// Genre name (from the majority of tracks).
    var genreName: String
    
    /// Artwork hash (artwork stored separately on disk).
    var artworkHash: String?
    
    /// When the album was first added to the library.
    var addedAt: Date
    
    /// IDs of tracks belonging to this album.
    var trackIds: [UUID]
    
    /// Artist ID.
    var artistId: UUID?
    
    init(title: String, albumArtist: String = "", year: Int = 0) {
        self.id = UUID()
        self.title = title
        self.albumArtist = albumArtist
        self.year = year
        self.discCount = 1
        self.genreName = ""
        self.addedAt = Date()
        self.trackIds = []
    }
}

extension Album {
    /// Display title with fallback.
    var displayTitle: String {
        title.isEmpty ? "Unknown Album" : title
    }
    
    /// Display artist with fallback.
    var displayArtist: String {
        albumArtist.isEmpty ? "Various Artists" : albumArtist
    }
    
    var trackCount: Int {
        trackIds.count
    }
}
