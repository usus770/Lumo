import SwiftUI

/// Shows genres with track counts, tap to see tracks in that genre.
struct GenresView: View {
    @State private var genres: [Genre] = []
    @State private var tracks: [Track] = []
    @State private var selectedGenre: Genre?
    @Environment(PlaybackState.self) private var playbackState

    var body: some View {
        Group {
            if genres.isEmpty {
                GenericPlaceholder(
                    icon: "guitars",
                    title: "No Genres",
                    subtitle: "Genres will appear here as you add music to your library"
                )
            } else if let genre = selectedGenre {
                GenreDetailView(
                    genre: genre,
                    allTracks: tracks
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedGenre = nil }
                }
            } else {
                genreList
            }
        }
        .onAppear(perform: loadData)
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            loadData()
        }
    }

    // MARK: - List

    private var genreList: some View {
        List(genres, id: \.id) { genre in
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { selectedGenre = genre }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "guitars.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(LumoColors.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(genre.displayName)
                            .font(LumoFonts.bodyMedium.weight(.semibold))
                            .foregroundStyle(LumoColors.textPrimary)

                        Text("\(genre.trackCount) song\(genre.trackCount == 1 ? "" : "s")")
                            .font(LumoFonts.micro)
                            .foregroundStyle(LumoColors.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(LumoColors.textTertiary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .lumoHover()
        }
        .listStyle(.plain)
    }

    // MARK: - Data

    private func loadData() {
        Task {
            let g = await PersistenceStore.shared.loadAll(Genre.self)
            let t = await PersistenceStore.shared.loadAll(Track.self)
            await MainActor.run {
                self.genres = g.sorted { $0.displayName < $1.displayName }
                self.tracks = t
            }
        }
    }
}

// MARK: - Genre Detail

struct GenreDetailView: View {
    let genre: Genre
    let allTracks: [Track]
    let onBack: () -> Void

    @Environment(PlaybackState.self) private var playbackState
    @State private var playlists: [Playlist] = []
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var pendingPlaylistTracks = Set<Track.ID>()

    private var genreTracks: [Track] {
        allTracks
            .filter { $0.genreName.lowercased() == genre.name.lowercased() }
            .sorted { $0.displayTitle < $1.displayTitle }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            genreHeader

            Divider()

            // Track list
            if genreTracks.isEmpty {
                Spacer()
                Text("No tracks in this genre")
                    .foregroundStyle(LumoColors.textTertiary)
                Spacer()
            } else {
                Table(genreTracks) {
                    TableColumn("#") { track in
                        Text("\(genreTracks.firstIndex(of: track)! + 1)")
                            .foregroundStyle(LumoColors.textTertiary)
                            .font(LumoFonts.micro)
                    }
                    .width(30)

                    TableColumn("Title") { track in
                        HStack {
                            ArtworkView(data: ArtworkCache.load(hash: track.artworkHash), fallbackTitle: track.displayTitle, size: 32, cornerRadius: 4)
                            Text(track.displayTitle)
                                .font(LumoFonts.bodyMedium)
                        }
                    }

                    TableColumn("Artist", value: \.displayArtist)

                    TableColumn("Album", value: \.displayAlbum)

                    TableColumn("Time", value: \.formattedDuration)
                        .width(50)
                }
                .contextMenu(forSelectionType: Track.ID.self) { selection in
                    Button("Play") {
                        playSelected(selection)
                    }
                    Button("Play Next") {
                        queueSelectedNext(selection)
                    }
                    Button("Add to Queue") {
                        addSelectedToQueue(selection)
                    }
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
        }
        .onAppear {
            Task { playlists = await PlaylistManager.shared.loadAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistsDidChange)) { _ in
            Task { playlists = await PlaylistManager.shared.loadAll() }
        }
        .sheet(isPresented: $showNewPlaylistAlert) {
            NewPlaylistSheet(initialTracks: Array(pendingPlaylistTracks), isPresented: $showNewPlaylistAlert)
        }
    }

    private var genreHeader: some View {
        HStack(spacing: 20) {
            Button(action: onBack) {
                Label("Genres", systemImage: "chevron.left")
                    .font(LumoFonts.bodyMedium)
                    .foregroundStyle(LumoColors.accent)
            }
            .buttonStyle(.plain)

            Image(systemName: "guitars.fill")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [LumoColors.accent, LumoColors.accentSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(genre.displayName)
                    .font(LumoFonts.headingLarge)
                    .foregroundStyle(LumoColors.textPrimary)

                Text("\(genre.trackCount) song\(genre.trackCount == 1 ? "" : "s")")
                    .font(LumoFonts.micro)
                    .foregroundStyle(LumoColors.textTertiary)
            }

            Spacer()

            if !genreTracks.isEmpty {
                Button {
                    playAll()
                } label: {
                    Label("Play All", systemImage: "play.fill")
                }
                .buttonStyle(.lumoPrimary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func playAll() {
        guard !genreTracks.isEmpty else { return }
        let infos = genreTracks.map { makeInfo($0) }
        playbackState.play(tracks: infos, startingAt: 0)
    }

    private func playSelected(_ ids: Set<Track.ID>) {
        guard let id = ids.first,
              let index = genreTracks.firstIndex(where: { $0.id == id }) else { return }
        let infos = genreTracks.map { makeInfo($0) }
        playbackState.play(tracks: infos, startingAt: index)
    }

    private func queueSelectedNext(_ ids: Set<Track.ID>) {
        for id in ids.reversed() {
            if let t = genreTracks.first(where: { $0.id == id }) {
                playbackState.insertNext(track: makeInfo(t))
            }
        }
    }

    private func addSelectedToQueue(_ ids: Set<Track.ID>) {
        for id in ids {
            if let t = genreTracks.first(where: { $0.id == id }) {
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