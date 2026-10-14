import SwiftUI
import UniformTypeIdentifiers

/// Library Songs List for Lumo iOS.
/// Allows importing audio from iPhone Files app / iCloud Drive via `.fileImporter`,
/// searching, and playback with automatic queue population.
public struct iOSLibraryView: View {
    @ObservedObject private var playbackState = iOSPlaybackState.shared
    @State private var tracks: [iOSTrack] = []
    @State private var searchQuery: String = ""
    @State private var isImportingFiles: Bool = false
    @State private var isLoading: Bool = false
    
    public init() {}
    
    private var filteredTracks: [iOSTrack] {
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return tracks
        }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.artist.localizedCaseInsensitiveContains(searchQuery) ||
            $0.album.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                LumoTheme.bg0.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if tracks.isEmpty && !isLoading {
                        emptyLibraryState
                    } else {
                        List {
                            ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, track in
                                trackRow(index: index, track: track)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowBackground(LumoTheme.surface)
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            playbackState.insertNext(track: track)
                                        } label: {
                                            Label("Play Next", systemImage: "text.insert")
                                        }
                                        .tint(LumoTheme.accentPink)
                                        
                                        Button {
                                            playbackState.appendToQueue(track: track)
                                        } label: {
                                            Label("Queue", systemImage: "plus.rectangle.on.rectangle")
                                        }
                                        .tint(LumoTheme.accentViolet)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            withAnimation {
                                                tracks.removeAll { $0.id == track.id }
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Songs")
            .searchable(text: $searchQuery, prompt: "Search tracks, artists, albums...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isImportingFiles = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(LumoTheme.brandGradient)
                    }
                }
            }
            .fileImporter(
                isPresented: $isImportingFiles,
                allowedContentTypes: [.audio, .mp3, .mpeg4Audio, UTType("org.xiph.flac") ?? .audio],
                allowsMultipleSelection: true
            ) { result in
                handleImportedFiles(result: result)
            }
            .onAppear {
                if tracks.isEmpty {
                    loadInitialDemoTracks()
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private func trackRow(index: Int, track: iOSTrack) -> some View {
        let isCurrent = playbackState.currentTrack?.id == track.id
        
        return HStack(spacing: 14) {
            // Artwork
            if let data = track.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LumoTheme.surfaceRaised)
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(isCurrent ? LumoTheme.accentPink : LumoTheme.textTertiary)
                    )
            }
            
            // Metadata
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent ? LumoTheme.accentPink : LumoTheme.textPrimary)
                    .lineLimit(1)
                
                Text(track.artist)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(LumoTheme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Duration
            Text(track.formattedDuration)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(LumoTheme.textTertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            playbackState.play(tracks: filteredTracks, startingAt: index)
        }
    }
    
    private var emptyLibraryState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 54))
                .foregroundStyle(LumoTheme.brandGradient)
            
            Text("No Songs in Library")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(LumoTheme.textPrimary)
            
            Text("Tap the + button to import audio files (.mp3, .flac, .m4a, .wav) directly from your iPhone Files app or iCloud Drive.")
                .font(.system(size: 14))
                .foregroundStyle(LumoTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                isImportingFiles = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                    Text("Import from Files")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(LumoTheme.brandGradient)
                .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func handleImportedFiles(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                var loaded: [iOSTrack] = []
                for url in urls {
                    // Security-scoped bookmark handling for iOS Files app
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    // Copy to app documents container
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let dest = docs.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.copyItem(at: url, to: dest)
                    
                    let track = await iOSTrack.from(url: dest)
                    loaded.append(track)
                }
                
                await MainActor.run {
                    tracks.append(contentsOf: loaded)
                }
            }
        case .failure(let error):
            print("Import error: \(error)")
        }
    }
    
    private func loadInitialDemoTracks() {
        // Built-in sample tracks to demonstrate full playback and queue immediately
        tracks = [
            iOSTrack(
                title: "Mockingbird",
                artist: "Eminem",
                album: "Encore",
                duration: 251,
                lyricsText: "[00:01.00]Yeah, I know sometimes things may not make sense to you right now\n[00:07.00]Now hush, little baby, don't you cry\n[00:10.00]Everything's gonna be alright"
            ),
            iOSTrack(
                title: "Kesariya",
                artist: "Arijit Singh, Pritam",
                album: "Brahmāstra",
                duration: 268,
                lyricsText: "[00:15.00]केसरिया तेरा इश्क़ है पिया\n[00:20.00]रंग जाऊं जो मैं हाथ लगाऊं"
            ),
            iOSTrack(
                title: "Better With You",
                artist: "Ollie",
                album: "Better With You",
                duration: 197
            ),
            iOSTrack(
                title: "Darkside",
                artist: "Alan Walker",
                album: "Different World",
                duration: 211
            ),
            iOSTrack(
                title: "Tum Hi Ho",
                artist: "Arijit Singh",
                album: "Aashiqui 2",
                duration: 262
            )
        ]
    }
}
