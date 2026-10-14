import SwiftUI
import AppKit
import ImageIO
import CoreImage
import QuartzCore

/// Redesigned Full-Screen Apple Music-Style Music Visualizer for Lumo.
/// Features:
/// - Target layout: Left panel (~35% width) with square artwork, drop glow, scrubber bar, marquee title/artist.
///   Right panel (~55% width) with vertically scrolling column of ALL lyric lines.
/// - Apple Music lyric styling: Current line bright white with 12% translucent rounded-rect highlight and soft glow;
///   past and upcoming lines grey with distance-based blur (0 to 6pt) and opacity (0.6 down to 0.25).
/// - Smooth spring auto-scroll keeping current line at ~38% panel height; manual scroll pauses auto-follow for 3s.
/// - Line-click and scrubber seeking directly to playback timestamp.
/// - Non-Latin & Hindi support: Original script main line + Romanized transliteration underneath + ad-lib dimmed opacity.
/// - Fallbacks: Plain unsynced lyrics scroll by progress estimation; no lyrics centers cover with clear label.
/// - Background: Blurred, scaled (1.6x), darkened artwork with subtle slow drift and dark scrim (> 7:1 contrast).
/// - Glowing border: Core Animation GPU-accelerated rotating conic gradient tracing display perimeter & notch contour.
/// - Retains ALL previous fixes: true full screen, 4 fail-safe exit paths, 2s watchdog, 30fps cap, cached assets.
struct KineticVisualizerView: View {
    @Environment(PlaybackState.self) private var playbackState
    
    // Core State
    private var nowPlaying: NowPlayingSnapshot { NowPlayingSnapshot.shared }
    private var visualizer: AudioVisualizer { AudioVisualizer.shared }
    
    // User Settings
    @AppStorage("visualizerGradientMode") private var gradientMode: String = "musicSync"
    @AppStorage("visualizerNotchCompatible") private var notchCompatible: Bool = true
    @AppStorage("visualizerBorderThickness") private var borderThickness: Double = 4.0
    @AppStorage("visualizerGlowIntensity") private var glowIntensity: Double = 22.0
    @AppStorage("visualizerOverrideColor") private var overrideColor: Bool = false
    @AppStorage("visualizerPrimaryColorHex") private var primaryColorHex: String = "#FF007F"
    @AppStorage("visualizerSecondaryColorHex") private var secondaryColorHex: String = "#7B00FF"
    
    // Transliteration, Debug & Interactive State
    @State private var showRomanized: Bool = true
    @State private var showDebugOverlay: Bool = false
    @State private var isVisualizerActive: Bool = true
    @State private var showControls: Bool = true
    @State private var showSettings: Bool = false
    @State private var isUserScrolling: Bool = false
    @State private var showShortcutsHelp: Bool = false
    
    // Control Hover & Interaction Tracking
    @State private var isHoveringControls: Bool = false
    @State private var isHoveringExit: Bool = false
    @State private var isDraggingSlider: Bool = false
    @State private var mousePoint: NSPoint = .zero
    
    // Play/Pause Center Flash Feedback
    @State private var flashFeedbackIcon: String? = nil
    @State private var flashFeedbackTask: Task<Void, Never>? = nil
    @State private var hideControlsTask: Task<Void, Never>? = nil
    @State private var userScrollResumeTask: Task<Void, Never>? = nil
    
    // Artwork & Palette Cache (computed once per track)
    @State private var cachedArtwork: NSImage? = nil
    @State private var cachedBlurredBackground: NSImage? = nil
    @State private var cachedPalette: (Color, Color, NSColor, NSColor) = (
        Color(hex: "#FF007F"),
        Color(hex: "#7B00FF"),
        NSColor(red: 1.0, green: 0.0, blue: 0.5, alpha: 1.0),
        NSColor(red: 0.48, green: 0.0, blue: 1.0, alpha: 1.0)
    )
    @State private var lastProcessedArtworkData: Data? = nil
    
