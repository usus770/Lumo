import SwiftUI

/// Albums section: grid of album cards, tap to see track list.
struct AlbumsView: View {
    @State private var albums: [Album] = []
    @State private var tracks: [Track] = []
    @State private var selectedAlbum: Album?
    @Environment(PlaybackState.self) private var playbackState

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        Group {
            if albums.isEmpty {
                EmptyLibraryView(
                    icon: "square.stack",
                    title: "No Albums",
                    subtitle: "Albums will appear here as you add music to your library",
                    actionLabel: "Add Folder"
                ) { addFolder() }
            } else if let album = selectedAlbum {
                AlbumDetailView(album: album, allTracks: tracks) {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedAlbum = nil }
                }
            } else {
                albumGrid
            }
        }
        .onAppear(perform: loadData)
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            loadData()
        }
    }

    // MARK: - Grid

    private var albumGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(albums) { album in
                    AlbumCard(album: album, tracks: tracks)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedAlbum = album
                            }
                        }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Data

    private func loadData() {
        Task {
            let loadedAlbums = await PersistenceStore.shared.loadAll(Album.self)
            let loadedTracks = await PersistenceStore.shared.loadAll(Track.self)
            await MainActor.run {
                self.albums = loadedAlbums.sorted { $0.displayTitle < $1.displayTitle }
                self.tracks = loadedTracks
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Library"
        panel.begin { response in
            if response == .OK {
                Task {
                    for url in panel.urls {
                        await LibraryScanner.shared.scan(folderURL: url)
                    }
                }
            }
        }
    }
}

// MARK: - Album Card

struct AlbumCard: View {
    let album: Album
    let tracks: [Track]
    @State private var isHovered = false

    private var artworkData: Data? {
        ArtworkCache.load(hash: album.artworkHash)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Artwork
            ArtworkView(data: artworkData, size: 160, cornerRadius: 10)
                .scaleEffect(isHovered ? 1.03 : 1.0)
                .shadow(color: .black.opacity(isHovered ? 0.30 : 0.15), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 2)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(album.displayTitle)
                    .font(LumoFonts.bodyMedium.weight(.semibold))
                    .foregroundStyle(LumoColors.textPrimary)
                    .lineLimit(1)

                Text(album.displayArtist)
                    .font(LumoFonts.bodySmall)
                    .foregroundStyle(LumoColors.textSecondary)
                    .lineLimit(1)

                if album.year > 0 {
                    Text(String(album.year))
                        .font(LumoFonts.micro)
                        .foregroundStyle(LumoColors.textTertiary)
                }
            }
            .frame(maxWidth: 160, alignment: .leading)
        }
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .cursor(.pointingHand)
    }
}

// MARK: - Album Detail

struct AlbumDetailView: View {
    let album: Album
    let allTracks: [Track]
    let onBack: () -> Void

    @Environment(PlaybackState.self) private var playbackState
    @State private var playlists: [Playlist] = []
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var pendingPlaylistTracks = Set<Track.ID>()

    private var albumTracks: [Track] {
        allTracks
            .filter { $0.albumId == album.id }
            .sorted {
                if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
                return $0.trackNumber < $1.trackNumber
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            albumHeader

            Divider()

            // Track list
            if albumTracks.isEmpty {
                Spacer()
                Text("No tracks found")
                    .foregroundStyle(LumoColors.textTertiary)
                Spacer()
            } else {
                Table(albumTracks) {
                    TableColumn("#") { track in
                        Text(track.trackNumber > 0 ? "\(track.trackNumber)" : "—")
                            .foregroundStyle(LumoColors.textTertiary)
                            .font(LumoFonts.micro)
                    }
                    .width(30)

                    TableColumn("Title") { track in
                        Text(track.displayTitle)
                            .font(LumoFonts.bodyMedium)
                    }

                    TableColumn("Artist", value: \.displayArtist)

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

    private var albumHeader: some View {
        HStack(spacing: 20) {
            Button(action: onBack) {
                Label("Albums", systemImage: "chevron.left")
                    .font(LumoFonts.bodyMedium)
                    .foregroundStyle(LumoColors.accent)
            }
            .buttonStyle(.plain)

            ArtworkView(data: ArtworkCache.load(hash: album.artworkHash), size: 80, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.displayTitle)
                    .font(LumoFonts.headingLarge)
                    .foregroundStyle(LumoColors.textPrimary)

                Text(album.displayArtist)
                    .font(LumoFonts.bodyMedium)
                    .foregroundStyle(LumoColors.textSecondary)

                HStack(spacing: 8) {
                    if album.year > 0 {
                        Text(String(album.year))
                    }
                    Text("·")
                    Text("\(album.trackCount) track\(album.trackCount == 1 ? "" : "s")")
                }
                .font(LumoFonts.micro)
                .foregroundStyle(LumoColors.textTertiary)
            }

            Spacer()

            // Play album button
            Button {
                playAlbum()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.lumoPrimary)
            .help("Play Album")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func playAlbum() {
        guard !albumTracks.isEmpty else { return }
        let infos = albumTracks.map { makeInfo($0) }
        playbackState.play(tracks: infos, startingAt: 0)
    }

    private func playSelected(_ ids: Set<Track.ID>) {
        guard let firstId = ids.first,
              let index = albumTracks.firstIndex(where: { $0.id == firstId }) else { return }
        let infos = albumTracks.map { makeInfo($0) }
        playbackState.play(tracks: infos, startingAt: index)
    }

    private func queueSelectedNext(_ ids: Set<Track.ID>) {
        for id in ids.reversed() {
            if let track = albumTracks.first(where: { $0.id == id }) {
                playbackState.insertNext(track: makeInfo(track))
            }
        }
    }

    private func addSelectedToQueue(_ ids: Set<Track.ID>) {
        for id in ids {
            if let track = albumTracks.first(where: { $0.id == id }) {
                playbackState.appendToQueue(track: makeInfo(track))
            }
        }
    }
    
    private func makeInfo(_ t: Track) -> TrackInfo {
        TrackInfo(
            id: t.id,
            title: t.displayTitle,
            artist: t.displayArtist,
            album: t.displayAlbum,
            duration: t.duration,
            artworkData: ArtworkCache.load(hash: t.artworkHash),
            filePath: t.filePath,
            fileExtension: t.fileExtension,
            lyricsText: t.lyricsText,
            hasSyncedLyrics: t.hasSyncedLyrics
        )
    }
}

// MARK: - Cursor helper

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
