import SwiftUI

/// Shows tracks that need metadata review (confidence < 1.0)
struct NeedsReviewView: View {
    @State private var tracks: [Track] = []
    @State private var selectedTrackToFix: Track?
    @State private var selectedTrackForCoverLyrics: Track?
    @State private var isFixingAll = false
    @State private var showAutoFindModal = false
    @State private var selectedTrackIds = Set<Track.ID>()
    @State private var showDeleteConfirmation = false
    @State private var tracksToDelete = Set<Track.ID>()
    
    var body: some View {
        VStack {
            if tracks.isEmpty {
                GenericPlaceholder(
                    icon: "checkmark.circle",
                    title: "All Good!",
                    subtitle: "No tracks currently need metadata review."
                )
            } else {
                Table(tracks, selection: $selectedTrackIds) {
                    TableColumn("Original File") { track in
                        Text(URL(fileURLWithPath: track.filePath).lastPathComponent)
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Parsed Title", value: \.displayTitle)
                    TableColumn("Parsed Artist", value: \.displayArtist)
                    TableColumn("Album", value: \.displayAlbum)
                    TableColumn("Confidence") { track in
                        HStack(spacing: 4) {
                            Text(String(format: "%.0f%%", track.metadataConfidence * 100))
                            if track.needsProbe {
                                Text("(Needs Probe)").font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                    TableColumn("Actions") { track in
                        HStack(spacing: 8) {
                            Button("Find Cover & Lyrics...") {
                                selectedTrackForCoverLyrics = track
                            }
                            .buttonStyle(.lumoPrimary)
                            
                            Button("Edit Tags") {
                                selectedTrackToFix = track
                            }
                            .buttonStyle(.lumoSecondary)
                        }
                    }
                }
                .onDeleteCommand {
                    if !selectedTrackIds.isEmpty {
                        promptDelete(for: selectedTrackIds)
                    }
                }
                .contextMenu(forSelectionType: Track.ID.self) { selection in
                    Button("Find Cover & Lyrics...") {
                        if let firstId = selection.first, let t = tracks.first(where: { $0.id == firstId }) {
                            selectedTrackForCoverLyrics = t
                        }
                    }
                    Button("Fix Metadata Tags...") {
                        if let firstId = selection.first, let t = tracks.first(where: { $0.id == firstId }) {
                            selectedTrackToFix = t
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        promptDelete(for: selection)
                    } label: {
                        Label(selection.count > 1 ? "Remove \(selection.count) Songs from Library..." : "Remove from Library...", systemImage: "trash")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAutoFindModal = true
                } label: {
                    Label("Auto-Find Missing...", systemImage: "wand.and.stars")
                }
                .help("Automatically find missing covers and lyrics for tracks needing review")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isFixingAll = true
                    Task {
                        await LibraryScanner.shared.migrateAndDeduplicateLibrary()
                        await MainActor.run {
                            isFixingAll = false
                            loadTracks()
                        }
                    }
                } label: {
                    Label(isFixingAll ? "Fixing All..." : "Fix All Online", systemImage: "sparkles")
                }
                .disabled(isFixingAll)
            }
        }
        .onAppear {
            loadTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            loadTracks()
        }
        .sheet(item: $selectedTrackToFix) { track in
            FixMatchSheet(track: track) {
                loadTracks()
            }
        }
        .sheet(item: $selectedTrackForCoverLyrics) { track in
            FindCoverLyricsSheet(track: track) {
                loadTracks()
            }
        }
        .sheet(isPresented: $showAutoFindModal) {
            AutoFindModal(selectedTrackIds: Set(tracks.map(\.id))) {
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
        }
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
            
            await MainActor.run {
                self.selectedTrackIds.subtract(ids)
                self.tracksToDelete.removeAll()
                loadTracks()
                NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
            }
        }
    }
    
    private func loadTracks() {
        Task {
            let allTracks = await PersistenceStore.shared.loadAll(Track.self)
            await MainActor.run {
                self.tracks = allTracks.filter {
                    $0.metadataConfidence < 0.85 ||
                    $0.artistName.lowercased().contains("unknown") ||
                    $0.albumTitle.lowercased().contains("unknown") ||
                    $0.needsProbe ||
                    $0.title.lowercased() == $0.artistName.lowercased()
                }
                .sorted { $0.displayTitle < $1.displayTitle }
            }
        }
    }
}
