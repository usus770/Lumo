import SwiftUI

/// Expanded now-playing view showing lyrics, visualizer, and full controls.
/// Driven by the unified NowPlayingSnapshot for zero-flicker local and external playback.
struct NowPlayingExpandedView: View {
    @Environment(PlaybackState.self) private var playbackState
    @Environment(WindowManager.self) private var windowManager
    @Environment(\.openWindow) private var openWindow
    @State private var nowPlaying = NowPlayingSnapshot.shared
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let currentPos = nowPlaying.position(at: ProcessInfo.processInfo.systemUptime)
            let lyricsPos = nowPlaying.lyricsTime(at: ProcessInfo.processInfo.systemUptime)
            
            VStack(spacing: 0) {
                // Drag handle
                Rectangle()
                    .fill(LumoColors.textTertiary.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                
                HStack(spacing: 0) {
                    // Left: Artwork + Visualizer
                    VStack(spacing: 16) {
                        // Large artwork
                        ArtworkView(
                            data: nowPlaying.artworkData,
                            fallbackTitle: nowPlaying.title.isEmpty ? "Lumo" : nowPlaying.title,
                            size: 200,
                            cornerRadius: 12
                        )
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                        
                        // Visualizer button
                        Button {
                            VisualizerWindowController.shared.showFullScreen()
                        } label: {
                            VisualizerView()
                                .frame(height: 80)
                                .frame(maxWidth: 220)
                                .padding(.horizontal, 20)
                                .background(Color.black.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .help("Open Full-Screen Visualizer")
                    }
                    .frame(width: 260)
                    .padding(.leading, 24)
                    
                    Divider()
                        .padding(.vertical, 24)
                    
                    // Center: Track info + Controls
                    VStack(spacing: 16) {
                        // Track info
                        VStack(spacing: 8) {
                            Text(nowPlaying.title.isEmpty ? "Not Playing" : nowPlaying.title)
                                .font(LumoFonts.playerTitle)
                                .foregroundStyle(LumoColors.textPrimary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            
                            Text(nowPlaying.artist)
                                .font(LumoFonts.playerArtist)
                                .foregroundStyle(LumoColors.textSecondary)
                                .lineLimit(1)
                            
                            if !nowPlaying.album.isEmpty {
                                Text(nowPlaying.album)
                                    .font(LumoFonts.bodyMedium)
                                    .foregroundStyle(LumoColors.textTertiary)
                                    .lineLimit(1)
                            }
                            
                            // Source indicator for external
                            if nowPlaying.isExternal {
                                HStack(spacing: 6) {
                                    if let icon = nowPlaying.appIcon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 12, height: 12)
                                    } else {
                                        Image(systemName: "link")
                                            .font(.system(size: 10))
                                    }
                                    Text(nowPlaying.appName)
                                        .font(LumoFonts.micro)
                                }
                                .foregroundStyle(LumoColors.accent)
                                .padding(.top, 4)
                            }
                        }
                        
                        // Scrubber
                        VStack(spacing: 8) {
                            ScrubberView(
                                currentTime: Binding(
                                    get: { currentPos },
                                    set: { nowPlaying.seek(to: $0) }
                                ),
                                duration: nowPlaying.duration
                            ) { time in
                                nowPlaying.seek(to: time)
                            }
                        }
                        .frame(maxWidth: 400)
                        .padding(.horizontal, 40)
                        
                        // Transport controls
                        HStack(spacing: 24) {
                            // Shuffle
                            Button {
                                playbackState.toggleShuffle()
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .buttonStyle(LumoIconButtonStyle(size: 32, isActive: playbackState.isShuffleEnabled))
                            .help("Shuffle")
                            .disabled(nowPlaying.isExternal)
                            
                            // Previous
                            Button {
                                nowPlaying.previousTrack()
                            } label: {
                                Image(systemName: "backward.fill").font(.system(size: 18))
                            }
                            .buttonStyle(LumoIconButtonStyle(size: 36))
                            .help("Previous")
                            
                            // Play/Pause
                            Button {
                                nowPlaying.togglePlayPause()
                            } label: {
                                Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24, weight: .semibold))
                            }
                            .buttonStyle(.lumoPlay)
                            .frame(width: 56, height: 56)
                            .help(nowPlaying.isPlaying ? "Pause" : "Play")
                            
                            // Next
                            Button {
                                nowPlaying.nextTrack()
                            } label: {
                                Image(systemName: "forward.fill").font(.system(size: 18))
                            }
                            .buttonStyle(LumoIconButtonStyle(size: 36))
                            .help("Next")
                            
                            // Repeat
                            Button {
                                playbackState.cycleRepeatMode()
                            } label: {
                                Image(systemName: playbackState.repeatMode.icon)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .buttonStyle(LumoIconButtonStyle(size: 32, isActive: playbackState.repeatMode.isActive))
                            .help("Repeat: \(playbackState.repeatMode.rawValue)")
                            .disabled(nowPlaying.isExternal)
                        }
                        
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
                            width: 140
                        )
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider()
                        .padding(.vertical, 24)
                    
                    // Right: Lyrics
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Lyrics")
                                .font(LumoFonts.headingMedium)
                                .foregroundStyle(LumoColors.textPrimary)
                            Spacer()
                            if !nowPlaying.isExternal, let track = playbackState.currentTrack {
                                FavoriteButton(trackId: track.id)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        LyricsView(
                            lyricsText: nowPlaying.lyricsText,
                            hasSyncedLyrics: nowPlaying.hasSyncedLyrics,
                            currentTime: lyricsPos
                        )
                        .frame(maxWidth: 320)
                        .frame(maxHeight: .infinity)
                    }
                    .frame(width: 360)
                    .padding(.trailing, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                DynamicBackground(artworkData: nowPlaying.artworkData)
                    .ignoresSafeArea()
            )
        }
    }
}