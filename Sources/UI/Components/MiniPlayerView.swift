import SwiftUI
import AppKit

/// Full-featured mini player view for the menu bar popover.
/// Reads from unified NowPlayingSnapshot for seamless local and external playback.
struct MiniPlayerView: View {
    @Environment(PlaybackState.self) private var playbackState
    @State private var nowPlaying = NowPlayingSnapshot.shared
    @State private var windowManager = WindowManager.shared
    @State private var isHoveringScrubber = false
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let currentPos = nowPlaying.position(at: ProcessInfo.processInfo.systemUptime)
            
            VStack(spacing: 0) {
                // Header with source app if external
                if nowPlaying.isExternal {
                    HStack {
                        if let icon = nowPlaying.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text("Playing from \(nowPlaying.appName)")
                            .font(LumoFonts.micro)
                            .foregroundStyle(LumoColors.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }
                
                Divider()
                
                // Main content
                HStack(spacing: 14) {
                    // Artwork
                    ArtworkView(
                        data: nowPlaying.artworkData,
                        fallbackTitle: nowPlaying.title.isEmpty ? "Lumo" : nowPlaying.title,
                        size: 72,
                        cornerRadius: 10
                    )
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    
                    // Track info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(nowPlaying.title.isEmpty ? "Not Playing" : nowPlaying.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(nowPlaying.title.isEmpty ? LumoColors.textTertiary : LumoColors.textPrimary)
                            .lineLimit(1)
                        
                        Text(nowPlaying.artist)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(LumoColors.textSecondary)
                            .lineLimit(1)
                        
                        if !nowPlaying.album.isEmpty {
                            Text(nowPlaying.album)
                                .font(.system(size: 11))
                                .foregroundStyle(LumoColors.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Favorite button (only for local tracks)
                    if !nowPlaying.isExternal, let track = playbackState.currentTrack {
                        FavoriteButton(trackId: track.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                
                // Scrubber
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        let trackWidth = geometry.size.width
                        
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.1))
                                .frame(height: isHoveringScrubber ? 5 : 3)
                            
                            let progress = nowPlaying.duration > 0 ? CGFloat(currentPos / nowPlaying.duration) : 0
                            Capsule()
                                .fill(LumoColors.progressGradient)
                                .frame(
                                    width: max(0, trackWidth * progress),
                                    height: isHoveringScrubber ? 5 : 3
                                )
                            
                            if isHoveringScrubber {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 10, height: 10)
                                    .shadow(color: .black.opacity(0.2), radius: 1)
                                    .offset(x: max(0, min(trackWidth * progress - 5, trackWidth - 10)))
                            }
                        }
                        .frame(height: 10)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let fraction = max(0, min(value.location.x / trackWidth, 1))
                                    let seekTime = Double(fraction) * nowPlaying.duration
                                    nowPlaying.seek(to: seekTime)
                                }
                        )
                        .onHover { hovering in
                            withAnimation(.easeOut(duration: 0.12)) {
                                isHoveringScrubber = hovering
                            }
                        }
                    }
                    .frame(height: 10)
                    .padding(.horizontal, 16)
                    
                    // Time labels
                    HStack {
                        Text(PlaybackState.formatTime(currentPos))
                            .font(LumoFonts.mono)
                            .foregroundStyle(LumoColors.textTertiary)
                        
                        Spacer()
                        
                        Text("-" + PlaybackState.formatTime(max(0, nowPlaying.duration - currentPos)))
                            .font(LumoFonts.mono)
                            .foregroundStyle(LumoColors.textTertiary)
                    }
                    .padding(.horizontal, 16)
                }
                
                // Controls
                HStack(spacing: 8) {
                    // Shuffle (local only)
                    if !nowPlaying.isExternal {
                        Button {
                            playbackState.toggleShuffle()
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(LumoIconButtonStyle(size: 22, isActive: playbackState.isShuffleEnabled))
                        .help("Shuffle")
                    }
                    
                    // Previous
                    Button {
                        nowPlaying.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(LumoIconButtonStyle(size: 26))
                    .help("Previous")
                    
                    // Play/Pause
                    Button {
                        nowPlaying.togglePlayPause()
                    } label: {
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.lumoPlay)
                    .help(nowPlaying.isPlaying ? "Pause" : "Play")
                    
                    // Next
                    Button {
                        nowPlaying.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(LumoIconButtonStyle(size: 26))
                    .help("Next")
                    
                    // Repeat (local only)
                    if !nowPlaying.isExternal {
                        Button {
                            playbackState.cycleRepeatMode()
                        } label: {
                            Image(systemName: playbackState.repeatMode.icon)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(LumoIconButtonStyle(size: 22, isActive: playbackState.repeatMode.isActive))
                        .help("Repeat: \(playbackState.repeatMode.rawValue)")
                    }
                    
                    Spacer()
                    
                    // Volume
                    VolumeSlider(
                        volume: .init(
                            get: { playbackState.volume },
                            set: { playbackState.volume = $0 }
                        ),
                        isMuted: .init(
                            get: { playbackState.isMuted },
                            set: { playbackState.isMuted = $0 }
                        ),
                        width: 80
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                
                Divider()
                
                // Footer actions
                HStack(spacing: 12) {
                    Button("Open Lumo") {
                        NSApp.activate(ignoringOtherApps: true)
                        for window in NSApp.windows {
                            if window.identifier?.rawValue == "main" {
                                window.makeKeyAndOrderFront(nil)
                                break
                            }
                        }
                    }
                    .buttonStyle(.lumoSecondary)
                    .font(LumoFonts.bodySmall)
                    
                    Spacer()
                    
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .font(LumoFonts.bodySmall)
                    .foregroundStyle(LumoColors.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(width: 380)
            .background(.ultraThinMaterial)
        }
    }
}

/// Compact mini player for always-on-top floating window (M6)
struct CompactMiniPlayerView: View {
    @Environment(PlaybackState.self) private var playbackState
    @State private var nowPlaying = NowPlayingSnapshot.shared
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Artwork
            ArtworkView(
                data: nowPlaying.artworkData,
                fallbackTitle: nowPlaying.title.isEmpty ? "Lumo" : nowPlaying.title,
                size: 40,
                cornerRadius: 6
            )
            
            // Track info
            VStack(alignment: .leading, spacing: 1) {
                Text(nowPlaying.title.isEmpty ? "Not Playing" : nowPlaying.title)
                    .font(LumoFonts.bodySmall.weight(.semibold))
                    .foregroundStyle(nowPlaying.title.isEmpty ? LumoColors.textTertiary : LumoColors.textPrimary)
                    .lineLimit(1)
                
                if !nowPlaying.artist.isEmpty {
                    Text(nowPlaying.artist)
                        .font(LumoFonts.micro)
                        .foregroundStyle(LumoColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Controls
            HStack(spacing: 6) {
                Button {
                    nowPlaying.previousTrack()
                } label: {
                    Image(systemName: "backward.fill").font(.system(size: 11))
                }
                .buttonStyle(LumoIconButtonStyle(size: 20))
                
                Button {
                    nowPlaying.togglePlayPause()
                } label: {
                    Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.lumoPlay)
                
                Button {
                    nowPlaying.nextTrack()
                } label: {
                    Image(systemName: "forward.fill").font(.system(size: 11))
                }
                .buttonStyle(LumoIconButtonStyle(size: 20))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .scaleEffect(isHovering ? 1.01 : 1.0)
    }
}