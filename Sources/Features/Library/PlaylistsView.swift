import SwiftUI
import UniformTypeIdentifiers

/// Playlists section with sidebar list + detail view.
struct PlaylistsView: View {
    var searchText: String = ""
    
    @State private var playlists: [Playlist] = []
    @State private var tracks: [Track] = []
    @State private var selectedPlaylistID: Playlist.ID?
    @State private var isCreating = false
    @State private var newPlaylistName = ""
    
    @State private var playlistToRename: Playlist?
    @State private var renameText = ""
    @State private var isRenaming = false
    
    @Environment(PlaybackState.self) private var playbackState

    private var filteredPlaylists: [Playlist] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return playlists }
        return playlists.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        HSplitView {
            // Left: Playlist list
            playlistSidebar
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            // Right: Playlist detail
            if let selectedID = selectedPlaylistID,
               let idx = playlists.firstIndex(where: { $0.id == selectedID }) {
                PlaylistDetailView(
                    playlist: $playlists[idx],
                    allTracks: tracks,
                    searchText: searchText
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 52, weight: .ultraLight))
                        .foregroundStyle(LumoColors.accent.opacity(0.4))
                    Text(playlists.isEmpty ? "No playlists yet" : "Select a playlist")
                        .font(LumoFonts.headingMedium)
                        .foregroundStyle(LumoColors.textPrimary)
                    Text(playlists.isEmpty ? "Create your first playlist to organize your music" : "Choose a playlist from the sidebar to view its tracks")
                        .font(LumoFonts.bodyMedium)
                        .foregroundStyle(LumoColors.textTertiary)
                    Button("New Playlist") { isCreating = true }
                        .buttonStyle(.lumoPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $isCreating) {
            NewPlaylistSheet(isPresented: $isCreating) { created in
                selectedPlaylistID = created.id
            }
        }
        .sheet(isPresented: $isRenaming) {
            if let p = playlistToRename {
                RenamePlaylistSheet(playlist: p, isPresented: $isRenaming)
            }
        }
        .onAppear(perform: loadData)
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistsDidChange)) { _ in
            loadPlaylists()
        }
    }

    // MARK: - Sidebar

    private var playlistSidebar: some View {
        VStack(spacing: 0) {
            List(filteredPlaylists, selection: $selectedPlaylistID) { playlist in
                PlaylistRow(playlist: playlist)
                    .tag(playlist.id)
                    .contextMenu {
                        Button("Play") {
                            playPlaylist(playlist)
                        }
                        Divider()
                        Button("Rename...") {
                            playlistToRename = playlist
                            renameText = playlist.name
                            isRenaming = true
                        }
                        Button("Duplicate") {
                            Task {
                                if let copy = await PlaylistManager.shared.duplicatePlaylist(id: playlist.id) {
                                    selectedPlaylistID = copy.id
                                }
                            }
                        }
                        Divider()
                        Button("Delete Playlist", role: .destructive) {
                            deletePlaylist(playlist)
                        }
                    }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                isCreating = true
            } label: {
                Label("New Playlist", systemImage: "plus")
                    .font(LumoFonts.bodySmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LumoColors.accent)
            .padding(10)
        }
    }

    // MARK: - Actions

    private func loadData() {
        loadPlaylists()
        Task {
            let t = await PersistenceStore.shared.loadAll(Track.self)
            await MainActor.run { self.tracks = t }
        }
    }

    private func loadPlaylists() {
        Task {
            let loaded = await PlaylistManager.shared.loadAll()
            await MainActor.run {
                self.playlists = loaded
                // Auto-select first playlist if none selected
                if selectedPlaylistID == nil, let first = playlists.first {
                    selectedPlaylistID = first.id
                } else if let sel = selectedPlaylistID, !playlists.contains(where: { $0.id == sel }) {
                    selectedPlaylistID = playlists.first?.id
                }
            }
        }
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            let created = await PlaylistManager.shared.createPlaylist(name: name)
            await MainActor.run {
                newPlaylistName = ""
                isCreating = false
                selectedPlaylistID = created.id
            }
        }
    }

    private func deletePlaylist(_ playlist: Playlist) {
        if selectedPlaylistID == playlist.id {
            selectedPlaylistID = playlists.first(where: { $0.id != playlist.id })?.id
        }
        Task {
            await PlaylistManager.shared.deletePlaylist(id: playlist.id)
        }
    }

    private func playPlaylist(_ playlist: Playlist) {
        let pTracks = playlist.sortedEntries.compactMap { entry in
            tracks.first { $0.id == entry.trackId }
        }
        guard !pTracks.isEmpty else { return }
        let infos = pTracks.map { makeInfo($0) }
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

// MARK: - Playlist Row

struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 14))
                .foregroundStyle(LumoColors.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(LumoFonts.bodyMedium)
                    .foregroundStyle(LumoColors.textPrimary)
                    .lineLimit(1)

                Text("\(playlist.trackCount) song\(playlist.trackCount == 1 ? "" : "s")")
                    .font(LumoFonts.micro)
                    .foregroundStyle(LumoColors.textTertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Playlist Detail

struct PlaylistDetailView: View {
    @Binding var playlist: Playlist
    let allTracks: [Track]
    var searchText: String = ""
    
    @Environment(PlaybackState.self) private var playbackState
    @State private var selectedTrackIDs = Set<Track.ID>()
    @State private var isShowingAddSongsSheet = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var searchSheetTrack: Track?

    private var playlistTracks: [Track] {
        playlist.sortedEntries.compactMap { entry in
            allTracks.first { $0.id == entry.trackId }
        }
    }

    private var filteredTracks: [Track] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return playlistTracks }
        return playlistTracks.filter { track in
            track.displayTitle.localizedCaseInsensitiveContains(trimmed) ||
            track.displayArtist.localizedCaseInsensitiveContains(trimmed) ||
            track.displayAlbum.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var totalDurationFormatted: String {
        let total = playlistTracks.reduce(0) { $0 + $1.duration }
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            playlistHeader
            Divider()

            if playlistTracks.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(LumoColors.accent.opacity(0.35))
                    Text("This playlist is empty")
                        .font(LumoFonts.headingMedium)
                        .foregroundStyle(LumoColors.textPrimary)
                    Text("Add songs from your library to start listening, or drop audio files here")
                        .font(LumoFonts.bodyMedium)
                        .foregroundStyle(LumoColors.textTertiary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        isShowingAddSongsSheet = true
                    } label: {
                        Label("Add Songs to Playlist", systemImage: "plus")
                    }
                    .buttonStyle(.lumoPrimary)
                    .padding(.top, 4)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
            } else {
                Table(filteredTracks, selection: $selectedTrackIDs) {
                    TableColumn("#") { track in
                        if let index = playlistTracks.firstIndex(where: { $0.id == track.id }) {
                            Text("\(index + 1)")
                                .font(LumoFonts.caption)
                                .foregroundStyle(LumoColors.textTertiary)
                                .frame(width: 24, alignment: .trailing)
                        }
                    }
                    .width(28)

                    TableColumn("Title") { track in
                        HStack(spacing: 10) {
                            ArtworkView(data: ArtworkCache.load(hash: track.artworkHash), fallbackTitle: track.displayTitle, size: 32, cornerRadius: 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.displayTitle)
                                    .font(LumoFonts.bodyMedium.weight(.medium))
                                    .lineLimit(1)
                                if !track.displayArtist.isEmpty {
                                    Text(track.displayArtist)
                                        .font(LumoFonts.caption)
                                        .foregroundStyle(LumoColors.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    TableColumn("Artist", value: \.displayArtist)
                    TableColumn("Album", value: \.displayAlbum)
                    TableColumn("Time", value: \.formattedDuration)
                        .width(55)
                }
                .contextMenu(forSelectionType: Track.ID.self) { selection in
                    Button("Play") { playSelected(selection) }
                    Button("Play Next") { queueSelectedNext(selection) }
                    Button("Add to Queue") { addSelectedToQueue(selection) }
                    Divider()
                    if let firstId = selection.first, let track = playlistTracks.first(where: { $0.id == firstId }) {
                        Button("Find Cover & Lyrics...") {
                            searchSheetTrack = track
                        }
                    }
                    Divider()
                    Button("Remove from Playlist", role: .destructive) {
                        removeFromPlaylist(selection)
                    }
                } primaryAction: { selection in
                    playSelected(selection)
                }
                .onDeleteCommand {
                    if !selectedTrackIDs.isEmpty {
                        removeFromPlaylist(selectedTrackIDs)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .sheet(isPresented: $isShowingAddSongsSheet) {
            AddSongsToPlaylistSheet(playlist: playlist, allTracks: allTracks)
        }
        .sheet(item: $searchSheetTrack) { track in
            FindCoverLyricsSheet(track: track)
        }
        .sheet(isPresented: $isRenaming) {
            RenamePlaylistSheet(playlist: playlist, isPresented: $isRenaming)
        }
    }

    private var playlistHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LumoColors.accent.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: "music.note.list")
                    .font(.system(size: 26))
                    .foregroundStyle(LumoColors.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(playlist.name)
                        .font(LumoFonts.headingLarge)
                        .foregroundStyle(LumoColors.textPrimary)
                    
                    Button {
                        renameText = playlist.name
                        isRenaming = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundStyle(LumoColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Rename playlist")
                }

                Text("\(playlist.trackCount) song\(playlist.trackCount == 1 ? "" : "s") • \(totalDurationFormatted)")
                    .font(LumoFonts.bodySmall)
                    .foregroundStyle(LumoColors.textTertiary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    isShowingAddSongsSheet = true
                } label: {
                    Label("Add Songs", systemImage: "plus")
                }
                .buttonStyle(.lumoSecondary)

                if !playlistTracks.isEmpty {
                    Button {
                        shuffleAndPlay()
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.lumoSecondary)

                    Button {
                        playAll()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.lumoPrimary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func playAll() {
        guard !playlistTracks.isEmpty else { return }
        let infos = playlistTracks.map { makeInfo($0) }
        playbackState.play(tracks: infos, startingAt: 0)
        if let first = playlistTracks.first {
            incrementPlayCount(id: first.id)
        }
    }

    private func shuffleAndPlay() {
        guard !playlistTracks.isEmpty else { return }
        playbackState.isShuffleEnabled = true
        let infos = playlistTracks.shuffled().map { makeInfo($0) }
        playbackState.play(tracks: infos, startingAt: 0)
        if let first = infos.first {
            incrementPlayCount(id: first.id)
        }
    }

    private func playSelected(_ ids: Set<Track.ID>) {
        guard let id = ids.first,
              let index = playlistTracks.firstIndex(where: { $0.id == id }) else { return }
        let infos = playlistTracks.map { makeInfo($0) }
        playbackState.play(tracks: infos, startingAt: index)
        incrementPlayCount(id: id)
    }

    private func queueSelectedNext(_ ids: Set<Track.ID>) {
        for id in ids.reversed() {
            if let t = playlistTracks.first(where: { $0.id == id }) {
                playbackState.insertNext(track: makeInfo(t))
            }
        }
    }

    private func addSelectedToQueue(_ ids: Set<Track.ID>) {
        for id in ids {
            if let t = playlistTracks.first(where: { $0.id == id }) {
                playbackState.appendToQueue(track: makeInfo(t))
            }
        }
    }

    private func removeFromPlaylist(_ ids: Set<Track.ID>) {
        Task {
            await PlaylistManager.shared.removeTracks(trackIDs: ids, fromPlaylist: playlist.id)
            await MainActor.run {
                selectedTrackIDs.subtract(ids)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        Task {
                            await LibraryScanner.shared.scan(folderURL: url)
                            // After scanning, find newly added tracks and add to playlist
                            let allNow = await PersistenceStore.shared.loadAll(Track.self)
                            let newIDs = allNow.filter { $0.filePath == url.path }.map(\.id)
                            if !newIDs.isEmpty {
                                await PlaylistManager.shared.addTracks(trackIDs: Set(newIDs), toPlaylist: playlist.id)
                            }
                        }
                    }
                }
                handled = true
            }
        }
        return handled
    }

    private func incrementPlayCount(id: Track.ID) {
        Task {
            var all = await PersistenceStore.shared.loadAll(Track.self)
            if let idx = all.firstIndex(where: { $0.id == id }) {
                all[idx].playCount += 1
                all[idx].lastPlayedAt = Date()
                try? await PersistenceStore.shared.saveAll(all)
                NotificationCenter.default.post(name: .playCountDidChange, object: nil)
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