    // Deterministic Seed for Tracks without Cover Art or Lyrics
    private var placeholderSeed: PlaceholderSeed {
        PlaceholderSeed(
            title: nowPlaying.title.isEmpty ? "Lumo" : nowPlaying.title,
            artist: nowPlaying.artist
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            if !isVisualizerActive {
                Color.black.ignoresSafeArea()
            } else {
                // Cap render loop at 30 FPS to guarantee CPU < 25%
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    let hostNow = ProcessInfo.processInfo.systemUptime
                    let currentPos = nowPlaying.position(at: hostNow)
                    let lyricsPos = nowPlaying.lyricsTime(at: hostNow)
                    let (_, glitch) = computeBeat(time: now)
                    
                    ZStack {
                        // 1. Drifting Heavily Blurred & Darkened Background Artwork
                        fullScreenBackground(geometry: geometry, time: now)
                        
                        // 2. Main Apple Music-Style Two-Panel Stage
                        mainTwoPanelStage(
                            geometry: geometry,
                            currentPos: currentPos,
                            lyricsPos: lyricsPos,
                            duration: nowPlaying.duration,
                            glitch: glitch,
                            time: now
                        )
                        
                        // 3. GPU Core Animation Glowing Border (traces screen corners and notch cutout)
                        neonEdgeGlow(geometry: geometry, glitch: glitch)
                        
                        // 4. Fail-Safe Top 60px Click Interceptor
                        topClickInterceptor(geometry: geometry)
                        
                        // 5. Solid High-Contrast Top Exit Button (>= 48pt tall, white on black, below notch)
                        if showControls {
                            topExitButton(geometry: geometry)
                                .transition(.opacity)
                        }
                        
                        // 6. Floating Glass Bottom Controls Bar (Thick progress bar, 48x48 transport buttons, volume slider + mute)
                        if showControls {
                            VStack {
                                Spacer()
                                VisualizerControlBar(
                                    playbackState: playbackState,
                                    nowPlaying: nowPlaying,
                                    themeColor: effectivePrimaryColor,
                                    currentTime: currentPos,
                                    duration: nowPlaying.duration,
                                    hasNonLatinLyrics: hasNonLatinLyrics,
                                    showRomanized: $showRomanized,
                                    onSeek: { newTime in
                                        PlaybackState.shared.seek(to: newTime)
                                    },
                                    onFlashPlayPause: {
                                        flashPlayPauseFeedback()
                                    },
                                    onToggleHelp: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showShortcutsHelp.toggle()
                                        }
                                    },
                                    onHoverChanged: { hovering in
                                        isHoveringControls = hovering
                                    },
                                    onDraggingChanged: { dragging in
                                        isDraggingSlider = dragging
                                    }
                                )
                                .padding(.bottom, max(geometry.safeAreaInsets.bottom + 20, 36))
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        
                        // 7. Large Center Play/Pause Flash Feedback (0.6s)
                        if let icon = flashFeedbackIcon {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.70))
                                    .frame(width: 120, height: 120)
                                    .overlay(Circle().stroke(Color.white.opacity(0.30), lineWidth: 2))
                                    .shadow(color: effectivePrimaryColor.opacity(0.50), radius: 30)
                                    .shadow(color: Color.black.opacity(0.80), radius: 20)
                                
                                Image(systemName: icon)
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundStyle(Color.white)
                                    .offset(x: icon == "play.fill" ? 3 : 0)
                            }
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                        
                        // 8. Keyboard Shortcuts Help Overlay Modal (? toggle)
                        if showShortcutsHelp {
                            VisualizerKeyboardHelpOverlay {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showShortcutsHelp = false
                                }
                            }
                            .transition(.opacity)
                        }
                        
                        // 9. Debug HUD Overlay (Cmd+D / D toggle)
                        if showDebugOverlay {
                            debugHUDView(geometry: geometry, currentPos: currentPos, lyricsPos: lyricsPos)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                        
                        // 10. Settings Popover
                        if showSettings {
                            settingsOverlay
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .onAppear {
                        updateCachedArtwork(data: nowPlaying.artworkData)
                        resetInactivityTimer(duration: 5.0)
                    }
                    .onChange(of: nowPlaying.artworkData) { _, newData in
                        updateCachedArtwork(data: newData)
                    }
                    .onChange(of: nowPlaying.id) { _, _ in
                        updateCachedArtwork(data: nowPlaying.artworkData)
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            NSCursor.unhide()
                            self.mousePoint = NSPoint(x: loc.x, y: loc.y)
                            if !showControls {
                                withAnimation(.easeOut(duration: 0.2)) { showControls = true }
                            }
                            resetInactivityTimer(duration: 4.0)
                        case .ended:
                            break
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumoToggleRomanized"))) { _ in
            showRomanized.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumoToggleDebugOverlay"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showDebugOverlay.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumoToggleHelpOverlay"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showShortcutsHelp.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumoFlashPlayPauseFeedback"))) { _ in
            flashPlayPauseFeedback()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumoVisualizerUserActivity"))) { notif in
            NSCursor.unhide()
            if let loc = notif.object as? NSPoint {
                self.mousePoint = loc
            }
            if !showControls {
                withAnimation(.easeOut(duration: 0.2)) {
                    showControls = true
                }
            }
            resetInactivityTimer(duration: 4.0)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumoVisualizerVisibilityChanged"))) { notif in
            if let active = notif.object as? Bool {
                self.isVisualizerActive = active
            }
        }
    }
    
    // MARK: - 1. Full Screen Background (1.6x Blurred Artwork with Slow Pan & Dark Scrim)
    
    @ViewBuilder
    private func fullScreenBackground(geometry: GeometryProxy, time: TimeInterval) -> some View {
        let panX = sin(time / 14.0) * (geometry.size.width * 0.035)
        let panY = cos(time / 18.0) * (geometry.size.height * 0.030)
        
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let blurred = cachedBlurredBackground {
                Image(nsImage: blurred)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width * 1.5, height: geometry.size.height * 1.5)
                    .offset(x: panX, y: panY)
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: Color.black.opacity(0.68), location: 0.0),
                                .init(color: Color.black.opacity(0.86), location: 0.65),
                                .init(color: Color.black.opacity(0.92), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(Color.black.opacity(0.42))
            } else if let image = cachedArtwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width * 1.5, height: geometry.size.height * 1.5)
                    .offset(x: panX, y: panY)
                    .overlay(Color.black.opacity(0.85))
            } else {
                LinearGradient(
                    colors: [
                        effectivePrimaryColor.opacity(0.20),
                        Color.black,
                        effectiveSecondaryColor.opacity(0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .clipped()
        .ignoresSafeArea()
    }
    
    // MARK: - 2. Main Apple Music-Style Two-Panel Stage
    
    @ViewBuilder
    private func mainTwoPanelStage(
        geometry: GeometryProxy,
        currentPos: TimeInterval,
        lyricsPos: TimeInterval,
        duration: TimeInterval,
        glitch: Float,
        time: TimeInterval
    ) -> some View {
        let isWide = geometry.size.width >= 850 && geometry.size.width > geometry.size.height
        let lines = parsedLyrics.lines
        let isSynced = parsedLyrics.isSynced
        let hasArtwork = (cachedArtwork != nil)
        let hasLyrics = !lines.isEmpty
        
        if !hasArtwork && !hasLyrics {
            // Case D: Neither cover art nor lyrics available
            // Center the generated cover and put the animation behind it and around it so the screen feels full
            CenteredPlaceholderVisualView(
                seed: placeholderSeed,
                time: time,
                isPlaying: nowPlaying.isPlaying,
                title: nowPlaying.title,
                artist: nowPlaying.artist,
                album: nowPlaying.album,
                onFindLyrics: {
                    nowPlaying.refetchLyrics(forceRemote: true)
                },
                upNextTrack: playbackState.queue.first,
                onPlayUpNext: {
                    playbackState.nextTrack()
                }
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
        } else if !hasLyrics {
            // Case B: Has cover art, but no lyrics
            // Left panel: cover + details; Right panel: animated placeholder visual
            if isWide {
                let leftWidth = geometry.size.width * 0.35
                let rightWidth = geometry.size.width * 0.55
                
                HStack(spacing: geometry.size.width * 0.04) {
                    VStack {
                        Spacer()
                        coverAndDetailsBlock(
                            width: leftWidth,
                            geometry: geometry,
                            currentPos: currentPos,
                            duration: duration,
                            glitch: glitch,
                            time: time
                        )
                        Spacer()
                    }
                    .frame(width: leftWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, geometry.size.width * 0.04)
                    
                    RightPanelPlaceholderVisualView(
                        seed: placeholderSeed,
                        time: time,
                        isPlaying: nowPlaying.isPlaying,
                        isUnsynced: false,
                        title: nowPlaying.title,
                        artist: nowPlaying.artist,
                        onFindLyrics: {
                            nowPlaying.refetchLyrics(forceRemote: true)
                        },
                        upNextTrack: playbackState.queue.first,
                        onPlayUpNext: {
                            playbackState.nextTrack()
                        }
                    )
                    .frame(width: rightWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.trailing, geometry.size.width * 0.02)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 36) {
                        coverAndDetailsBlock(
                            width: min(geometry.size.width * 0.85, 360),
                            geometry: geometry,
                            currentPos: currentPos,
                            duration: duration,
                            glitch: glitch,
                            time: time
                        )
                        .padding(.top, max(geometry.safeAreaInsets.top + 20, 60))
                        
                        RightPanelPlaceholderVisualView(
                            seed: placeholderSeed,
                            time: time,
                            isPlaying: nowPlaying.isPlaying,
                            isUnsynced: false,
                            title: nowPlaying.title,
                            artist: nowPlaying.artist,
                            onFindLyrics: {
                                nowPlaying.refetchLyrics(forceRemote: true)
                            },
                            upNextTrack: playbackState.queue.first,
                            onPlayUpNext: {
                                playbackState.nextTrack()
                            }
                        )
                        .frame(height: max(350, geometry.size.height * 0.50))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else if isWide {
            // Case A (cover + lyrics) or Case C (lyrics, no cover): Wide layout
            let leftWidth = geometry.size.width * 0.35
            let rightWidth = geometry.size.width * 0.55
            
            HStack(spacing: geometry.size.width * 0.04) {
                // LEFT PANEL (about 35% width, vertically centered)
                VStack {
                    Spacer()
                    coverAndDetailsBlock(
                        width: leftWidth,
                        geometry: geometry,
                        currentPos: currentPos,
                        duration: duration,
                        glitch: glitch,
                        time: time
                    )
                    Spacer()
                }
                .frame(width: leftWidth)
                .frame(maxHeight: .infinity)
                .padding(.leading, geometry.size.width * 0.04)
                
                // RIGHT PANEL (about 55% width, full height)
                lyricColumnPanel(
                    width: rightWidth,
                    geometry: geometry,
                    currentPos: currentPos,
                    lyricsPos: lyricsPos,
                    duration: duration,
                    lines: lines,
                    isSynced: isSynced
                )
                .frame(width: rightWidth)
                .frame(maxHeight: .infinity)
                .padding(.trailing, geometry.size.width * 0.02)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        } else {
            // Narrow or Portrait Viewport: vertically stacked
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 36) {
                    coverAndDetailsBlock(
                        width: min(geometry.size.width * 0.85, 360),
                        geometry: geometry,
                        currentPos: currentPos,
                        duration: duration,
                        glitch: glitch,
                        time: time
                    )
                    .padding(.top, max(geometry.safeAreaInsets.top + 20, 60))
                    
                    lyricColumnPanel(
                        width: geometry.size.width * 0.90,
                        geometry: geometry,
                        currentPos: currentPos,
                        lyricsPos: lyricsPos,
                        duration: duration,
                        lines: lines,
                        isSynced: isSynced
                    )
                    .frame(height: max(350, geometry.size.height * 0.60))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Left Panel: Cover Artwork + Scrubber + Marquee Title & Artist
    
    @ViewBuilder
    private func coverAndDetailsBlock(
        width: CGFloat,
        geometry: GeometryProxy,
        currentPos: TimeInterval,
        duration: TimeInterval,
        glitch: Float,
        time: TimeInterval
    ) -> some View {
        let artCornerRadius = min(geometry.size.width * 0.025, 24)
        let artSize = min(width * 0.95, geometry.size.height * 0.38)
        
        VStack(alignment: .leading, spacing: 20) {
            // Square Artwork or Generated Monogram Cover
            ZStack {
                if let image = cachedArtwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: artSize, height: artSize)
                        .clipShape(RoundedRectangle(cornerRadius: artCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: artCornerRadius)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1.0)
                        )
                        .shadow(color: effectivePrimaryColor.opacity(0.40), radius: 36, x: 0, y: 14)
                        .shadow(color: .black.opacity(0.85), radius: 24, x: 0, y: 10)
                        .scaleEffect(1.0 + CGFloat(glitch * 0.015)) // Subtle strong-beat accent
                } else {
                    GeneratedCoverArtView(
                        seed: placeholderSeed,
                        size: artSize,
                        cornerRadius: artCornerRadius,
                        isPlaying: nowPlaying.isPlaying,
                        time: time
                    )
                }
            }
            .frame(width: artSize, height: artSize)
            
            // Scrubber Progress Bar (White on Translucent Track with Elapsed / Total Time)
            VisualizerProgressBar(
                currentTime: currentPos,
                duration: duration,
                themeColor: effectivePrimaryColor,
                onSeek: { newTime in
                    PlaybackState.shared.seek(to: newTime)
                }
            )
            .frame(width: artSize)
            
            // Song Title and Artist with Smooth Marquee Overflow Scroll
            VStack(alignment: .leading, spacing: 6) {
                // Title (Bold, Large)
                MarqueeText(
                    text: nowPlaying.title.isEmpty ? "Lumo" : nowPlaying.title,
                    font: .system(size: max(22, geometry.size.height * 0.026), weight: .bold),
                    color: .white
                )
                .frame(width: artSize, height: max(28, geometry.size.height * 0.032))
                
                // Artist (Smaller, 60% Opacity)
                MarqueeText(
                    text: nowPlaying.artist.isEmpty ? "Unknown Artist" : nowPlaying.artist,
                    font: .system(size: max(15, geometry.size.height * 0.018), weight: .medium),
                    color: .white,
                    opacity: 0.60
                )
                .frame(width: artSize, height: max(22, geometry.size.height * 0.024))
                
                // Album or Year (if present)
                if !nowPlaying.album.isEmpty {
                    Text(nowPlaying.album)
                        .font(.system(size: max(13, geometry.size.height * 0.015), weight: .regular))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                        .frame(width: artSize, alignment: .leading)
                }
            }
            .frame(width: artSize)
        }
        .frame(width: width, alignment: .leading)
    }
    
    // MARK: - Right Panel: Vertically Scrolling Lyrics Column
    
    @ViewBuilder
    private func lyricColumnPanel(
        width: CGFloat,
        geometry: GeometryProxy,
        currentPos: TimeInterval,
        lyricsPos: TimeInterval,
        duration: TimeInterval,
        lines: [LyricLine],
        isSynced: Bool
    ) -> some View {
        let currIdx: Int = isSynced ? parsedLyrics.lineIndex(at: lyricsPos) : {
            let progress = duration > 0 ? (currentPos / duration) : 0
            return min(lines.count - 1, max(0, Int(progress * Double(lines.count))))
        }()
        
        let lyricFontSize = max(34.0, geometry.size.height * 0.046) // Current line >= 4.5% screen height
        
        ZStack(alignment: .topLeading) {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        // Top spacing so current line auto-scrolls to ~38% panel height
                        Color.clear.frame(height: geometry.size.height * 0.38)
                        
                        // Status badge for unsynced plain lyrics
                        if !isSynced {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .font(.system(size: 13))
                                Text("Lyrics not synced")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.70))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .padding(.leading, 16)
                            .padding(.bottom, 10)
                        }
                        
                        // Vertical column of ALL lyric lines
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            let isCurrent = (index == currIdx)
                            let distance = abs(index - currIdx)
                            
                            LyricLineRowView(
                                line: line,
                                index: index,
                                isCurrent: isCurrent,
                                distance: distance,
                                fontSize: lyricFontSize,
                                themeColor: effectivePrimaryColor,
                                showRomanized: showRomanized,
                                onSeek: {
                                    if isSynced {
                                        PlaybackState.shared.seek(to: line.time)
                                    }
                                }
                            )
                            .id(index)
                        }
                        
                        // Bottom spacing so final lines can reach the ~38% height line
                        Color.clear.frame(height: geometry.size.height * 0.55)
                    }
                }
                .mask(
                    // Soft fade masks on top and bottom edges of the lyrics column
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.12),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { _ in
                            handleUserManualScroll(scrollProxy: scrollProxy, targetIndex: currIdx)
                        }
                )
                .onChange(of: currIdx) { _, newIndex in
                    guard !isUserScrolling, newIndex >= 0, newIndex < lines.count else { return }
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) {
                        scrollProxy.scrollTo(newIndex, anchor: UnitPoint(x: 0, y: 0.38))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func handleUserManualScroll(scrollProxy: ScrollViewProxy, targetIndex: Int) {
        isUserScrolling = true
        userScrollResumeTask?.cancel()
        userScrollResumeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds pause after user scroll
            isUserScrolling = false
            if targetIndex >= 0 && targetIndex < parsedLyrics.lines.count {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) {
                    scrollProxy.scrollTo(targetIndex, anchor: UnitPoint(x: 0, y: 0.38))
                }
            }
        }
    }
    
    // MARK: - 3. GPU Core Animation Glowing Border (Perimeter & Notch Contour)
    
    @ViewBuilder
    private func neonEdgeGlow(geometry: GeometryProxy, glitch: Float) -> some View {
        if gradientMode != "none" {
            let notchShape = NeonBorderShape.forScreen(NSScreen.main ?? NSScreen.screens.first)
            
            CAGlowingBorderView(
                primaryColor: effectivePrimaryNSColor,
                secondaryColor: effectiveSecondaryNSColor,
                notchShape: notchShape,
                glowIntensity: CGFloat(glowIntensity),
                beatPulse: CGFloat(glitch)
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
    
    // MARK: - 4. Fail-Safe Top Click Interceptor (Top 60px closes visualizer)
    
    @ViewBuilder
    private func topClickInterceptor(geometry: GeometryProxy) -> some View {
        VStack {
            Color.clear
                .frame(height: 60)
                .contentShape(Rectangle())
                .onTapGesture {
                    VisualizerWindowController.shared.closeFullScreen()
                }
            Spacer()
        }
    }
    
    // MARK: - 5. Top Exit Button (Solid high-contrast white button, >= 48pt tall, 16pt font, clear of border glow)
    
    @ViewBuilder
    private func topExitButton(geometry: GeometryProxy) -> some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    VisualizerWindowController.shared.closeFullScreen()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                        Text("Exit")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 22)
                    .frame(minWidth: 48, minHeight: 48)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.60), radius: 12, x: 0, y: 4)
                            .shadow(color: effectivePrimaryColor.opacity(0.35), radius: 16)
                    )
                    .scaleEffect(isHoveringExit ? 1.05 : 1.0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exit full screen")
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isHoveringExit = hovering
                    }
                }
                .padding(.top, max(geometry.safeAreaInsets.top + 20, 56)) // Safely below MacBook notch
                .padding(.trailing, 42) // Clear of border glow
            }
            Spacer()
        }
    }
    
    // MARK: - 6. Debug HUD Overlay (Cmd+D / D)
    
    @ViewBuilder
    private func debugHUDView(geometry: GeometryProxy, currentPos: TimeInterval, lyricsPos: TimeInterval) -> some View {
        let lines = parsedLyrics.lines
        let isSynced = parsedLyrics.isSynced
        let lineIdx = parsedLyrics.lineIndex(at: lyricsPos)
        
        let lineSpan: String = {
            if lineIdx >= 0 && lineIdx < lines.count {
                let start = lines[lineIdx].time
                let end = (lineIdx + 1 < lines.count) ? lines[lineIdx + 1].time : (start + 6.0)
                return String(format: "%.2fs - %.2fs", start, end)
            }
            return "N/A"
        }()
        
        let userOffsetMs = Int((nowPlaying.userLyricsOffset * 1000).rounded())
        let totalOffsetMs = Int((nowPlaying.totalLyricsOffset * 1000).rounded())
        
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("LUMO DEBUG OVERLAY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.yellow)
                        Spacer()
                        Text("Cmd+D to close")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Divider().background(Color.white.opacity(0.2))
                    
                    HStack {
                        Text("Playback Time:")
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(String(format: "%.2fs (%02d:%05.2f)", currentPos, Int(currentPos) / 60, currentPos.truncatingRemainder(dividingBy: 60)))
                            .bold()
                            .foregroundStyle(.white)
                    }
                    
                    HStack {
                        Text("Lyrics Clock:")
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(String(format: "%.2fs", lyricsPos))
                            .bold()
                            .foregroundStyle(.white)
                    }
                    
                    HStack {
                        Text("Line Index:")
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(lineIdx >= 0 ? "\(lineIdx + 1) / \(lines.count)" : "None (-1)")
                            .bold()
                            .foregroundStyle(lineIdx >= 0 ? .green : .orange)
                    }
                    
                    HStack {
                        Text("Line Span:")
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(lineSpan)
                            .bold()
                            .foregroundStyle(.white)
                    }
                    
                    HStack {
                        Text("Offset ([ / ]):")
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text("\(totalOffsetMs)ms (Track: \(userOffsetMs)ms)")
                            .bold()
                            .foregroundStyle(.cyan)
                    }
                    
                    HStack {
                        Text("Lyric Source:")
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(nowPlaying.lyricsSource ?? "Unknown")
                            .bold()
                            .foregroundStyle(.white)
                    }
                    
                    HStack {
                        Text("Synced LRC:")
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(isSynced ? "YES" : "NO")
                            .bold()
                            .foregroundStyle(isSynced ? .green : .orange)
                    }
                    
                    HStack {
                        Text("Render Mode:")
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text("Apple Music Layout (30 FPS)")
                            .bold()
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(14)
                .frame(width: 340)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.90))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.8), radius: 12)
                .padding(.top, max(geometry.safeAreaInsets.top + 14, 52))
                .padding(.leading, 32)
                
                Spacer()
            }
            Spacer()
        }
    }
    
    // MARK: - 7. Bottom Floating Controls Bar
    
    private var bottomControlsBar: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 16) {
                // Previous Track
                Button { nowPlaying.previousTrack() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("Previous Track")
                
                // Play / Pause
                Button { nowPlaying.togglePlayPause() } label: {
                    Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)
                .help("Play / Pause")
                
                // Next Track
                Button { nowPlaying.nextTrack() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("Next Track")
                
                Divider()
                    .frame(height: 18)
                    .opacity(0.3)
                
                // Lyrics Offset ± (keys [ and ])
                HStack(spacing: 5) {
                    Button {
                        nowPlaying.setUserLyricsOffset(nowPlaying.userLyricsOffset - 0.1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Lyrics 100ms earlier (Key: [)")
                    
                    let offsetMs = Int((nowPlaying.totalLyricsOffset * 1000).rounded())
                    Text("\(offsetMs >= 0 ? "+" : "")\(offsetMs)ms")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(minWidth: 48)
                    
                    Button {
                        nowPlaying.setUserLyricsOffset(nowPlaying.userLyricsOffset + 0.1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Lyrics 100ms later (Key: ])")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                
                // Transliteration Script Toggle (Aa)
                if hasNonLatinLyrics {
                    Button {
                        showRomanized.toggle()
                    } label: {
                        Text("Aa")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(showRomanized ? effectivePrimaryColor : .white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Romanized Lyrics")
                }
                
                // Debug HUD Toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDebugOverlay.toggle()
                    }
                } label: {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(showDebugOverlay ? .yellow : .white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Toggle Debug Overlay (Cmd+D)")
                
                // Settings Toggle
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showSettings.toggle()
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(showSettings ? effectivePrimaryColor : .white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Visualizer Settings")
                
                // Close Full Screen
                Button {
                    VisualizerWindowController.shared.closeFullScreen()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("Exit Full Screen (Esc)")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.88))
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 20, y: 10)
            )
            .padding(.bottom, 28)
        }
    }
    
    // MARK: - 8. Settings Popover Overlay
    
    private var settingsOverlay: some View {
        HStack {
            Spacer()
            VStack {
                SettingsPopoverView {
                    withAnimation(.spring(response: 0.3)) {
                        showSettings = false
                    }
                }
                .padding(.trailing, 24)
                .padding(.top, 44)
                Spacer()
            }
        }
    }
    
    // MARK: - Beat Dynamics (Pure Functional, Zero State Redraw Cost)
    
    private func computeBeat(time: TimeInterval) -> (Float, Float) {
        let spectrum = visualizer.spectrumData
        let realBass = Float(spectrum.prefix(4).reduce(0, +) / 4.0)
        
        var effectiveBass = realBass
        if effectiveBass < 0.05 && nowPlaying.isPlaying {
            let tempoBps = 2.1
            let phase = Float((time * tempoBps).truncatingRemainder(dividingBy: 1.0))
            let beatSpike = exp(-phase * 5.5)
            effectiveBass = max(effectiveBass, beatSpike * 0.72)
        }
        
        let ambientShimmer = Float(sin(time * 2.2) * 0.03 + 0.03)
        effectiveBass = max(effectiveBass, ambientShimmer)
        
        let beatWave = sin(time * 3.5)
        let spike = effectiveBass > 0.35 ? effectiveBass * 1.2 : effectiveBass * 0.4
        let glitch = min(1.0, max(0.0, spike + Float(max(0, beatWave) * 0.15)))
        
        return (effectiveBass, glitch)
    }
    
    // MARK: - Lyrics Resolution
    
    private var parsedLyrics: ParsedLyrics {
        guard let text = nowPlaying.lyricsText, !text.isEmpty else {
            return ParsedLyrics(lines: [], isSynced: false)
        }
        return LyricsParser.parse(text, duration: nowPlaying.duration)
    }
    
    private var hasNonLatinLyrics: Bool {
        guard let text = nowPlaying.lyricsText, !text.isEmpty else { return false }
        return Romanizer.detectScript(in: text) != nil
    }
    
    // MARK: - Palette Colors & ImageIO Caching
    
    private var effectivePrimaryColor: Color {
        if overrideColor {
            return Color(hex: primaryColorHex)
        }
        if nowPlaying.artworkData == nil {
            return placeholderSeed.colors[0]
        }
        return cachedPalette.0
    }
    
    private var effectiveSecondaryColor: Color {
        if overrideColor {
            return Color(hex: secondaryColorHex)
        }
        if nowPlaying.artworkData == nil {
            return placeholderSeed.colors[1]
        }
        return cachedPalette.1
    }
    
    private var effectivePrimaryNSColor: NSColor {
        if overrideColor {
            return NSColor(Color(hex: primaryColorHex))
        }
        if nowPlaying.artworkData == nil {
            return placeholderSeed.nsColors[0]
        }
        return cachedPalette.2
    }
    
    private var effectiveSecondaryNSColor: NSColor {
        if overrideColor {
            return NSColor(Color(hex: secondaryColorHex))
        }
        if nowPlaying.artworkData == nil {
            return placeholderSeed.nsColors[1]
        }
        return cachedPalette.3
    }
    
    private func updateCachedArtwork(data: Data?) {
        guard let data = data else {
            let nsc1 = LumoTheme.nsAccentPink
            let nsc2 = LumoTheme.nsAccentViolet
            cachedArtwork = nil
            cachedBlurredBackground = nil
            cachedPalette = (Color(nsc1), Color(nsc2), nsc1, nsc2)
            lastProcessedArtworkData = nil
            return
        }
        if data == lastProcessedArtworkData && cachedArtwork != nil {
            return
        }
        lastProcessedArtworkData = data
        
        // Downsample artwork directly at decode time (ImageIO, max 1024px)
        let downsampled = downsampleArtwork(data: data, maxDimension: 1024)
        cachedArtwork = downsampled
        
        // Pre-render blurred background aura once (zero per-frame blur cost)
        let thumbForBlur = downsampleArtwork(data: data, maxDimension: 256)
        cachedBlurredBackground = generateBlurredBackground(from: thumbForBlur ?? downsampled)
        
        if let img = downsampled {
            cachedPalette = extractPaletteColors(from: img)
        }
    }
    
    private func generateBlurredBackground(from image: NSImage?) -> NSImage? {
        guard let image = image,
              let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else { return nil }
        
        let blurFilter = CIFilter(name: "CIGaussianBlur")
        blurFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter?.setValue(36.0, forKey: kCIInputRadiusKey)
        guard let output = blurFilter?.outputImage else { return nil }
        
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let rect = CGRect(origin: .zero, size: image.size)
        guard let cgImg = context.createCGImage(output, from: rect) else { return nil }
        return NSImage(cgImage: cgImg, size: image.size)
    }
    
    private func downsampleArtwork(data: Data, maxDimension: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return NSImage(data: data)
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    private func extractPaletteColors(from image: NSImage) -> (Color, Color, NSColor, NSColor) {
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let provider = cg.dataProvider,
              let pixelData = provider.data,
              let raw = CFDataGetBytePtr(pixelData) else {
            let nsc1 = NSColor(red: 1.0, green: 0.0, blue: 0.5, alpha: 1.0)
            let nsc2 = NSColor(red: 0.48, green: 0.0, blue: 1.0, alpha: 1.0)
            return (Color(nsc1), Color(nsc2), nsc1, nsc2)
        }
        
        let width = cg.width
        let height = cg.height
        let bpp = cg.bitsPerPixel / 8
        let bpr = cg.bytesPerRow
        guard width > 0, height > 0 else {
            let nsc1 = NSColor(red: 1.0, green: 0.0, blue: 0.5, alpha: 1.0)
            let nsc2 = NSColor(red: 0.48, green: 0.0, blue: 1.0, alpha: 1.0)
            return (Color(nsc1), Color(nsc2), nsc1, nsc2)
        }
        
        let p1 = (width / 3, height / 3)
        let p2 = (2 * width / 3, 2 * height / 3)
        let o1 = p1.1 * bpr + p1.0 * bpp
        let o2 = p2.1 * bpr + p2.0 * bpp
        let total = CFDataGetLength(pixelData)
        
        var nsc1 = NSColor(red: 1.0, green: 0.0, blue: 0.5, alpha: 1.0)
        var nsc2 = NSColor(red: 0.48, green: 0.0, blue: 1.0, alpha: 1.0)
        
        if o1 + 2 < total {
            let r = CGFloat(raw[o1]) / 255.0
            let g = CGFloat(raw[o1 + 1]) / 255.0
            let b = CGFloat(raw[o1 + 2]) / 255.0
            nsc1 = makeVivid(color: NSColor(red: r, green: g, blue: b, alpha: 1.0))
        }
        if o2 + 2 < total {
            let r = CGFloat(raw[o2]) / 255.0
            let g = CGFloat(raw[o2 + 1]) / 255.0
            let b = CGFloat(raw[o2 + 2]) / 255.0
            nsc2 = makeVivid(color: NSColor(red: r, green: g, blue: b, alpha: 1.0))
        }
        
        return (Color(nsc1), Color(nsc2), nsc1, nsc2)
    }
    
    private func makeVivid(color: NSColor) -> NSColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let rgbColor = color.usingColorSpace(.sRGB) ?? color
        rgbColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        
        // For dull or dark covers, guarantee vibrant neon saturation and brightness
        let vividS = max(s, 0.72)
        let vividB = max(b, 0.88)
        return NSColor(hue: h, saturation: vividS, brightness: vividB, alpha: 1.0)
    }
    
    private func resetInactivityTimer(duration: TimeInterval = 4.0) {
        hideControlsTask?.cancel()
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled { return }
            
            // Wait while hovered, dragged, or in edge zones
            while isHoveringControls || isHoveringExit || isDraggingSlider || isMouseInHotZone {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
            }
            
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = false
            }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }
    
    private var isMouseInHotZone: Bool {
        guard let screen = NSScreen.main else { return false }
        let h = screen.frame.height
        guard h > 0 else { return false }
        let distFromEdge = min(mousePoint.y, h - mousePoint.y)
        return distFromEdge <= (h * 0.25)
    }
    
    private func flashPlayPauseFeedback() {
        flashFeedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            flashFeedbackIcon = nowPlaying.isPlaying ? "pause.fill" : "play.fill"
        }
        flashFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.2)) {
                flashFeedbackIcon = nil
            }
        }
    }
}

