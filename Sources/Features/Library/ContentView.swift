import SwiftUI

/// Routes sidebar selection to the appropriate content view.
struct ContentView: View {
    @Environment(WindowManager.self) private var windowManager
    @State private var searchText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Content header with search
            contentHeader
            
            Divider()
                .background(LumoTheme.stroke)
            
            // Routed content
            contentBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LumoTheme.bg1)
    }
    
    // MARK: - Header
    
    private var contentHeader: some View {
        HStack(spacing: 16) {
            // Section title
            Text(windowManager.selectedSection.rawValue)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(LumoTheme.textPrimary)
            
            Spacer()
            
            SearchBar(text: $searchText, placeholder: "Search \(windowManager.selectedSection.rawValue.lowercased())…")
                .frame(maxWidth: 260)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    // MARK: - Content Router
    
    @ViewBuilder
    private var contentBody: some View {
        switch windowManager.selectedSection {
        case .songs:
            SongsListView(searchText: searchText)
        case .albums:
            AlbumsView()
        case .artists:
            ArtistsView()
        case .genres:
            GenresView()
        case .folders:
            FoldersView()
        case .recentlyAdded:
            RecentlyAddedView()
        case .mostPlayed:
            MostPlayedView()
        case .favorites:
            FavoritesView()
        case .needsReview:
            NeedsReviewView()
        case .playlists:
            PlaylistsView(searchText: searchText)
        }
    }
}

// MARK: - Placeholder & Empty State Views

/// Placeholder for the songs list.
struct SongsListPlaceholder: View {
    var onAddFolder: () -> Void
    
    var body: some View {
        EmptyLibraryView(
            title: "No Songs Yet",
            subtitle: "Add a folder or drag and drop audio files to build your high-resolution library.",
            actionLabel: "Add Music Folder",
            action: onAddFolder
        )
    }
}

/// Placeholder for the albums grid.
struct AlbumsGridPlaceholder: View {
    var body: some View {
        EmptyLibraryView(
            title: "No Albums Found",
            subtitle: "Albums will automatically appear once you import music.",
            actionLabel: "Import Music"
        ) {
            NotificationCenter.default.post(name: Notification.Name("LumoTriggerAddFolder"), object: nil)
        }
    }
}

/// Placeholder for the artists list.
struct ArtistsListPlaceholder: View {
    var body: some View {
        EmptyLibraryView(
            title: "No Artists Found",
            subtitle: "Artists are cataloged as songs and albums are added.",
            actionLabel: "Import Music"
        ) {
            NotificationCenter.default.post(name: Notification.Name("LumoTriggerAddFolder"), object: nil)
        }
    }
}

/// Placeholder for the folders view with add-folder CTA.
struct FoldersPlaceholder: View {
    var body: some View {
        EmptyLibraryView(
            title: "Watch Folders",
            subtitle: "Add folders and Lumo will automatically watch and sync them.",
            actionLabel: "Add Folder"
        ) {
            NotificationCenter.default.post(name: Notification.Name("LumoTriggerAddFolder"), object: nil)
        }
    }
}

/// Generic empty state view with lumo-mark at 40% opacity, friendly line, and action button.
struct GenericPlaceholder: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    
    init(icon: String = "music.note", title: String, subtitle: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionLabel = actionLabel
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // Brand mark at 40% opacity
            LumoMarkView(size: 80, opacity: 0.40, isAnimated: false)
            
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(LumoTheme.textPrimary)
                
                Text(subtitle)
                    .font(LumoTheme.Typography.body)
                    .foregroundStyle(LumoTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            
            if let label = actionLabel, let act = action {
                Button(action: act) {
                    Text(label)
                }
                .buttonStyle(.lumoPrimary)
                .padding(.top, 4)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LumoTheme.bg1)
    }
}

/// Empty state view showing the lumo-mark in large size at 40% opacity with a friendly line and one clear action button.
struct EmptyLibraryView: View {
    var icon: String = "music.note"
    let title: String
    let subtitle: String
    let actionLabel: String
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Lumo mark at 40% opacity
            LumoMarkView(size: 92, opacity: 0.40, isAnimated: false)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LumoTheme.textPrimary)
                
                Text(subtitle)
                    .font(LumoTheme.Typography.body)
                    .foregroundStyle(LumoTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            
            Button(action: action) {
                Label(actionLabel, systemImage: "plus")
            }
            .buttonStyle(.lumoPrimary)
            .padding(.top, 6)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LumoTheme.bg1)
    }
}
