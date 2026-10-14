import SwiftUI

/// Volume slider with icon, mute toggle, and smooth gradient fill.
struct VolumeSlider: View {
    @Binding var volume: Float
    @Binding var isMuted: Bool
    var width: CGFloat = 100
    
    @State private var isHovered = false
    
    private var displayVolume: CGFloat {
        isMuted ? 0 : CGFloat(volume)
    }
    
    private var volumeIcon: String {
        if isMuted || volume == 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Mute toggle
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    isMuted.toggle()
                }
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LumoColors.textSecondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")
            
            // Slider track
            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.1))
                        .frame(height: isHovered ? 5 : 3)
                    
                    Capsule()
                        .fill(LumoColors.accent.opacity(0.8))
                        .frame(
                            width: max(0, trackWidth * displayVolume),
                            height: isHovered ? 5 : 3
                        )
                    
                    if isHovered {
                        Circle()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                            .shadow(color: .black.opacity(0.2), radius: 1)
                            .offset(x: max(0, min(trackWidth * displayVolume - 5, trackWidth - 10)))
                    }
                }
                .frame(height: 10)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(value.location.x / trackWidth, 1))
                            volume = Float(fraction)
                            if isMuted && volume > 0 {
                                isMuted = false
                            }
                        }
                )
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHovered = hovering
                    }
                }
            }
            .frame(width: width, height: 10)
        }
    }
}
