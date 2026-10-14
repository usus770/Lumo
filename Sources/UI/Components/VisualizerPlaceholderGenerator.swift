import SwiftUI
import AppKit

// MARK: - Deterministic Seed & Color Generator

struct PlaceholderSeed: Sendable {
    let hashValue: UInt64
    let colors: [Color]
    let nsColors: [NSColor]
    let monogram: String
    let visualMode: Int // 0: Waveform, 1: Kinetic Typography, 2: Orbiting Particles
    
    init(title: String, artist: String) {
        let key = "\(title):\(artist)".trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 64-bit FNV-1a Hash
        var hash: UInt64 = 14695981039346656037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        self.hashValue = hash
        
        // Brand hues as one of the curated palettes
        if (hash % 3) == 0 {
            self.colors = [LumoTheme.accentPink, LumoTheme.accentViolet, LumoTheme.accentAmber, LumoTheme.surfaceRaised]
            self.nsColors = [LumoTheme.nsAccentPink, LumoTheme.nsAccentViolet]
        } else {
            // Deterministic, aesthetically pleasing hues
            let baseHue = Double(hash % 360) / 360.0
            let hue2 = (baseHue + 0.18).truncatingRemainder(dividingBy: 1.0)
            let hue3 = (baseHue + 0.42).truncatingRemainder(dividingBy: 1.0)
            let hue4 = (baseHue + 0.68).truncatingRemainder(dividingBy: 1.0)
            
            let saturation = 0.76 + Double((hash >> 8) % 12) / 100.0 // 0.76 - 0.88
            let brightness = 0.82 + Double((hash >> 16) % 10) / 100.0 // 0.82 - 0.92
            
            let c1 = Color(hue: baseHue, saturation: saturation, brightness: brightness)
            let c2 = Color(hue: hue2, saturation: saturation, brightness: brightness)
            let c3 = Color(hue: hue3, saturation: saturation, brightness: brightness)
            let c4 = Color(hue: hue4, saturation: saturation, brightness: brightness)
            self.colors = [c1, c2, c3, c4]
            
            let n1 = NSColor(hue: CGFloat(baseHue), saturation: CGFloat(saturation), brightness: CGFloat(brightness), alpha: 1.0)
            let n2 = NSColor(hue: CGFloat(hue2), saturation: CGFloat(saturation), brightness: CGFloat(brightness), alpha: 1.0)
            self.nsColors = [n1, n2]
        }
        
        // Monogram calculation: 1 or 2 uppercase display initials
        let words = title.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if words.count >= 2 {
            let first = words[0].prefix(1).uppercased()
            let second = words[1].prefix(1).uppercased()
            self.monogram = "\(first)\(second)"
        } else if let firstWord = words.first, !firstWord.isEmpty {
            self.monogram = String(firstWord.prefix(min(2, firstWord.count))).uppercased()
        } else {
            self.monogram = "♫"
        }
        
        self.visualMode = Int((hash >> 24) % 3)
    }
}

// MARK: - Generated Artwork View (No Cover Art Fallback)

struct GeneratedCoverArtView: View {
    let seed: PlaceholderSeed
    let size: CGFloat
    let cornerRadius: CGFloat
    let isPlaying: Bool
    let time: TimeInterval
    
    init(
        seed: PlaceholderSeed,
        size: CGFloat,
        cornerRadius: CGFloat,
        isPlaying: Bool,
        time: TimeInterval
    ) {
        self.seed = seed
        self.size = size
        self.cornerRadius = cornerRadius
        self.isPlaying = isPlaying
        self.time = time
    }
    
