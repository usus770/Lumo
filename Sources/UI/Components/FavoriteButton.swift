import SwiftUI

/// A toggle button that reads and writes the `isFavorite` field for a track.
/// Can be placed anywhere — NowPlayingBar, song row, detail view, etc.
struct FavoriteButton: View {
    let trackId: UUID
    @State private var isFavorite: Bool = false

    var body: some View {
        Button {
            toggleFavorite()
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 12))
                .foregroundStyle(isFavorite ? LumoColors.accent : LumoColors.textSecondary)
                .scaleEffect(isFavorite ? 1.1 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isFavorite)
        }
        .buttonStyle(LumoIconButtonStyle(size: 24))
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .onAppear(perform: loadState)
        .onReceive(NotificationCenter.default.publisher(for: .favoritesDidChange)) { _ in
            loadState()
        }
    }

    private func loadState() {
        Task {
            let tracks = await PersistenceStore.shared.loadAll(Track.self)
            let fav = tracks.first(where: { $0.id == trackId })?.isFavorite ?? false
            await MainActor.run { self.isFavorite = fav }
        }
    }

    private func toggleFavorite() {
        let newValue = !isFavorite
        isFavorite = newValue   // Optimistic UI update
        Task {
            var allTracks = await PersistenceStore.shared.loadAll(Track.self)
            if let idx = allTracks.firstIndex(where: { $0.id == trackId }) {
                allTracks[idx].isFavorite = newValue
                try? await PersistenceStore.shared.saveAll(allTracks)
            }
            await MainActor.run {
                NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
            }
        }
    }
}
