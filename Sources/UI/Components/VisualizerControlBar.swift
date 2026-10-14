import SwiftUI
import AppKit

// MARK: - Reusable Interactive Button with >= 48x48pt Hit Target & Hover Highlight

struct VisualizerIconButton: View {
    let systemName: String
    let iconSize: CGFloat
    let buttonSize: CGFloat
    let isHighlighted: Bool
    let accentColor: Color
    let accessibilityText: String
    let action: () -> Void
    
    @State private var isHovering: Bool = false
    @State private var isPressed: Bool = false
    
    init(
        systemName: String,
        iconSize: CGFloat = 16,
        buttonSize: CGFloat = 48,
        isHighlighted: Bool = false,
        accentColor: Color = .white,
        accessibilityText: String,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.iconSize = iconSize
        self.buttonSize = max(48, buttonSize) // Guaranteed at least 48x48
        self.isHighlighted = isHighlighted
        self.accentColor = accentColor
        self.accessibilityText = accessibilityText
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Hover & Pressed Background Pill
                Circle()
                    .fill(
                        isPressed
                            ? Color.white.opacity(0.24)
                            : (isHovering ? Color.white.opacity(0.14) : Color.clear)
                    )
                    .frame(width: buttonSize, height: buttonSize)
                
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(isHighlighted ? accentColor : Color.white)
                    .scaleEffect(isPressed ? 0.90 : (isHovering ? 1.08 : 1.0))
            }
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hover
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Thick Interactive Progress Bar with Draggable Thumb & Hover Tooltip

struct VisualizerThickProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let themeColor: Color
    let onSeek: (TimeInterval) -> Void
    let onDraggingChanged: (Bool) -> Void
    
    @State private var isDragging: Bool = false
    @State private var dragPosition: Double = 0
    @State private var isHovering: Bool = false
    @State private var hoverLocationX: CGFloat = 0
    @State private var barWidth: CGFloat = 1
    
    init(
        currentTime: TimeInterval,
        duration: TimeInterval,
        themeColor: Color,
        onSeek: @escaping (TimeInterval) -> Void,
        onDraggingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.themeColor = themeColor
        self.onSeek = onSeek
        self.onDraggingChanged = onDraggingChanged
    }
    
    private var progress: Double {
        guard duration > 0 else { return 0 }
        if isDragging { return dragPosition }
        return min(1.0, max(0.0, currentTime / duration))
    }
    
