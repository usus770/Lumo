import SwiftUI

/// Persistent bottom bar showing current track info, playback controls, and volume.
/// Reads from unified NowPlayingSnapshot for seamless local and external playback.
struct NowPlayingBar: View {
    @Environment(PlaybackState.self) private var playbackState
    @State private var nowPlaying = NowPlayingSnapshot.shared
    @State private var enhancementManager = AudioEnhancementManager.shared
    @State private var trackForSearch: Track? = nil
    @State private var playlists: [Playlist] = []
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var showQueuePopover = false
    
    var body: some View {
        @Bindable var ps = playbackState
        
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let currentPos = nowPlaying.position(at: ProcessInfo.processInfo.systemUptime)
            
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 16) {
                    // MARK: - Track Info (left)
                    trackInfo
                    
                    Spacer()
                    
                    // MARK: - Center Controls
                    centerControls(currentPos: currentPos)
                    
                    Spacer()
                    
                    // MARK: - Right Controls
                    rightControls
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(height: AppConstants.UI.nowPlayingBarHeight)
                .background(.ultraThinMaterial)
            }
            .sheet(item: $trackForSearch) { track in
                FindCoverLyricsSheet(track: track)
            }
            .onAppear {
                Task { playlists = await PlaylistManager.shared.loadAll() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .playlistsDidChange)) { _ in
                Task { playlists = await PlaylistManager.shared.loadAll() }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumoToggleQueuePopover"))) { _ in
                showQueuePopover.toggle()
            }
            .sheet(isPresented: $showNewPlaylistAlert) {
                if let track = playbackState.currentTrack {
                    NewPlaylistSheet(initialTracks: [track.id], isPresented: $showNewPlaylistAlert)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var trackInfo: some View {
        HStack(spacing: 12) {
            // Artwork
            ArtworkView(
                data: nowPlaying.artworkData,
                fallbackTitle: nowPlaying.title.isEmpty ? "Lumo" : nowPlaying.title,
                size: 48,
                cornerRadius: 6
            )
            
            // Title & Artist
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.title.isEmpty ? "Not Playing" : nowPlaying.title)
                    .font(LumoFonts.nowPlayingTitle)
                    .foregroundStyle(nowPlaying.title.isEmpty ? LumoColors.textTertiary : LumoColors.textPrimary)
                    .lineLimit(1)
                
                if !nowPlaying.artist.isEmpty {
                    Text(nowPlaying.artist)
                        .font(LumoFonts.nowPlayingSubtitle)
                        .foregroundStyle(LumoColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 200, alignment: .leading)
            
            // Favorite button (local only)
            if !nowPlaying.isExternal, let track = playbackState.currentTrack {
                FavoriteButton(trackId: track.id)
                
                // Track actions menu
                Menu {
                    Button("Find Cover & Lyrics...") {
                        openSearchSheet(for: track)
                    }
                    Divider()
                    Menu {
                        Button {
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
                                        await PlaylistManager.shared.addTracks(trackIDs: [track.id], toPlaylist: playlist.id)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Add to Playlist", systemImage: "music.note.list")
                    }
                    Divider()
                    Button("Reset to Automatic") {
                        Task { await MetadataFetcherCoordinator.shared.resetToAutomatic(trackId: track.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .help("More track options")
            }
        }
        .contextMenu {
            if let track = playbackState.currentTrack {
                Button("Find Cover & Lyrics...") {
                    openSearchSheet(for: track)
                }
                Divider()
                Menu {
                    Button {
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
                                    await PlaylistManager.shared.addTracks(trackIDs: [track.id], toPlaylist: playlist.id)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Add to Playlist", systemImage: "music.note.list")
                }
                Divider()
                Button("Reset to Automatic") {
                    Task { await MetadataFetcherCoordinator.shared.resetToAutomatic(trackId: track.id) }
                }
            }
        }
    }
    
    private func centerControls(currentPos: TimeInterval) -> some View {
        VStack(spacing: 4) {
            // Transport buttons
            HStack(spacing: 20) {
                // Shuffle
                Button {
                    playbackState.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(LumoIconButtonStyle(
                    size: 24,
                    isActive: playbackState.isShuffleEnabled
                ))
                .help("Shuffle")
                .disabled(nowPlaying.isExternal)
                
                // Previous
                Button {
                    nowPlaying.previousTrack()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(LumoIconButtonStyle(size: 28))
                .help("Previous Track")
                
                // Play/Pause
                Button {
                    nowPlaying.togglePlayPause()
                } label: {
                    Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(LumoPlayButtonStyle(isPlaying: nowPlaying.isPlaying))
                .help(nowPlaying.isPlaying ? "Pause" : "Play")
                
                // Next
                Button {
                    nowPlaying.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(LumoIconButtonStyle(size: 28))
                .help("Next Track")
                
                // Repeat
                Button {
                    playbackState.cycleRepeatMode()
                } label: {
                    Image(systemName: playbackState.repeatMode.icon)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(LumoIconButtonStyle(
                    size: 24,
                    isActive: playbackState.repeatMode.isActive
                ))
                .help("Repeat: \(playbackState.repeatMode.rawValue)")
                .disabled(nowPlaying.isExternal)
            }
            
            // Scrubber
            ScrubberView(
                currentTime: Binding(
                    get: { currentPos },
                    set: { nowPlaying.seek(to: $0) }
                ),
                duration: nowPlaying.duration
            ) { time in
                nowPlaying.seek(to: time)
            }
            .frame(maxWidth: 400)
        }
    }
    
    private var rightControls: some View {
        @Bindable var ps = playbackState
        
        return HStack(spacing: 12) {
            // Source indicator & Switcher
            if nowPlaying.isExternal {
                HStack(spacing: 6) {
                    if let icon = nowPlaying.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "link")
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                    Text(nowPlaying.appName)
                        .font(LumoFonts.micro)
                        .foregroundStyle(LumoColors.textTertiary)
                    
                    if let localTrack = playbackState.currentTrack {
                        Button {
                            playbackState.isPlaying = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 8))
                                Text("Local")
                                    .font(LumoFonts.micro)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Switch to local track: \(localTrack.title)")
                    }
                }
            } else if let ext = UniversalNowPlayingManager.shared.activeState {
                Button {
                    NowPlayingSnapshot.shared.updateExternal(state: ext)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 8))
                        Text(ext.appName)
                            .font(LumoFonts.micro)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Switch to \(ext.appName)")
            }
            
            // Enhancement Toggle
            Button {
                enhancementManager.isEnabled.toggle()
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14))
            }
            .buttonStyle(LumoIconButtonStyle(
                size: 28,
                isActive: enhancementManager.isEnabled
            ))
            .help("Toggle Audio Enhancement")
            .disabled(nowPlaying.isExternal)
            
            // Queue Popover Toggle
            Button {
                showQueuePopover.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 14))
                    
                    if !playbackState.queue.isEmpty {
                        Circle()
                            .fill(LumoTheme.accentPink)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(LumoIconButtonStyle(
                size: 28,
                isActive: showQueuePopover
            ))
            .help("Playing Queue (\(playbackState.queue.count) upcoming)")
            .popover(isPresented: $showQueuePopover, arrowEdge: .top) {
                QueuePopoverView()
            }
            
            // Volume
            VolumeSlider(
                volume: $ps.volume,
                isMuted: $ps.isMuted,
                width: 90
            )
        }
    }
    
    private func openSearchSheet(for trackInfo: TrackInfo) {
        Task {
            let all = await PersistenceStore.shared.loadAll(Track.self)
            if let found = all.first(where: { $0.id == trackInfo.id }) {
                await MainActor.run {
                    trackForSearch = found
                }
            } else {
                var synth = Track(
                    filePath: trackInfo.filePath,
                    fileName: (trackInfo.filePath as NSString).lastPathComponent,
                    fileExtension: trackInfo.fileExtension,
                    title: trackInfo.title,
                    artistName: trackInfo.artist,
                    albumTitle: trackInfo.album,
                    duration: trackInfo.duration
                )
                synth.id = trackInfo.id
                await MainActor.run {
                    trackForSearch = synth
                }
            }
        }
    }
}
