import SwiftUI

/// Artists section: list of artists with track/album counts, tap to see artist's albums.
struct ArtistsView: View {
    @State private var artists: [Artist] = []
    @State private var albums: [Album] = []
    @State private var tracks: [Track] = []
    @State private var selectedArtist: Artist?
    @Environment(PlaybackState.self) private var playbackState

    var body: some View {
        Group {
            if artists.isEmpty {
                EmptyLibraryView(
                    icon: "music.mic",
                    title: "No Artists",
                    subtitle: "Artists will appear here as you add music to your library",
                    actionLabel: "Add Folder"
                ) { addFolder() }
            } else if let artist = selectedArtist {
                ArtistDetailView(
                    artist: artist,
                    allAlbums: albums,
                    allTracks: tracks
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedArtist = nil }
                }
            } else {
                artistList
            }
        }
        .onAppear(perform: loadData)
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            loadData()
        }
    }

    // MARK: - List

    private var artistList: some View {
        List(artists, id: \.id) { artist in
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { selectedArtist = artist }
            } label: {
                HStack(spacing: 14) {
                    // Artist icon (placeholder circle with initials)
                    ArtistAvatarView(artist: artist, albums: albums, size: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(artist.displayName)
                            .font(LumoFonts.bodyMedium.weight(.semibold))
                            .foregroundStyle(LumoColors.textPrimary)

                        HStack(spacing: 4) {
                            Text("\(artist.albumCount) album\(artist.albumCount == 1 ? "" : "s")")
                            Text("·")
                            Text("\(artist.trackCount) song\(artist.trackCount == 1 ? "" : "s")")
                        }
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
            let a = await PersistenceStore.shared.loadAll(Artist.self)
            let al = await PersistenceStore.shared.loadAll(Album.self)
            let t = await PersistenceStore.shared.loadAll(Track.self)
            await MainActor.run {
                self.artists = a.sorted { $0.displayName < $1.displayName }
                self.albums = al
                self.tracks = t
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

// MARK: - Artist Avatar

struct ArtistAvatarView: View {
    let artist: Artist
    let albums: [Album]
    let size: CGFloat

    private var artworkData: Data? {
        // Try to find artwork from any of the artist's albums
        let artistAlbum = albums.first { $0.artistId == artist.id && $0.artworkHash != nil }
        return ArtworkCache.load(hash: artistAlbum?.artworkHash)
    }

    private var initials: String {
        let words = artist.displayName.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(artist.displayName.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            if let data = artworkData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hue: 0.74, saturation: 0.3, brightness: 0.3),
                                Color(hue: 0.80, saturation: 0.25, brightness: 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)

                Text(initials)
                    .font(.system(size: size * 0.35, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

// MARK: - Artist Detail

struct ArtistDetailView: View {
    let artist: Artist
    let allAlbums: [Album]
    let allTracks: [Track]
    let onBack: () -> Void

    @Environment(PlaybackState.self) private var playbackState

    private var artistAlbums: [Album] {
        allAlbums
            .filter { $0.artistId == artist.id }
            .sorted { $0.year > $1.year }
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            artistHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !artistAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Albums")
                                .font(LumoFonts.headingMedium)
                                .foregroundStyle(LumoColors.textPrimary)
                                .padding(.horizontal, 20)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(artistAlbums) { album in
                                    AlbumCard(album: album, tracks: allTracks)
                                        .onTapGesture { playAlbum(album) }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
        }
    }

    private var artistHeader: some View {
        HStack(spacing: 20) {
            Button(action: onBack) {
                Label("Artists", systemImage: "chevron.left")
                    .font(LumoFonts.bodyMedium)
                    .foregroundStyle(LumoColors.accent)
            }
            .buttonStyle(.plain)

            ArtistAvatarView(artist: artist, albums: allAlbums, size: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(artist.displayName)
                    .font(LumoFonts.headingLarge)
                    .foregroundStyle(LumoColors.textPrimary)

                HStack(spacing: 6) {
                    Text("\(artist.albumCount) album\(artist.albumCount == 1 ? "" : "s")")
                    Text("·")
                    Text("\(artist.trackCount) song\(artist.trackCount == 1 ? "" : "s")")
                }
                .font(LumoFonts.micro)
                .foregroundStyle(LumoColors.textTertiary)
            }

            Spacer()

            Button {
                playAll()
            } label: {
                Label("Play All", systemImage: "play.fill")
            }
            .buttonStyle(.lumoPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func playAll() {
        let tracksToPlay = allTracks
            .filter { $0.artistId == artist.id }
            .sorted { $0.displayTitle < $1.displayTitle }
        guard !tracksToPlay.isEmpty else { return }
        let infos = tracksToPlay.map { makeInfo($0) }
        playbackState.play(tracks: infos, startingAt: 0)
    }

    private func playAlbum(_ album: Album) {
        let albumTracks = allTracks
            .filter { $0.albumId == album.id }
            .sorted { $0.trackNumber < $1.trackNumber }
        guard !albumTracks.isEmpty else { return }
        let infos = albumTracks.map { makeInfo($0) }
        playbackState.play(tracks: infos, startingAt: 0)
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