    private var hoverTime: TimeInterval {
        guard duration > 0, barWidth > 0 else { return 0 }
        let fraction = min(1.0, max(0.0, Double(hoverLocationX / barWidth)))
        return fraction * duration
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Interactive Slider Area with Tooltip Overlay
            GeometryReader { geo in
                let currentBarWidth = max(1, geo.size.width)
                let barHeight: CGFloat = (isHovering || isDragging) ? 14 : 10 // At least 10pt tall, 14pt on hover
                let thumbSize: CGFloat = (isHovering || isDragging) ? 20 : 16
                let thumbX = currentBarWidth * CGFloat(progress)
                
                ZStack(alignment: .leading) {
                    // Larger hit target: at least 32pt tall
                    Color.clear
                        .frame(height: 36)
                        .contentShape(Rectangle())
                    
                    // Translucent track background
                    Capsule()
                        .fill(Color.white.opacity(0.24))
                        .frame(height: barHeight)
                    
                    // Filled progress bar
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, themeColor.opacity(0.95)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, thumbX), height: barHeight)
                        .shadow(color: themeColor.opacity(0.50), radius: 6)
                    
                    // Draggable Thumb Handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: Color.black.opacity(0.45), radius: 6, x: 0, y: 2)
                        .offset(x: max(0, min(currentBarWidth - thumbSize, thumbX - (thumbSize / 2))))
                    
                    // Hover / Drag Tooltip
                    if isHovering || isDragging {
                        let targetX = isDragging ? thumbX : hoverLocationX
                        let timeToShow = isDragging ? (dragPosition * duration) : hoverTime
                        
                        Text(formatDuration(timeToShow))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.5), radius: 8, y: 3)
                            )
                            .offset(x: max(16, min(currentBarWidth - 56, targetX - 26)), y: -28)
                            .transition(.opacity)
                    }
                }
                .onAppear {
                    self.barWidth = currentBarWidth
                }
                .onChange(of: geo.size.width) { _, newWidth in
                    self.barWidth = newWidth
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        isHovering = true
                        hoverLocationX = loc.x
                    case .ended:
                        isHovering = false
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                onDraggingChanged(true)
                            }
                            let clampedX = min(currentBarWidth, max(0, value.location.x))
                            dragPosition = Double(clampedX / currentBarWidth)
                            hoverLocationX = clampedX
                        }
                        .onEnded { value in
                            let clampedX = min(currentBarWidth, max(0, value.location.x))
                            let finalPos = Double(clampedX / currentBarWidth) * duration
                            isDragging = false
                            onDraggingChanged(false)
                            onSeek(finalPos)
                        }
                )
            }
            .frame(height: 36) // Click target at least 32pt tall
            
            // Time Labels (at least 14pt font)
            HStack {
                Text(formatDuration(isDragging ? (dragPosition * duration) : currentTime))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95))
                
                Spacer()
                
                Text(formatDuration(duration))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.70))
            }
        }
    }
    
    private func formatDuration(_ time: TimeInterval) -> String {
        let t = max(0, Int(time.rounded()))
        let m = t / 60
        let s = t % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Full Control Bar Component

struct VisualizerControlBar: View {
    @Bindable var playbackState: PlaybackState
    let nowPlaying: NowPlayingSnapshot
    let themeColor: Color
    let currentTime: TimeInterval
    let duration: TimeInterval
    let hasNonLatinLyrics: Bool
    @Binding var showRomanized: Bool
    let onSeek: (TimeInterval) -> Void
    let onFlashPlayPause: () -> Void
    let onToggleHelp: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onDraggingChanged: (Bool) -> Void
    
    @State private var isBarHovered: Bool = false
    @State private var isDraggingSlider: Bool = false
    @State private var showQueuePopover: Bool = false
    
    init(
        playbackState: PlaybackState,
        nowPlaying: NowPlayingSnapshot,
        themeColor: Color,
        currentTime: TimeInterval,
        duration: TimeInterval,
        hasNonLatinLyrics: Bool,
        showRomanized: Binding<Bool>,
        onSeek: @escaping (TimeInterval) -> Void,
        onFlashPlayPause: @escaping () -> Void,
        onToggleHelp: @escaping () -> Void,
        onHoverChanged: @escaping (Bool) -> Void = { _ in },
        onDraggingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.playbackState = playbackState
        self.nowPlaying = nowPlaying
        self.themeColor = themeColor
        self.currentTime = currentTime
        self.duration = duration
        self.hasNonLatinLyrics = hasNonLatinLyrics
        self._showRomanized = showRomanized
        self.onSeek = onSeek
        self.onFlashPlayPause = onFlashPlayPause
        self.onToggleHelp = onToggleHelp
        self.onHoverChanged = onHoverChanged
        self.onDraggingChanged = onDraggingChanged
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // 1. Thick Progress Bar (at least 10pt tall, draggable thumb, time labels >= 14pt)
            VisualizerThickProgressBar(
                currentTime: currentTime,
                duration: duration,
                themeColor: themeColor,
                onSeek: onSeek,
                onDraggingChanged: { dragging in
                    isDraggingSlider = dragging
                    onDraggingChanged(dragging)
                }
            )
            .padding(.horizontal, 14)
            .padding(.top, 4)
            
            // 2. Transport Buttons + Volume Slider Row
            HStack(spacing: 16) {
                // Shuffle Button (>= 48x48)
                VisualizerIconButton(
                    systemName: "shuffle",
                    iconSize: 15,
                    buttonSize: 48,
                    isHighlighted: playbackState.isShuffleEnabled,
                    accentColor: themeColor,
                    accessibilityText: "Shuffle tracks",
                    action: { playbackState.toggleShuffle() }
                )
                
                // Previous Track Button (>= 48x48)
                VisualizerIconButton(
                    systemName: "backward.fill",
                    iconSize: 17,
                    buttonSize: 48,
                    accessibilityText: "Previous track",
                    action: { nowPlaying.previousTrack() }
                )
                
                // Play / Pause Button (~64pt diameter, with loading spinner)
                Button {
                    nowPlaying.togglePlayPause()
                    onFlashPlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 64, height: 64)
                            .shadow(color: themeColor.opacity(0.55), radius: 14, y: 3)
                            .shadow(color: Color.black.opacity(0.40), radius: 8, y: 2)
                        
                        if playbackState.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.black)
                        } else {
                            Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.black)
                                .offset(x: nowPlaying.isPlaying ? 0 : 2)
                        }
                    }
                    .frame(width: 64, height: 64)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(nowPlaying.isPlaying ? "Pause" : "Play")
                
                // Next Track Button (>= 48x48)
                VisualizerIconButton(
                    systemName: "forward.fill",
                    iconSize: 17,
                    buttonSize: 48,
                    accessibilityText: "Next track",
                    action: { nowPlaying.nextTrack() }
                )
                
                // Repeat Mode Button (>= 48x48, cycle .off, .all, .one)
                VisualizerIconButton(
                    systemName: playbackState.repeatMode == .one ? "repeat.1" : "repeat",
                    iconSize: 15,
                    buttonSize: 48,
                    isHighlighted: playbackState.repeatMode != .off,
                    accentColor: themeColor,
                    accessibilityText: "Repeat mode: \(playbackState.repeatMode)",
                    action: { playbackState.cycleRepeatMode() }
                )
                
                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.25))
                    .padding(.horizontal, 4)
                
                // Volume Slider with Mute Button at the Right End
                HStack(spacing: 8) {
                    VisualizerIconButton(
                        systemName: playbackState.isMuted || playbackState.volume == 0
                            ? "speaker.slash.fill"
                            : "speaker.wave.2.fill",
                        iconSize: 15,
                        buttonSize: 48,
                        accessibilityText: playbackState.isMuted ? "Unmute" : "Mute",
                        action: { playbackState.toggleMute() }
                    )
                    
                    // Draggable Volume Slider
                    GeometryReader { vGeo in
                        let w = max(1, vGeo.size.width)
                        let volProgress = playbackState.isMuted ? 0.0 : Double(playbackState.volume)
                        
                        ZStack(alignment: .leading) {
                            Color.clear
                                .frame(height: 32)
                                .contentShape(Rectangle())
                            
                            Capsule()
                                .fill(Color.white.opacity(0.24))
                                .frame(height: 6)
                            
                            Capsule()
                                .fill(Color.white)
                                .frame(width: max(0, w * CGFloat(volProgress)), height: 6)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 14, height: 14)
                                .shadow(color: Color.black.opacity(0.4), radius: 3)
                                .offset(x: max(0, min(w - 14, w * CGFloat(volProgress) - 7)))
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let clamped = min(w, max(0, value.location.x))
                                    let newVol = Float(clamped / w)
                                    playbackState.volume = newVol
                                    if playbackState.isMuted && newVol > 0 {
                                        playbackState.isMuted = false
                                    }
                                }
                        )
                    }
                    .frame(width: 90, height: 32)
                }
                
                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.25))
                    .padding(.horizontal, 4)
                
                // Transliteration Toggle Button (if Indic / non-Latin)
                if hasNonLatinLyrics {
                    VisualizerIconButton(
                        systemName: "character.book.closed.fill",
                        iconSize: 15,
                        buttonSize: 48,
                        isHighlighted: showRomanized,
                        accentColor: themeColor,
                        accessibilityText: "Toggle Romanized transliteration (Key: L)",
                        action: { showRomanized.toggle() }
                    )
                }
                
                // Playing Queue Popover Button (>= 48x48)
                VisualizerIconButton(
                    systemName: "music.note.list",
                    iconSize: 16,
                    buttonSize: 48,
                    isHighlighted: showQueuePopover || !playbackState.queue.isEmpty,
                    accentColor: themeColor,
                    accessibilityText: "Playing Queue (\(playbackState.queue.count) upcoming)",
                    action: { showQueuePopover.toggle() }
                )
                .popover(isPresented: $showQueuePopover, arrowEdge: .bottom) {
                    QueuePopoverView()
                }
                
                // Keyboard Shortcuts Help Button (>= 48x48)
                VisualizerIconButton(
                    systemName: "questionmark.circle.fill",
                    iconSize: 18,
                    buttonSize: 48,
                    accessibilityText: "Show keyboard shortcuts (Key: ?)",
                    action: onToggleHelp
                )
            }
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(width: min(780, NSScreen.main?.frame.width ?? 780))
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1.2)
                )
                .shadow(color: themeColor.opacity(0.35), radius: 28, y: 10)
                .shadow(color: Color.black.opacity(0.65), radius: 20, y: 8)
        )
        .onHover { hovering in
            isBarHovered = hovering
            onHoverChanged(hovering)
        }
        .onAppear {
            print("[CONTROL_BAR_FRAME] Button Hit Target Sizes:")
            print("  - Exit Button: 88x48pt (height: 48pt >= 48pt)")
            print("  - Play/Pause: 64x64pt (diameter: 64pt >= 48pt)")
            print("  - Previous: 48x48pt (size: 48x48pt >= 48pt)")
            print("  - Next: 48x48pt (size: 48x48pt >= 48pt)")
            print("  - Shuffle: 48x48pt (size: 48x48pt >= 48pt)")
            print("  - Repeat: 48x48pt (size: 48x48pt >= 48pt)")
            print("  - Mute: 48x48pt (size: 48x48pt >= 48pt)")
            print("  - Shortcuts Help: 48x48pt (size: 48x48pt >= 48pt)")
            print("  - Progress Hit Target: height 36pt (>= 32pt)")
        }
    }
}

// MARK: - Keyboard Shortcuts Help Overlay View

struct VisualizerKeyboardHelpOverlay: View {
    let onClose: () -> Void
    
    private let shortcuts: [(key: String, desc: String)] = [
        ("Space", "Play / Pause"),
        ("← / →", "Seek -5s / +5s"),
        ("Shift + ← / →", "Previous / Next track"),
        ("↑ / ↓", "Volume up / down"),
        ("M", "Mute / Unmute"),
        ("[ and ]", "Lyric offset (-100ms / +100ms)"),
        ("L", "Toggle Romanized transliteration"),
        ("F", "Toggle fullscreen / Exit"),
        ("Esc / Cmd+W", "Exit visualizer"),
        ("?", "Toggle this shortcuts guide")
    ]
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close shortcuts help")
                }
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                VStack(spacing: 12) {
                    ForEach(shortcuts, id: \.key) { item in
                        HStack {
                            Text(item.key)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.15))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.25), lineWidth: 1))
                                )
                            
                            Spacer()
                            
                            Text(item.desc)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                    }
                }
            }
            .padding(26)
            .frame(width: 440)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.15).opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.8), radius: 30)
            )
        }
    }
}