    private var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    
    var body: some View {
        let rotationDeg = shouldReduceMotion ? 0.0 : (time * 12.0).truncatingRemainder(dividingBy: 360.0)
        let blobShiftX = shouldReduceMotion ? 0.0 : sin(time * 0.6) * (size * 0.08)
        let blobShiftY = shouldReduceMotion ? 0.0 : cos(time * 0.8) * (size * 0.08)
        
        ZStack {
            // 1. Multi-gradient mesh background
            seed.colors[0]
            
            RadialGradient(
                colors: [seed.colors[1].opacity(0.85), Color.clear],
                center: UnitPoint(x: 0.2 + (blobShiftX / size), y: 0.25 + (blobShiftY / size)),
                startRadius: 10,
                endRadius: size * 0.8
            )
            
            RadialGradient(
                colors: [seed.colors[2].opacity(0.75), Color.clear],
                center: UnitPoint(x: 0.8 - (blobShiftX / size), y: 0.75 - (blobShiftY / size)),
                startRadius: 10,
                endRadius: size * 0.75
            )
            
            RadialGradient(
                colors: [seed.colors[3].opacity(0.65), Color.clear],
                center: .center,
                startRadius: size * 0.2,
                endRadius: size * 0.95
            )
            
            // 2. Vinyl grooves / Concentric rings
            ZStack {
                ForEach(1...5, id: \.self) { ring in
                    Circle()
                        .stroke(
                            Color.white.opacity(0.08 + Double(ring) * 0.025),
                            lineWidth: 1.0
                        )
                        .frame(width: size * (0.35 + CGFloat(ring) * 0.11), height: size * (0.35 + CGFloat(ring) * 0.11))
                }
            }
            .rotationEffect(.degrees(rotationDeg))
            
            // 3. Ambient vinyl center label with Monogram
            Circle()
                .fill(Color.black.opacity(0.35))
                .frame(width: size * 0.44, height: size * 0.44)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.20), lineWidth: 1.5)
                )
            
            Text(seed.monogram)
                .font(.system(size: size * 0.26, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.75), radius: 8, x: 0, y: 3)
            
            // 4. Subtle glass highlight
            LinearGradient(
                colors: [Color.white.opacity(0.25), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.20), lineWidth: 1.2)
        )
        .shadow(color: seed.colors[0].opacity(0.40), radius: 36, x: 0, y: 14)
        .shadow(color: .black.opacity(0.85), radius: 24, x: 0, y: 10)
    }
}

// MARK: - Right Panel Placeholder Visuals (No Lyrics / Unsynced Fallback)

struct RightPanelPlaceholderVisualView: View {
    let seed: PlaceholderSeed
    let time: TimeInterval
    let isPlaying: Bool
    let isUnsynced: Bool
    let title: String
    let artist: String
    let onFindLyrics: () -> Void
    let upNextTrack: TrackInfo?
    let onPlayUpNext: () -> Void
    
    private var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 28) {
                Spacer()
                
                // Visual choice driven deterministically by seed.visualMode
                Group {
                    switch seed.visualMode {
                    case 0:
                        waveformVisual(width: geo.size.width, height: min(240, geo.size.height * 0.35))
                    case 1:
                        kineticTypographyVisual(width: geo.size.width)
                    default:
                        orbitingParticlesVisual(size: min(280, geo.size.height * 0.40))
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Clear Status Pill + Find Lyrics Button
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: isUnsynced ? "music.note.list" : "waveform")
                            .font(.system(size: 13, weight: .semibold))
                        Text(isUnsynced ? "Lyrics not synced" : "Instrumental / No lyrics available")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.60))
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    )
                    
                    Button(action: onFindLyrics) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .bold))
                            Text("Find Lyrics")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(seed.colors[0].opacity(0.40))
                                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search or fetch online lyrics")
                }
                
                Spacer()
                
                // Up Next Card (if queue exists)
                if let next = upNextTrack {
                    upNextCard(next: next)
                        .padding(.bottom, 24)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
    
    // Mode 0: 48 Flowing Waveform / Equalizer Bars
    @ViewBuilder
    private func waveformVisual(width: CGFloat, height: CGFloat) -> some View {
        let barCount = 48
        let barWidth: CGFloat = max(3, (width * 0.75) / CGFloat(barCount * 2))
        
        HStack(alignment: .center, spacing: max(2, barWidth * 0.6)) {
            ForEach(0..<barCount, id: \.self) { i in
                let idx = Double(i)
                let phase = (time * 3.4) + (idx * 0.24)
                let wave1 = sin(phase) * 0.42
                let wave2 = cos(phase * 1.5 + idx * 0.32) * 0.32
                let noise = sin(idx * 17.0 + time * 1.8) * 0.18
                
                let rawAmp = isPlaying ? (0.35 + wave1 + wave2 + noise) : (0.10 + sin(time + idx * 0.12) * 0.04)
                let amp = shouldReduceMotion ? 0.35 : max(0.08, min(1.0, rawAmp))
                let barH = max(8, height * CGFloat(amp))
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [seed.colors[0], seed.colors[1]],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: barWidth, height: barH)
                    .shadow(color: seed.colors[0].opacity(0.35), radius: 6)
            }
        }
        .frame(height: height)
    }
    
    // Mode 1: Kinetic Typography (Huge Cropped Title + Artist Outline)
    @ViewBuilder
    private func kineticTypographyVisual(width: CGFloat) -> some View {
        let slideOffset = shouldReduceMotion ? 0.0 : sin(time * 0.35) * (width * 0.15)
        
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.85), seed.colors[0].opacity(0.90)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineLimit(1)
                .offset(x: slideOffset)
                .shadow(color: seed.colors[0].opacity(0.40), radius: 18)
            
            Text(artist)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(seed.colors[1].opacity(0.85))
                .lineLimit(1)
                .offset(x: -slideOffset * 0.6)
        }
        .frame(maxWidth: width)
        .clipped()
    }
    
    // Mode 2: Orbiting Ring Particles around Pulsing Center
    @ViewBuilder
    private func orbitingParticlesVisual(size: CGFloat) -> some View {
        let pulse = shouldReduceMotion ? 1.0 : (1.0 + sin(time * 2.8) * 0.08)
        let rot1 = shouldReduceMotion ? 0.0 : (time * 16.0).truncatingRemainder(dividingBy: 360.0)
        let rot2 = shouldReduceMotion ? 0.0 : (-time * 22.0).truncatingRemainder(dividingBy: 360.0)
        
        ZStack {
            // Center pulsing core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [seed.colors[0].opacity(0.9), seed.colors[1].opacity(0.2), Color.clear],
                        center: .center,
                        startRadius: 5,
                        endRadius: size * 0.28
                    )
                )
                .frame(width: size * 0.55 * CGFloat(pulse), height: size * 0.55 * CGFloat(pulse))
            
            // Orbit ring 1
            Ellipse()
                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                .frame(width: size * 0.85, height: size * 0.36)
                .rotationEffect(.degrees(rot1))
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .shadow(color: seed.colors[0], radius: 10)
                        .offset(x: size * 0.425)
                        .rotationEffect(.degrees(rot1))
                )
            
            // Orbit ring 2
            Ellipse()
                .stroke(Color.white.opacity(0.14), lineWidth: 1.5)
                .frame(width: size * 0.70, height: size * 0.55)
                .rotationEffect(.degrees(rot2))
                .overlay(
                    Circle()
                        .fill(seed.colors[2])
                        .frame(width: 8, height: 8)
                        .shadow(color: seed.colors[2], radius: 10)
                        .offset(x: size * 0.35)
                        .rotationEffect(.degrees(rot2))
                )
        }
        .frame(width: size, height: size)
    }
    
    // Up Next Card
    @ViewBuilder
    private func upNextCard(next: TrackInfo) -> some View {
        Button(action: onPlayUpNext) {
            HStack(spacing: 12) {
                // Miniature artwork
                if let data = next.artworkData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(seed.colors[1].opacity(0.4))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.8))
                        )
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 10))
                        Text("UP NEXT")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.60))
                    
                    Text(next.title.isEmpty ? "Unknown Title" : next.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(next.artist.isEmpty ? "Unknown Artist" : next.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.65))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.40), radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play up next: \(next.title) by \(next.artist)")
    }
}

