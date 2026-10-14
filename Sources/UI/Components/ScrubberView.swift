import SwiftUI

/// An interactive progress scrubber with time labels and gradient fill.
struct ScrubberView: View {
    @Binding var currentTime: TimeInterval
    let duration: TimeInterval
    var onSeek: ((TimeInterval) -> Void)?
    
    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0
    @State private var isHovered = false
    
    private var displayTime: TimeInterval {
        isDragging ? dragTime : currentTime
    }
    
    private var progress: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(displayTime / duration)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Scrubber track
            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(.white.opacity(0.1))
                        .frame(height: isHovered || isDragging ? 6 : 4)
                    
                    // Filled portion with gradient
                    Capsule()
                        .fill(LumoColors.progressGradient)
                        .frame(
                            width: max(0, trackWidth * progress),
                            height: isHovered || isDragging ? 6 : 4
                        )
                    
                    // Thumb indicator (visible on hover/drag)
                    if isHovered || isDragging {
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                            .offset(x: max(0, min(trackWidth * progress - 6, trackWidth - 12)))
                    }
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let fraction = max(0, min(value.location.x / trackWidth, 1))
                            dragTime = Double(fraction) * duration
                        }
                        .onEnded { value in
                            let fraction = max(0, min(value.location.x / trackWidth, 1))
                            let seekTime = Double(fraction) * duration
                            currentTime = seekTime
                            onSeek?(seekTime)
                            isDragging = false
                        }
                )
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
            }
            .frame(height: 12)
            
            // Time labels
            HStack {
                Text(PlaybackState.formatTime(displayTime))
                    .font(LumoFonts.mono)
                    .foregroundStyle(LumoColors.textTertiary)
                
                Spacer()
                
                Text("-" + PlaybackState.formatTime(max(0, duration - displayTime)))
                    .font(LumoFonts.mono)
                    .foregroundStyle(LumoColors.textTertiary)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