// MARK: - Interactive Progress Bar with Click-to-Seek

struct VisualizerProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let themeColor: Color
    let onSeek: (TimeInterval) -> Void
    
    @State private var isDragging: Bool = false
    @State private var dragPosition: Double = 0
    
    private var progress: Double {
        guard duration > 0 else { return 0 }
        if isDragging { return dragPosition }
        return min(1.0, max(0.0, currentTime / duration))
    }
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let barWidth = geo.size.width
                ZStack(alignment: .leading) {
                    // Translucent background track
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 5)
                    
                    // White + theme tinted progress bar
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white, themeColor.opacity(0.95)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, barWidth * CGFloat(progress)), height: 5)
                        .shadow(color: themeColor.opacity(0.55), radius: 6)
                }
                .contentShape(Rectangle().inset(by: -8))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let clampedX = min(barWidth, max(0, value.location.x))
                            dragPosition = Double(clampedX / barWidth)
                        }
                        .onEnded { value in
                            let clampedX = min(barWidth, max(0, value.location.x))
                            let finalPos = Double(clampedX / barWidth) * duration
                            isDragging = false
                            onSeek(finalPos)
                        }
                )
            }
            .frame(height: 12)
            
            HStack {
                Text(formatDuration(isDragging ? (dragPosition * duration) : currentTime))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(formatDuration(duration))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.60))
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

