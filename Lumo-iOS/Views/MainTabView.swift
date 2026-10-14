import SwiftUI

/// Main Tab Navigation and Floating Mini Player Bar for Lumo iOS.
public struct iOSMainTabView: View {
    @ObservedObject private var playbackState = iOSPlaybackState.shared
    @ObservedObject private var audioEngine = iOSAudioEngine.shared
    @State private var selectedTab: Int = 0
    @State private var showFullNowPlaying: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                iOSLibraryView()
                    .tabItem {
                        Label("Library", systemImage: "music.note.list")
                    }
                    .tag(0)
                
                iOSVisualizerView()
                    .tabItem {
                        Label("Visualizer", systemImage: "waveform")
                    }
                    .tag(1)
                
                iOSQueueView()
                    .tabItem {
                        Label("Queue", systemImage: "list.bullet")
                    }
                    .badge(playbackState.queue.count)
                    .tag(2)
                
                iOSSettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(3)
            }
            .tint(LumoTheme.accentPink)
            
            // Persistent Floating Mini-Player Bar
            if playbackState.currentTrack != nil {
                miniPlayerBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 54) // Positioned above the iOS Tab Bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showFullNowPlaying) {
            iOSNowPlayingView()
        }
    }
    
    // MARK: - Mini Player Bar
    
    private var miniPlayerBar: some View {
        HStack(spacing: 12) {
            // Artwork
            if let track = playbackState.currentTrack,
               let data = track.artworkData,
               let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LumoTheme.surfaceRaised)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(LumoTheme.accentPink)
                    )
            }
            
            // Title & Artist
            VStack(alignment: .leading, spacing: 2) {
                Text(playbackState.currentTrack?.title ?? "Not Playing")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LumoTheme.textPrimary)
                    .lineLimit(1)
                
                Text(playbackState.currentTrack?.artist ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LumoTheme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Play / Pause Button
            Button {
                playbackState.togglePlayPause()
            } label: {
                Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(LumoTheme.textPrimary)
                    .frame(width: 36, height: 36)
            }
            
            // Next Button
            Button {
                playbackState.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(LumoTheme.textSecondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LumoTheme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(LumoTheme.stroke, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 10, y: 4)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            showFullNowPlaying = true
        }
    }
}