// MARK: - Centered Placeholder Visual (Neither Cover Nor Lyrics Fallback)

struct CenteredPlaceholderVisualView: View {
    let seed: PlaceholderSeed
    let time: TimeInterval
    let isPlaying: Bool
    let title: String
    let artist: String
    let album: String
    let onFindLyrics: () -> Void
    let upNextTrack: TrackInfo?
    let onPlayUpNext: () -> Void
    
    private var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    
    init(
        seed: PlaceholderSeed,
        time: TimeInterval,
        isPlaying: Bool,
        title: String,
        artist: String,
        album: String,
        onFindLyrics: @escaping () -> Void,
        upNextTrack: TrackInfo?,
        onPlayUpNext: @escaping () -> Void
    ) {
        self.seed = seed
        self.time = time
        self.isPlaying = isPlaying
        self.title = title
        self.artist = artist
        self.album = album
        self.onFindLyrics = onFindLyrics
        self.upNextTrack = upNextTrack
        self.onPlayUpNext = onPlayUpNext
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background ambient visuals surrounding and behind the center
                Group {
                    switch seed.visualMode {
                    case 0:
                        waveformBackground(width: geo.size.width, height: min(320, geo.size.height * 0.45))
                    case 1:
                        kineticTypographyBackground(width: geo.size.width)
                    default:
                        orbitingParticlesBackground(size: min(geo.size.width * 0.75, min(geo.size.height * 0.75, 620)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.65)
                
                // Centered generated cover, titles, and status
                VStack(spacing: 20) {
                    Spacer()
                    
                    let artSize = min(geo.size.width * 0.32, min(geo.size.height * 0.36, 360))
                    let cornerRadius = min(geo.size.width * 0.025, 22)
                    
                    GeneratedCoverArtView(
                        seed: seed,
                        size: max(180, artSize),
                        cornerRadius: cornerRadius,
                        isPlaying: isPlaying,
                        time: time
                    )
                    
                    VStack(spacing: 6) {
                        Text(title.isEmpty ? "Lumo" : title)
                            .font(.system(size: max(22, geo.size.height * 0.028), weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        Text(artist.isEmpty ? "Unknown Artist" : artist)
                            .font(.system(size: max(15, geo.size.height * 0.018), weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                        
                        if !album.isEmpty {
                            Text(album)
                                .font(.system(size: max(13, geo.size.height * 0.015), weight: .regular))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: max(260, artSize * 1.2))
                    
                    // Clear status pill + Find lyrics button
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Instrumental / No lyrics available")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.65))
                                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        )
                        
                        Button(action: onFindLyrics) {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Find Lyrics")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(seed.colors[0].opacity(0.40))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Find lyrics")
                    }
                    
                    Spacer()
                    
                    if let next = upNextTrack {
                        upNextCard(next: next)
                            .padding(.bottom, 96) // Clear of bottom control bar
                    } else {
                        Spacer().frame(height: 72)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
    
    @ViewBuilder
    private func waveformBackground(width: CGFloat, height: CGFloat) -> some View {
        let barCount = 48
        let barWidth: CGFloat = max(4, (width * 0.85) / CGFloat(barCount * 2))
        
        HStack(alignment: .center, spacing: max(3, barWidth * 0.6)) {
            ForEach(0..<barCount, id: \.self) { i in
                let idx = Double(i)
                let phase = (time * 3.4) + (idx * 0.24)
                let wave1 = sin(phase) * 0.42
                let wave2 = cos(phase * 1.5 + idx * 0.32) * 0.32
                let noise = sin(idx * 17.0 + time * 1.8) * 0.18
                let rawAmp = isPlaying ? (0.35 + wave1 + wave2 + noise) : (0.10 + sin(time + idx * 0.12) * 0.04)
                let amp = shouldReduceMotion ? 0.35 : max(0.08, min(1.0, rawAmp))
                let barH = max(12, height * CGFloat(amp))
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [seed.colors[0].opacity(0.55), seed.colors[1].opacity(0.40)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: barWidth, height: barH)
                    .shadow(color: seed.colors[0].opacity(0.25), radius: 8)
            }
        }
        .frame(height: height)
    }
    
    @ViewBuilder
    private func kineticTypographyBackground(width: CGFloat) -> some View {
        let slideOffset = shouldReduceMotion ? 0.0 : sin(time * 0.28) * (width * 0.22)
        VStack(spacing: 16) {
            Text(title.uppercased())
                .font(.system(size: 96, weight: .black, design: .rounded))
                .foregroundStyle(seed.colors[0].opacity(0.18))
                .lineLimit(1)
                .offset(x: slideOffset)
            
            Text(artist.uppercased())
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(seed.colors[1].opacity(0.14))
                .lineLimit(1)
                .offset(x: -slideOffset * 0.8)
        }
        .frame(maxWidth: width)
        .clipped()
    }
    
    @ViewBuilder
    private func orbitingParticlesBackground(size: CGFloat) -> some View {
        let pulse = shouldReduceMotion ? 1.0 : (1.0 + sin(time * 2.2) * 0.08)
        let rot1 = shouldReduceMotion ? 0.0 : (time * 12.0).truncatingRemainder(dividingBy: 360.0)
        let rot2 = shouldReduceMotion ? 0.0 : (-time * 16.0).truncatingRemainder(dividingBy: 360.0)
        
        ZStack {
            Circle()
                .fill(seed.colors[0].opacity(0.12))
                .frame(width: size * 0.70 * CGFloat(pulse), height: size * 0.70 * CGFloat(pulse))
            
            Ellipse()
                .stroke(seed.colors[1].opacity(0.25), lineWidth: 2)
                .frame(width: size * 0.95, height: size * 0.45)
                .rotationEffect(.degrees(rot1))
            
            Ellipse()
                .stroke(seed.colors[2].opacity(0.20), lineWidth: 2)
                .frame(width: size * 0.80, height: size * 0.65)
                .rotationEffect(.degrees(rot2))
        }
        .frame(width: size, height: size)
    }
    
    @ViewBuilder
    private func upNextCard(next: TrackInfo) -> some View {
        Button(action: onPlayUpNext) {
            HStack(spacing: 12) {
                if let data = next.artworkData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(seed.colors[1].opacity(0.4))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.8))
                        )
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 10))
                        Text("UP NEXT")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.60))
                    
                    Text(next.title.isEmpty ? "Unknown Title" : next.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(next.artist.isEmpty ? "Unknown Artist" : next.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.65))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.40), radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play up next: \(next.title) by \(next.artist)")
    }
}

