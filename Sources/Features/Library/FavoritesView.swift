import SwiftUI

/// Shows tracks the user has favorited (heart icon).
struct FavoritesView: View {
    @State private var tracks: [Track] = []
    @State private var playlists: [Playlist] = []
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var pendingPlaylistTracks = Set<Track.ID>()
    @Environment(PlaybackState.self) private var playbackState

    private var favoriteTracks: [Track] {
        tracks.filter { $0.isFavorite }
    }

    var body: some View {
        Group {
            if favoriteTracks.isEmpty {
                GenericPlaceholder(
                    icon: "heart",
                    title: "No Favorites Yet",
                    subtitle: "Tap the heart icon on any track to add it here"
                )
            } else {
                trackTable
            }
        }
        .onAppear {
            loadTracks()
            loadPlaylists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            loadTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .favoritesDidChange)) { _ in
            loadTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistsDidChange)) { _ in
            loadPlaylists()
        }
        .sheet(isPresented: $showNewPlaylistAlert) {
            NewPlaylistSheet(initialTracks: Array(pendingPlaylistTracks), isPresented: $showNewPlaylistAlert)
        }
    }

    private var trackTable: some View {
        Table(favoriteTracks) {
            TableColumn("Title") { track in
                HStack {
                    ArtworkView(data: ArtworkCache.load(hash: track.artworkHash), fallbackTitle: track.displayTitle, size: 32, cornerRadius: 4)
                    Text(track.displayTitle)
                        .font(LumoFonts.bodyMedium.weight(.medium))
                }
            }
            TableColumn("Artist", value: \.displayArtist)
            TableColumn("Album", value: \.displayAlbum)
            TableColumn("Time", value: \.formattedDuration)
        }
        .contextMenu(forSelectionType: Track.ID.self) { selection in
            Button("Play") { playSelected(selection) }
            Button("Play Next") { queueSelectedNext(selection) }
            Button("Add to Queue") { addSelectedToQueue(selection) }
            Divider()
            Menu {
                Button {
                    pendingPlaylistTracks = selection
                    newPlaylistName = ""
                    showNewPlaylistAlert = true
                } label: {
                    Label("New Playlist...", systemImage: "plus")
                }
                if !playlists.isEmpty {
                    Divider()
                    ForEach(playlists) { playlist in
                        Button(playlist.name) {
                            Task {
                                await PlaylistManager.shared.addTracks(trackIDs: selection, toPlaylist: playlist.id)
                            }
                        }
                    }
                }
            } label: {
                Label("Add to Playlist", systemImage: "music.note.list")
            }
            Divider()
            Button("Remove from Favorites") { unfavorite(selection) }
        } primaryAction: { selection in
            playSelected(selection)
        }
    }

    private func loadTracks() {
        Task {
            let loaded = await PersistenceStore.shared.loadAll(Track.self)
            await MainActor.run {
                self.tracks = loaded.sorted { $0.displayTitle < $1.displayTitle }
            }
        }
    }

    private func loadPlaylists() {
        Task {
            let loaded = await PlaylistManager.shared.loadAll()
            await MainActor.run {
                self.playlists = loaded
            }
        }
    }

    private func playSelected(_ ids: Set<Track.ID>) {
        guard let id = ids.first,
              let index = favoriteTracks.firstIndex(where: { $0.id == id }) else { return }
        let infos = favoriteTracks.map { makeInfo($0) }
        playbackState.play(tracks: infos, startingAt: index)
    }

    private func queueSelectedNext(_ ids: Set<Track.ID>) {
        for id in ids.reversed() {
            if let t = favoriteTracks.first(where: { $0.id == id }) {
                playbackState.insertNext(track: makeInfo(t))
            }
        }
    }

    private func addSelectedToQueue(_ ids: Set<Track.ID>) {
        for id in ids {
            if let t = favoriteTracks.first(where: { $0.id == id }) {
                playbackState.appendToQueue(track: makeInfo(t))
            }
        }
    }

    private func unfavorite(_ ids: Set<Track.ID>) {
        Task {
            var allTracks = await PersistenceStore.shared.loadAll(Track.self)
            for id in ids {
                if let idx = allTracks.firstIndex(where: { $0.id == id }) {
                    allTracks[idx].isFavorite = false
                }
            }
            try? await PersistenceStore.shared.saveAll(allTracks)
            await MainActor.run {
                NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
            }
        }
    }

    private func makeInfo(_ t: Track) -> TrackInfo {
        TrackInfo(
            id: t.id, title: t.displayTitle, artist: t.displayArtist,
            album: t.displayAlbum, duration: t.duration,
            artworkData: ArtworkCache.load(hash: t.artworkHash),
            filePath: t.filePath, fileExtension: t.fileExtension,
            lyricsText: t.lyricsText, hasSyncedLyrics: t.hasSyncedLyrics
        )
    }
}

extension Notification.Name {
    static let favoritesDidChange = Notification.Name("favoritesDidChange")
}
