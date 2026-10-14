import SwiftUI
import UniformTypeIdentifiers

struct SongsListView: View {
    var searchText: String = ""
    @State private var tracks: [Track] = []
    @State private var playlists: [Playlist] = []
    @State private var isScanning = false
    @Environment(PlaybackState.self) private var playbackState
    @Environment(\.openWindow) private var openWindow
    @Environment(WindowManager.self) private var windowManager
    @State private var selectedInfoTrack: Track?
    @State private var trackForCoverLyricsSearch: Track?
    @State private var showAutoFindModal = false
    @State private var selectedTrackIdsForAutoFind: Set<UUID> = []
    @State private var selectedTrackIds = Set<Track.ID>()
    @State private var showDeleteConfirmation = false
    @State private var tracksToDelete = Set<Track.ID>()
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var pendingPlaylistTracks = Set<Track.ID>()
    
    enum QualityFilter: String, CaseIterable, Identifiable {
        case all = "All Files"
        case lossy = "Lossy files"
        case lossless = "True lossless"
        case suspectedFake = "Suspected fake lossless"
        var id: String { rawValue }
    }
    
    @State private var qualityFilter: QualityFilter = .all
    
    private var filteredTracks: [Track] {
        var result = tracks
        
        switch qualityFilter {
        case .all:
            break
        case .lossy:
            result = result.filter { $0.qualityStatus == .lossy || ["mp3", "aac", "ogg", "opus", "wma"].contains($0.fileExtension.lowercased()) }
        case .lossless:
            result = result.filter { $0.qualityStatus == .trueLossless }
        case .suspectedFake:
            result = result.filter { $0.qualityStatus == .suspectedFake }
        }
        
        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            result = result.filter { track in
                track.displayTitle.lowercased().contains(lower) ||
                track.displayArtist.lowercased().contains(lower) ||
                track.displayAlbum.lowercased().contains(lower) ||
                (track.lyricsText?.lowercased().contains(lower) ?? false)
            }
        }
        