// MARK: - Lightweight Equatable Lyric Row View

@MainActor
struct LyricLineRowView: View {
    let line: LyricLine
    let index: Int
    let isCurrent: Bool
    let distance: Int
    let fontSize: CGFloat
    let themeColor: Color
    let showRomanized: Bool
    let onSeek: () -> Void
}

extension LyricLineRowView: @preconcurrency Equatable {
    static func == (lhs: LyricLineRowView, rhs: LyricLineRowView) -> Bool {
        return lhs.line.id == rhs.line.id &&
               lhs.line.text == rhs.line.text &&
               lhs.isCurrent == rhs.isCurrent &&
               lhs.distance == rhs.distance &&
               lhs.fontSize == rhs.fontSize &&
               lhs.showRomanized == rhs.showRomanized
    }
}

extension LyricLineRowView {
    
    private var lineOpacity: Double {
        if isCurrent { return 1.0 }
        let factor = min(1.0, Double(distance) / 4.0)
        return max(0.25, 0.60 - (factor * 0.35))
    }
    
    private var lineBlur: CGFloat {
        if isCurrent { return 0 }
        return min(6.0, CGFloat(distance) * 1.5)
    }
    
    var body: some View {
        Button(action: onSeek) {
            VStack(alignment: .leading, spacing: 6) {
                if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Apple Music-style musical interlude indicator
                    HStack(spacing: 8) {
                        Circle().fill(Color.white.opacity(isCurrent ? 0.90 : 0.35)).frame(width: 8, height: 8)
                        Circle().fill(Color.white.opacity(isCurrent ? 0.90 : 0.35)).frame(width: 8, height: 8)
                        Circle().fill(Color.white.opacity(isCurrent ? 0.90 : 0.35)).frame(width: 8, height: 8)
                    }
                    .padding(.vertical, 4)
                } else {
                    // Main Lyric Line (Wrappable, large bold font)
                    formatLineText(line.text)
                        .font(.system(size: fontSize, weight: isCurrent ? .heavy : .bold))
                        .foregroundStyle(isCurrent ? .white : Color(white: 0.85).opacity(lineOpacity))
                        .multilineTextAlignment(.leading)
                        .blur(radius: lineBlur)
                    
                    // Non-Latin / Hindi Romanized Subtitle
                    if showRomanized && Romanizer.hasNonLatinScript(text: line.text) {
                        let romanized = Romanizer.romanize(text: line.text)
                        formatLineText(romanized)
                            .font(.system(size: fontSize * 0.58, weight: .semibold))
                            .foregroundStyle(isCurrent ? .white.opacity(0.95) : .white.opacity(0.42 * lineOpacity))
                            .multilineTextAlignment(.leading)
                            .blur(radius: lineBlur * 0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Group {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.12))
                            .shadow(color: themeColor.opacity(0.40), radius: 16)
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func formatLineText(_ raw: String) -> some View {
        if raw.contains("(") && raw.contains(")") {
            buildAdLibText(raw: raw)
        } else {
            Text(raw)
        }
    }
    
    private func buildAdLibText(raw: String) -> Text {
        var text = Text("")
        var currentChunk = ""
        var inParen = false
        
        for char in raw {
            if char == "(" {
                if !currentChunk.isEmpty {
                    text = text + Text(currentChunk)
                    currentChunk = ""
                }
                inParen = true
                currentChunk.append(char)
            } else if char == ")" {
                currentChunk.append(char)
                let adLibOpacity = isCurrent ? 0.60 : 0.40
                text = text + Text(currentChunk).foregroundColor(Color.white.opacity(adLibOpacity))
                currentChunk = ""
                inParen = false
            } else {
                currentChunk.append(char)
            }
        }
        if !currentChunk.isEmpty {
            if inParen {
                let adLibOpacity = isCurrent ? 0.60 : 0.40
                text = text + Text(currentChunk).foregroundColor(Color.white.opacity(adLibOpacity))
            } else {
                text = text + Text(currentChunk)
            }
        }
        return text
    }
}
