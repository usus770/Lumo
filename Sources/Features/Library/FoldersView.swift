import SwiftUI

/// Manages and displays watched library folders with add/remove capability.
struct FoldersView: View {
    @State private var folders: [LibraryFolder] = []
    @State private var isScanning = false
    @State private var folderToRemove: LibraryFolder?
    @State private var showRemoveAlert = false

    var body: some View {
        VStack(spacing: 0) {
            if folders.isEmpty {
                EmptyLibraryView(
                    icon: "folder.badge.plus",
                    title: "No Watch Folders",
                    subtitle: "Add folders and Lumo will automatically scan them and watch for changes",
                    actionLabel: "Add Folder"
                ) { addFolder() }
            } else {
                folderList
            }
        }
        .overlay(alignment: .bottom) {
            if isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Scanning library…")
                        .font(LumoFonts.bodySmall)
                        .foregroundStyle(LumoColors.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(.bottom, 16)
            }
        }
        .alert("Remove Folder", isPresented: $showRemoveAlert, presenting: folderToRemove) { folder in
            Button("Remove", role: .destructive) { removeFolder(folder) }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text("Remove \"\(URL(fileURLWithPath: folder.path).lastPathComponent)\" from your library? Tracks from this folder will be removed.")
        }
        .onAppear(perform: loadFolders)
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            isScanning = false
            loadFolders()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryNeedsRescan)) { _ in
            rescanAllFolders()
        }
    }

    // MARK: - List

    private var folderList: some View {
        VStack(spacing: 0) {
            List(folders, id: \.id) { folder in
                FolderRow(folder: folder) {
                    rescanFolder(folder)
                } onRemove: {
                    folderToRemove = folder
                    showRemoveAlert = true
                }
            }
            .listStyle(.plain)

            Divider()

            // Bottom toolbar
            HStack {
                Button {
                    addFolder()
                } label: {
                    Label("Add Folder", systemImage: "plus")
                        .font(LumoFonts.bodySmall)
                }
                .buttonStyle(.lumoSecondary)

                Spacer()

                Button {
                    rescanAllFolders()
                } label: {
                    Label("Rescan All", systemImage: "arrow.clockwise")
                        .font(LumoFonts.bodySmall)
                }
                .buttonStyle(.lumoSecondary)
                .disabled(folders.isEmpty || isScanning)
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Actions

    private func loadFolders() {
        Task {
            let loaded = await PersistenceStore.shared.loadAll(LibraryFolder.self)
            await MainActor.run {
                self.folders = loaded.sorted { $0.path < $1.path }
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
                isScanning = true
                Task {
                    for url in panel.urls {
                        await LibraryScanner.shared.scan(folderURL: url)
                    }
                    // FolderWatcher will be updated after rescan
                    await refreshFolderWatcher()
                }
            }
        }
    }

    private func rescanFolder(_ folder: LibraryFolder) {
        let url = URL(fileURLWithPath: folder.path)
        isScanning = true
        Task {
            await LibraryScanner.shared.scan(folderURL: url)
        }
    }

    private func rescanAllFolders() {
        isScanning = true
        Task {
            let allFolders = await PersistenceStore.shared.loadAll(LibraryFolder.self)
            for folder in allFolders {
                await LibraryScanner.shared.scan(folderURL: URL(fileURLWithPath: folder.path))
            }
        }
    }

    private func removeFolder(_ folder: LibraryFolder) {
        Task {
            // Remove tracks from this folder
            var allTracks = await PersistenceStore.shared.loadAll(Track.self)
            allTracks.removeAll { $0.libraryFolderId == folder.id }
            try? await PersistenceStore.shared.saveAll(allTracks)

            // Remove the folder record
            try? await PersistenceStore.shared.delete(LibraryFolder.self, id: folder.id)

            await refreshFolderWatcher()

            NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
        }
    }

    private func refreshFolderWatcher() async {
        let allFolders = await PersistenceStore.shared.loadAll(LibraryFolder.self)
        let paths = allFolders.map { $0.path }
        await MainActor.run {
            FolderWatcher.shared.start(watching: paths)
        }
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let folder: LibraryFolder
    let onRescan: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    private var folderName: String {
        URL(fileURLWithPath: folder.path).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.system(size: 28))
                .foregroundStyle(LumoColors.accent.opacity(0.8))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(folderName)
                    .font(LumoFonts.bodyMedium.weight(.semibold))
                    .foregroundStyle(LumoColors.textPrimary)

                Text(folder.path)
                    .font(LumoFonts.micro)
                    .foregroundStyle(LumoColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text("\(folder.trackCount) tracks")

                    if let scanned = folder.lastScannedAt {
                        Text("·")
                        Text("Last scanned \(scanned, style: .relative) ago")
                    }
                }
                .font(LumoFonts.micro)
                .foregroundStyle(LumoColors.textTertiary)
            }

            Spacer()

            if isHovered {
                HStack(spacing: 4) {
                    Button {
                        onRescan()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(LumoIconButtonStyle(size: 26))
                    .help("Rescan Folder")

                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(LumoIconButtonStyle(size: 26))
                    .help("Remove from Library")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.vertical, 6)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