        return result
    }
    
    var body: some View {
        VStack {
            if filteredTracks.isEmpty {
                SongsListPlaceholder(onAddFolder: addFolder)
            } else {
                Table(filteredTracks, selection: $selectedTrackIds) {
                    TableColumn("Title") { track in
                        SongTitleCell(
                            track: track,
                            isCurrent: playbackState.currentTrack?.id == track.id,
                            isPlaying: playbackState.isPlaying
                        )
                    }
                    TableColumn("Artist", value: \.displayArtist)
                    TableColumn("Album", value: \.displayAlbum)
                    TableColumn("Time", value: \.formattedDuration)
                }
                .onDeleteCommand {
                    if !selectedTrackIds.isEmpty {
                        promptDelete(for: selectedTrackIds)
                    }
                }
                .contextMenu(forSelectionType: Track.ID.self) { selection in
                    tableContextMenu(selection: selection)
                } primaryAction: { selection in
                    playSelected(selection)
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .sheet(item: $selectedInfoTrack) { track in
            TrackInfoView(track: track)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            selectedInfoTrack = nil
                        }
                    }
                }
        }
        .sheet(item: $trackForCoverLyricsSearch) { track in
            FindCoverLyricsSheet(track: track) {
                loadTracks()
            }
        }
        .sheet(isPresented: $showAutoFindModal) {
            AutoFindModal(selectedTrackIds: selectedTrackIdsForAutoFind) {
                loadTracks()
            }
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from Library", role: .destructive) {
                removeTracks(ids: tracksToDelete, moveToTrash: false)
            }
            Button("Move to Trash", role: .destructive) {
                removeTracks(ids: tracksToDelete, moveToTrash: true)
            }
            Button("Cancel", role: .cancel) {
                tracksToDelete.removeAll()
            }
        } message: {
            Text(deleteDialogMessage)
        }
        .sheet(isPresented: $showNewPlaylistAlert) {
            NewPlaylistSheet(initialTracks: Array(pendingPlaylistTracks), isPresented: $showNewPlaylistAlert)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumoOpenFindCoverLyrics"))) { notif in
            if let track = notif.object as? Track {
                trackForCoverLyricsSearch = track
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumoOpenAutoFindModal"))) { _ in
            selectedTrackIdsForAutoFind = Set(tracks.map(\.id))
            showAutoFindModal = true
        }
        .toolbar {
            if !selectedTrackIds.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        promptDelete(for: selectedTrackIds)
                    } label: {
                        Label("Remove (\(selectedTrackIds.count))...", systemImage: "trash")
                    }
                    .help("Remove selected song(s) from library")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    selectedTrackIdsForAutoFind = Set(tracks.map(\.id))
                    showAutoFindModal = true
                } label: {
                    Label("Auto-Find Missing...", systemImage: "wand.and.stars")
                }
                .help("Automatically find missing covers and lyrics in the background")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isScanning = true
                    Task {
                        await LibraryScanner.shared.migrateAndDeduplicateLibrary()
                        await MainActor.run {
                            isScanning = false
                            loadTracks()
                        }
                    }
                } label: {
                    Label("Re-scan Metadata", systemImage: "sparkles")
                }
                .help("Re-scan and auto-fix metadata, remove duplicates, and update artwork")
                .disabled(isScanning)
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("Filter Quality", selection: $qualityFilter) {
                    ForEach(QualityFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .overlay {
            if isScanning {
                VStack(spacing: 12) {
                    LumoMarkView(size: 38, opacity: 1.0, isAnimated: true)
                    Text("Scanning Library...")
                        .font(LumoTheme.Typography.caption)
                        .foregroundStyle(LumoTheme.textPrimary)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: LumoTheme.Radius.medium)
                        .fill(LumoTheme.surfaceRaised)
                        .overlay(RoundedRectangle(cornerRadius: LumoTheme.Radius.medium).stroke(LumoTheme.stroke, lineWidth: 1))
                )
            }
        }
        .onAppear {
            loadTracks()
            loadPlaylists()
        }
        .onChange(of: tracks.count) { _, newValue in
            windowManager.totalTrackCount = newValue
        }
        .onChange(of: filteredTracks.count) { _, newValue in
            windowManager.filteredTrackCount = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            loadTracks()
            isScanning = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistsDidChange)) { _ in
            loadPlaylists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .favoritesDidChange)) { _ in
            loadTracks()
        }
    }
    
    @ViewBuilder
    private func tableContextMenu(selection: Set<Track.ID>) -> some View {
        Button("Play") {
            playSelected(selection)
        }
        Button("Play Next") {
            for id in selection { queueTrackNext(id: id) }
        }
        Button("Add to Queue") {
            for id in selection { addTrackToQueue(id: id) }
        }
        Divider()
        Button("Get Info") {
            if let firstId = selection.first {
                if let t = tracks.first(where: { $0.id == firstId }) {
                    selectedInfoTrack = t
                }
            }
        }
        Divider()
        Button("Find Cover & Lyrics...") {
            if let firstId = selection.first {
                if let t = tracks.first(where: { $0.id == firstId }) {
                    trackForCoverLyricsSearch = t
                }
            }
        }
        if hasLockedItems(in: selection) {
            Button("Reset to Automatic") {
                for id in selection {
                    Task { await MetadataFetcherCoordinator.shared.resetToAutomatic(trackId: id) }
                }
            }
        }
        Divider()
        Button("Convert to Lossless...") {
            var urls: [URL] = []
            for id in selection {
                if let t = tracks.first(where: { $0.id == id }) {
                    urls.append(URL(fileURLWithPath: t.filePath))
                }
            }
            AudioConverterManager.shared.addFiles(urls)
            openWindow(id: "converter")
        }
        Divider()
        let allFavorited = selection.allSatisfy { id in
            tracks.first(where: { $0.id == id })?.isFavorite == true
        }
        Button(allFavorited ? "Remove from Favorites" : "Add to Favorites") {
            toggleFavorite(ids: selection, setTo: !allFavorited)
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
                        addToPlaylist(ids: selection, playlist: playlist)
                    }
                }
            }
        } label: {
            Label("Add to Playlist", systemImage: "music.note.list")
        }
        Divider()
        if selection.count > 1 {
            Button(role: .destructive) {
                promptDelete(for: selection)
            } label: {
                Label("Remove \(selection.count) Songs from Library...", systemImage: "trash")
            }
        } else {
            Button(role: .destructive) {
                promptDelete(for: selection)
            } label: {
                Label("Remove from Library...", systemImage: "trash")
            }
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
    
    private func hasLockedItems(in selection: Set<Track.ID>) -> Bool {
        for id in selection {
            if let t = tracks.first(where: { $0.id == id }) {
                if t.isCoverLocked || t.isLyricsLocked {
                    return true
                }
            }
        }
        return false
    }
    
    // MARK: - Remove Songs
    
    private var deleteDialogTitle: String {
        if tracksToDelete.count == 1 {
            let trackName = tracks.first(where: { $0.id == tracksToDelete.first })?.displayTitle ?? "Song"
            return "Remove \"\(trackName)\"?"
        } else {
            return "Remove \(tracksToDelete.count) Songs?"
        }
    }
    
    private var deleteDialogMessage: String {
        if tracksToDelete.count == 1 {
            return "Do you want to remove this song from your Lumo library only, or move the file to the Trash?"
        } else {
            return "Do you want to remove these \(tracksToDelete.count) songs from your Lumo library only, or move the files to the Trash?"
        }
    }
    
    private func promptDelete(for ids: Set<Track.ID>) {
        guard !ids.isEmpty else { return }
        tracksToDelete = ids
        showDeleteConfirmation = true
    }
    
    private func removeTracks(ids: Set<Track.ID>, moveToTrash: Bool) {
        Task {
            var allTracks = await PersistenceStore.shared.loadAll(Track.self)
            let tracksToRemove = allTracks.filter { ids.contains($0.id) }
            
            if moveToTrash {
                for track in tracksToRemove {
                    let fileURL = URL(fileURLWithPath: track.filePath)
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try? FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                    }
                }
            }
            
            allTracks.removeAll { ids.contains($0.id) }
            try? await PersistenceStore.shared.saveAll(allTracks)
            
            // Clean up from playlists as well
            await PlaylistManager.shared.removeTrackReferences(trackIDs: ids)
            
            await MainActor.run {
                if let cur = playbackState.currentTrack, ids.contains(cur.id) {
                    playbackState.nextTrack()
                }
                self.tracks = allTracks.sorted { $0.displayTitle < $1.displayTitle }
                self.selectedTrackIds.subtract(ids)
                self.tracksToDelete.removeAll()
                NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
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
        guard let firstId = ids.first,
              let index = filteredTracks.firstIndex(where: { $0.id == firstId }) else { return }
        let allInfos = filteredTracks.map { makeInfo($0) }
        playbackState.play(tracks: allInfos, startingAt: index)
        incrementPlayCount(id: firstId)
    }

    private func queueTrackNext(id: Track.ID) {
        guard let track = tracks.first(where: { $0.id == id }) else { return }
        playbackState.insertNext(track: makeInfo(track))
    }

    private func addTrackToQueue(id: Track.ID) {
        guard let track = tracks.first(where: { $0.id == id }) else { return }
        playbackState.appendToQueue(track: makeInfo(track))
    }

    private func toggleFavorite(ids: Set<Track.ID>, setTo isFavorite: Bool) {
        Task {
            var allTracks = await PersistenceStore.shared.loadAll(Track.self)
            for id in ids {
                if let idx = allTracks.firstIndex(where: { $0.id == id }) {
                    allTracks[idx].isFavorite = isFavorite
                }
            }
            try? await PersistenceStore.shared.saveAll(allTracks)
            await MainActor.run {
                NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
            }
        }
    }

    private func addToPlaylist(ids: Set<Track.ID>, playlist: Playlist) {
        Task {
            await PlaylistManager.shared.addTracks(trackIDs: ids, toPlaylist: playlist.id)
        }
    }

    private func incrementPlayCount(id: Track.ID) {
        Task {
            var allTracks = await PersistenceStore.shared.loadAll(Track.self)
            if let idx = allTracks.firstIndex(where: { $0.id == id }) {
                allTracks[idx].playCount += 1
                allTracks[idx].lastPlayedAt = Date()
                try? await PersistenceStore.shared.saveAll(allTracks)
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
    
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Library"
        
        panel.begin { response in
            if response == .OK {
                isScanning = true
                Task {
                    for url in panel.urls {
                        await LibraryScanner.shared.scan(folderURL: url)
                    }
                }
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            isScanning = true
                        }
                        Task {
                            await LibraryScanner.shared.scan(folderURL: url)
                        }
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

private struct SongTitleCell: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    
    private var needsReview: Bool {
        if track.metadataConfidence < 0.7 { return true }
        if track.artistName.lowercased() == "unknown" { return true }
        if track.albumTitle.lowercased() == "unknown" { return true }
        return false
    }
    
    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(
                data: ArtworkCache.load(hash: track.artworkHash, filePath: track.filePath),
                fallbackTitle: track.displayTitle,
                size: 32,
                cornerRadius: 6
            )
            
            if isCurrent {
                AnimatedEqualizerView(barCount: 3, height: 14, isPlaying: isPlaying)
            }
            
            Text(track.displayTitle)
                .font(isCurrent ? LumoFonts.bodyMedium.weight(.bold) : LumoFonts.bodyMedium.weight(.medium))
                .foregroundStyle(isCurrent ? LumoTheme.accentPink : LumoTheme.textPrimary)
            
            if needsReview {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(LumoTheme.accentAmber)
                    .help("Needs metadata review")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.displayTitle) by \(track.displayArtist)\(isCurrent ? ", Now Playing" : "")")
    }
}
