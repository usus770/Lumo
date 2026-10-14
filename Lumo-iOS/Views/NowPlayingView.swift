import SwiftUI

/// Full-screen immersive Now Playing view for Lumo iOS.
public struct iOSNowPlayingView: View {
    @ObservedObject private var playbackState = iOSPlaybackState.shared
    @ObservedObject private var audioEngine = iOSAudioEngine.shared
    @State private var isDraggingScrubber: Bool = false
    @State private var scrubTime: TimeInterval = 0
    @State private var showLyrics: Bool = false
    @State private var parsedLyrics: [iOSLyricsLine] = []
    
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        ZStack {
            LumoTheme.bg0.ignoresSafeArea()
            
            // Dynamic Background Ambient Glow
            RadialGradient(
                colors: [
                    LumoTheme.accentPink.opacity(0.18),
                    LumoTheme.accentViolet.opacity(0.08),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Top Grabber & Dismiss Button
                topBar
                    .padding(.top, 8)
                
                Spacer()
                
                // Center Area: Artwork or Synced Lyrics
                if showLyrics, !parsedLyrics.isEmpty {
                    lyricsView
                        .frame(maxHeight: 340)
                } else {
                    artworkCard
                }
                
                Spacer()
                
                // Track Info & Favorite/Lyrics Toggle
                trackMetadataBar
                
                // Audio Scrubber
                scrubberBar
                
                // Transport Controls
                transportControls
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            loadLyrics()
        }
        .onChange(of: playbackState.currentTrack) { _ in
            loadLyrics()
        }
    }
    
    // MARK: - Subviews
    
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(LumoTheme.textSecondary)
                    .padding(8)
                    .background(Circle().fill(LumoTheme.surfaceRaised))
            }
            
            Spacer()
            
            Text("Lumo Player")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LumoTheme.textSecondary)
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showLyrics.toggle()
                }
            } label: {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(showLyrics ? LumoTheme.accentPink : LumoTheme.textSecondary)
                    .padding(8)
                    .background(Circle().fill(LumoTheme.surfaceRaised))
            }
        }
    }
    
    private var artworkCard: some View {
        ZStack {
            // Neon Glow Shadow
            RoundedRectangle(cornerRadius: 24)
                .fill(LumoTheme.brandGradient)
                .blur(radius: 28)
                .opacity(audioEngine.isPlaying ? 0.45 : 0.20)
                .frame(width: 270, height: 270)
            
            if let track = playbackState.currentTrack,
               let data = track.artworkData,
               let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 290, height: 290)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(LumoTheme.stroke, lineWidth: 1.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LumoTheme.surfaceRaised)
                    .frame(width: 290, height: 290)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "music.note")
                                .font(.system(size: 64))
                                .foregroundStyle(LumoTheme.brandGradient)
                            Text("Lumo Audio")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(LumoTheme.textTertiary)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(LumoTheme.stroke, lineWidth: 1.5)
                    )
            }
        }
        .padding(.vertical, 8)
    }
    
    private var lyricsView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    ForEach(parsedLyrics) { line in
                        let isActive = audioEngine.currentTime >= line.time &&
                            (parsedLyrics.first(where: { $0.time > line.time })?.time ?? Double.infinity) > audioEngine.currentTime
                        
                        VStack(spacing: 4) {
                            Text(line.text)
                                .font(.system(size: isActive ? 22 : 16, weight: isActive ? .bold : .medium))
                                .foregroundStyle(isActive ? LumoTheme.textPrimary : LumoTheme.textTertiary)
                                .multilineTextAlignment(.center)
                            
                            if let romanized = line.romanizedText {
                                Text(romanized)
                                    .font(.system(size: isActive ? 14 : 12, weight: .regular))
                                    .foregroundStyle(isActive ? LumoTheme.accentAmber : LumoTheme.textTertiary.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .id(line.id)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 40)
            }
            .onChange(of: audioEngine.currentTime) { time in
                if let currentLine = parsedLyrics.last(where: { $0.time <= time }) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(currentLine.id, anchor: .center)
                    }
                }
            }
        }
    }
    
    private var trackMetadataBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(playbackState.currentTrack?.title ?? "No Track Playing")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LumoTheme.textPrimary)
                    .lineLimit(1)
                
                Text(playbackState.currentTrack?.artist ?? "Select a track to play")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LumoTheme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Audio Quality Tag
            Text("LOSSLESS")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(LumoTheme.accentAmber)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(LumoTheme.accentAmber.opacity(0.15))
                .clipShape(Capsule())
        }
    }
    
    private var scrubberBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isDraggingScrubber ? scrubTime : audioEngine.currentTime },
                    set: { newVal in
                        isDraggingScrubber = true
                        scrubTime = newVal
                    }
                ),
                in: 0...max(audioEngine.duration, 1.0)
            ) { editing in
                if !editing {
                    playbackState.seek(to: scrubTime)
                    isDraggingScrubber = false
                }
            }
            .tint(LumoTheme.accentPink)
            
            HStack {
                Text(formatTime(isDraggingScrubber ? scrubTime : audioEngine.currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(LumoTheme.textTertiary)
                Spacer()
                Text("-\(formatTime(max(0, audioEngine.duration - (isDraggingScrubber ? scrubTime : audioEngine.currentTime))))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(LumoTheme.textTertiary)
            }
        }
    }
    
    private var transportControls: some View {
        HStack(spacing: 32) {
            // Shuffle
            Button {
                withAnimation {
                    playbackState.toggleShuffle()
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(playbackState.isShuffleEnabled ? LumoTheme.accentPink : LumoTheme.textSecondary)
            }
            
            // Previous
            Button {
                playbackState.previousTrack()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(LumoTheme.textPrimary)
            }
            
            // Play / Pause
            Button {
                playbackState.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(LumoTheme.brandGradient)
                        .frame(width: 68, height: 68)
                        .shadow(color: LumoTheme.accentPink.opacity(0.4), radius: 14, y: 4)
                    
                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.black)
                }
            }
            
            // Next
            Button {
                playbackState.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(LumoTheme.textPrimary)
            }
            
            // Repeat
            Button {
                withAnimation {
                    playbackState.cycleRepeatMode()
                }
            } label: {
                Image(systemName: playbackState.repeatMode.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(playbackState.repeatMode.isActive ? LumoTheme.accentPink : LumoTheme.textSecondary)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func loadLyrics() {
        if let text = playbackState.currentTrack?.lyricsText, !text.isEmpty {
            parsedLyrics = iOSLyricsEngine.parse(lrcContent: text)
        } else {
            parsedLyrics = []
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
