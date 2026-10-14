import SwiftUI

/// Manages window state across the app: which windows are visible,
/// sidebar selection, and navigation state.
@Observable
final class WindowManager: @unchecked Sendable {
    static let shared = WindowManager()
    
    private init() {}
    
    /// Currently selected sidebar section.
    var selectedSection: SidebarSection = .songs
    
    /// Whether the now-playing detail panel is expanded.
    var isNowPlayingExpanded: Bool = false
    
    /// Whether the queue (Up Next) panel is visible.
    var isQueueVisible: Bool = false
    
    /// Whether the mini player floating window is visible.
    var isMiniPlayerVisible: Bool = false
    
    /// Whether the lyrics view is visible.
    /// Whether the lyrics view is visible.
    var isLyricsVisible: Bool = false
    
    /// Whether the visualizer window is visible.
    var isVisualizerPresented: Bool = false
    
    /// Global library track count
    var totalTrackCount: Int = 0
    
    /// Filtered library track count (e.g. from search or quality filters)
    var filteredTrackCount: Int = 0
}

// MARK: - Sidebar Sections

/// All navigable sections in the library sidebar.
enum SidebarSection: String, CaseIterable, Identifiable {
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"
    case genres = "Genres"
    case folders = "Folders"
    case recentlyAdded = "Recently Added"
    case mostPlayed = "Most Played"
    case favorites = "Favorites"
    case needsReview = "Needs Review"
    case playlists = "Playlists"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .songs: "music.note"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .genres: "guitars"
        case .folders: "folder"
        case .recentlyAdded: "clock"
        case .mostPlayed: "chart.bar"
        case .favorites: "heart"
        case .needsReview: "exclamationmark.triangle"
        case .playlists: "music.note.list"
        }
    }
    
    /// Group label for sidebar organization.
    var group: SidebarGroup {
        switch self {
        case .songs, .albums, .artists, .genres, .folders:
            return .library
        case .recentlyAdded, .mostPlayed, .favorites, .needsReview:
            return .discover
        case .playlists:
            return .playlists
        }
    }
}

/// Grouping for sidebar sections.
enum SidebarGroup: String, CaseIterable {
    case library = "Library"
    case discover = "Discover"
    case playlists = "Playlists"
    
    var sections: [SidebarSection] {
        SidebarSection.allCases.filter { $0.group == self }
    }
}
