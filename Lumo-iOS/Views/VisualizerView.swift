import SwiftUI

/// Reactive Kinetic Visualizer screen for Lumo iOS.
public struct iOSVisualizerView: View {
    @ObservedObject private var playbackState = iOSPlaybackState.shared
    @ObservedObject private var audioEngine = iOSAudioEngine.shared
    @State private var barHeights: [CGFloat] = Array(repeating: 20, count: 24)
    @State private var timer: Timer?
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                LumoTheme.bg0.ignoresSafeArea()
                
                // Deep ambient glow
                RadialGradient(
                    colors: [
                        LumoTheme.accentViolet.opacity(0.25),
                        LumoTheme.accentPink.opacity(0.12),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 50,
                    endRadius: 400
                )
                .ignoresSafeArea()
                
                VStack(spacing: 28) {
                    Spacer()
                    
                    // Center Artwork / Visualizer Circle
                    ZStack {
                        Circle()
                            .fill(LumoTheme.surface)
                            .frame(width: 220, height: 220)
                            .overlay(
                                Circle()
                                    .stroke(LumoTheme.brandGradient, lineWidth: 3)
                                    .blur(radius: audioEngine.isPlaying ? 4 : 0)
                            )
                        
                        if let track = playbackState.currentTrack,
                           let data = track.artworkData,
                           let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 190, height: 190)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "waveform")
                                .font(.system(size: 64, weight: .bold))
                                .foregroundStyle(LumoTheme.brandGradient)
                        }
                    }
                    .shadow(color: LumoTheme.accentPink.opacity(audioEngine.isPlaying ? 0.4 : 0.1), radius: 30)
                    
                    // Track Title & Artist
                    VStack(spacing: 6) {
                        Text(playbackState.currentTrack?.title ?? "No Music Playing")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(LumoTheme.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        Text(playbackState.currentTrack?.artist ?? "Play a song from your library")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(LumoTheme.textSecondary)
                    }
                    
                    // Frequency Spectrum Bars
                    HStack(spacing: 5) {
                        ForEach(0..<barHeights.count, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [LumoTheme.accentPink, LumoTheme.accentViolet],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(width: 8, height: barHeights[i])
                                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: barHeights[i])
                        }
                    }
                    .frame(height: 120, alignment: .bottom)
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
            }
            .navigationTitle("Kinetic Visualizer")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                startAnimation()
            }
            .onDisappear {
                stopAnimation()
            }
        }
    }
    
    private func startAnimation() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            guard audioEngine.isPlaying else {
                for i in 0..<barHeights.count {
                    barHeights[i] = 10
                }
                return
            }
            
            for i in 0..<barHeights.count {
                let randomFactor = CGFloat.random(in: 15...110)
                barHeights[i] = randomFactor
            }
        }
    }
    
    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}
