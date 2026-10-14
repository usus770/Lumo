import SwiftUI

/// Shows recently added tracks, sorted by addedAt descending.
struct RecentlyAddedView: View {
    @State private var tracks: [Track] = []
    @State private var playlists: [Playlist] = []
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var pendingPlaylistTracks = Set<Track.ID>()
    @Environment(PlaybackState.self) private var playbackState

    var body: some View {
        Group {
            if tracks.isEmpty {
                GenericPlaceholder(
                    icon: "clock",
                    title: "No Recent Tracks",
                    subtitle: "Add music to your library to see recent additions"
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
        .onReceive(NotificationCenter.default.publisher(for: .playlistsDidChange)) { _ in
            loadPlaylists()
        }
        .sheet(isPresented: $showNewPlaylistAlert) {
            NewPlaylistSheet(initialTracks: Array(pendingPlaylistTracks), isPresented: $showNewPlaylistAlert)
        }
    }

    private var trackTable: some View {
        Table(tracks) {
            TableColumn("Title") { track in
                HStack {
                    ArtworkView(data: ArtworkCache.load(hash: track.artworkHash), fallbackTitle: track.displayTitle, size: 32, cornerRadius: 4)
                    Text(track.displayTitle)
                        .font(LumoFonts.bodyMedium.weight(.medium))
                }
            }
            TableColumn("Artist", value: \.displayArtist)
            TableColumn("Album", value: \.displayAlbum)
            TableColumn("Added") { track in
                Text(track.addedAt, style: .relative)
                    .font(LumoFonts.micro)
                    .foregroundStyle(LumoColors.textTertiary)
            }
            .width(100)
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
        } primaryAction: { selection in
            playSelected(selection)
        }
    }

    private func loadTracks() {
        Task {
            let loaded = await PersistenceStore.shared.loadAll(Track.self)
            await MainActor.run {
                // Show the 200 most recently added
                self.tracks = loaded
                    .sorted { $0.addedAt > $1.addedAt }
                    .prefix(200)
                    .map { $0 }
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
              let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        let infos = tracks.map { makeInfo($0) }
        playbackState.play(tracks: infos, startingAt: index)
    }

    private func queueSelectedNext(_ ids: Set<Track.ID>) {
        for id in ids.reversed() {
            if let t = tracks.first(where: { $0.id == id }) {
                playbackState.insertNext(track: makeInfo(t))
            }
        }
    }

    private func addSelectedToQueue(_ ids: Set<Track.ID>) {
        for id in ids {
            if let t = tracks.first(where: { $0.id == id }) {
                playbackState.appendToQueue(track: makeInfo(t))
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

// MARK: - Most Played

/// Shows tracks sorted by playCount descending.
struct MostPlayedView: View {
    @State private var tracks: [Track] = []
    @State private var playlists: [Playlist] = []
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var pendingPlaylistTracks = Set<Track.ID>()
    @Environment(PlaybackState.self) private var playbackState

    var body: some View {
        Group {
            if tracks.isEmpty {
                GenericPlaceholder(
                    icon: "chart.bar",
                    title: "Nothing Played Yet",
                    subtitle: "Your most-played tracks will appear here"
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
        .onReceive(NotificationCenter.default.publisher(for: .playCountDidChange)) { _ in
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
        Table(tracks) {
            TableColumn("#") { track in
                if let idx = tracks.firstIndex(of: track) {
                    Text("\(idx + 1)")
                        .font(LumoFonts.micro)
                        .foregroundStyle(LumoColors.textTertiary)
                }
            }
            .width(30)
            TableColumn("Title") { track in
                HStack {
                    ArtworkView(data: ArtworkCache.load(hash: track.artworkHash), fallbackTitle: track.displayTitle, size: 32, cornerRadius: 4)
                    Text(track.displayTitle)
                        .font(LumoFonts.bodyMedium.weight(.medium))
                }
            }
            TableColumn("Artist", value: \.displayArtist)
            TableColumn("Plays") { track in
                Text("\(track.playCount)")
                    .font(LumoFonts.bodyMedium)
                    .foregroundStyle(track.playCount > 0 ? LumoColors.textPrimary : LumoColors.textTertiary)
            }
            .width(60)
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
        } primaryAction: { selection in
            playSelected(selection)
        }
    }

    private func loadTracks() {
        Task {
            let loaded = await PersistenceStore.shared.loadAll(Track.self)
            await MainActor.run {
                // Show top 200 by playCount, excluding unplayed
                self.tracks = loaded
                    .filter { $0.playCount > 0 }
                    .sorted { $0.playCount > $1.playCount }
                    .prefix(200)
                    .map { $0 }
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
              let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        let infos = tracks.map { makeInfo($0) }
        playbackState.play(tracks: infos, startingAt: index)
    }

    private func queueSelectedNext(_ ids: Set<Track.ID>) {
        for id in ids.reversed() {
            if let t = tracks.first(where: { $0.id == id }) {
                playbackState.insertNext(track: makeInfo(t))
            }
        }
    }

    private func addSelectedToQueue(_ ids: Set<Track.ID>) {
        for id in ids {
            if let t = tracks.first(where: { $0.id == id }) {
                playbackState.appendToQueue(track: makeInfo(t))
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
    static let playCountDidChange = Notification.Name("playCountDidChange")
}
