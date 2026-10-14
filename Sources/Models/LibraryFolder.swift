import Foundation

/// Represents a watched library folder added by the user.
struct LibraryFolder: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    
    /// Display path for the folder.
    var path: String
    
    /// Security-scoped bookmark data for sandbox access.
    var bookmarkData: Data
    
    /// Whether this folder should be watched for changes via FSEvents.
    var isWatched: Bool
    
    /// When the folder was added.
    var addedAt: Date
    
    /// Last time this folder was fully scanned.
    var lastScannedAt: Date?
    
    /// Number of tracks found in this folder tree.
    var trackCount: Int
    
    /// IDs of tracks in this folder.
    var trackIds: [UUID]
    
    init(path: String, bookmarkData: Data) {
        self.id = UUID()
        self.path = path
        self.bookmarkData = bookmarkData
        self.isWatched = true
        self.addedAt = Date()
        self.trackCount = 0
        self.trackIds = []
    }
}

extension LibraryFolder {
    /// Resolves the security-scoped URL from the stored bookmark.
    func resolveURL() -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        
        if isStale {
            // TODO: Log stale bookmark warning and re-save (M2)
        }
        
        return url
    }
}
