import SwiftUI
import AppKit

/// Central asset loader and brand graphics components for Lumo.
public enum BrandAssets {
    
    /// Loads an NSImage searching Bundle.module, Bundle.main, Brand/, and Resources/Brand/.
    public static func loadImage(named name: String) -> NSImage? {
        // 1. Try Bundle.module (if synthesized)
        let candidates = [
            "Resources/Brand/\(name)",
            "Brand/\(name)",
            "\(name)"
        ]
        
        for cand in candidates {
            if let path = Bundle.main.path(forResource: cand, ofType: nil),
               let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        
        // 2. Direct filesystem fallback for development
        let cwd = FileManager.default.currentDirectoryPath
        let localPaths = [
            "\(cwd)/Brand/\(name)",
            "\(cwd)/Sources/Resources/Brand/\(name)"
        ]
        
        for path in localPaths {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        
        return NSImage(named: name)
    }
    
    /// Pre-loaded horizontal logo (mark + wordmark).
    public static var horizontalLogoImage: NSImage? {
        loadImage(named: "lumo-logo-horizontal.png")
    }
    
    /// Pre-loaded standalone mark.
    public static var markImage: NSImage? {
        loadImage(named: "lumo-mark.png")
    }
    
    /// 1024x1024 app icon.
    public static var appIconImage: NSImage? {
        loadImage(named: "lumo-app-icon-1024.png")
    }
    
    /// Menu bar template icon (18pt).
    public static var menuBarTemplateImage: NSImage? {
        if let img = loadImage(named: "lumo-mark-menubar@2x.png") ?? loadImage(named: "lumo-mark-menubar.png") {
            let template = img.copy() as! NSImage
            template.size = NSSize(width: 18, height: 18)
            template.isTemplate = true
            return template
        }
        // Fallback: create on the fly from lumo-mark.png
        if let mark = markImage {
            let template = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                mark.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
                return true
            }
            template.isTemplate = true
            return template
        }
        return nil
    }
}

// MARK: - Reusable Brand Views

/// Renders the horizontal Lumo logo (mark + wordmark).
public struct LumoHorizontalLogoView: View {
    public var height: CGFloat = 28
    
    public init(height: CGFloat = 28) {
        self.height = height
    }
    
    public var body: some View {
        if let img = BrandAssets.horizontalLogoImage {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
        } else {
            // Crisp Vector Fallback:
            HStack(spacing: 8) {
                LumoMarkView(size: height, isAnimated: false)
                Text("Lumo")
                    .font(.system(size: height * 0.82, weight: .bold, design: .rounded))
                    .foregroundStyle(LumoTheme.textPrimary)
            }
        }
    }
}

/// Standalone Lumo Mark view, optionally animating outward pulsing arcs for loading states.
public struct LumoMarkView: View {
    public var size: CGFloat = 48
    public var opacity: Double = 1.0
    public var isAnimated: Bool = false
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    
    public init(size: CGFloat = 48, opacity: Double = 1.0, isAnimated: Bool = false) {
        self.size = size
        self.opacity = opacity
        self.isAnimated = isAnimated
    }
    
    private var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    
    public var body: some View {
        ZStack {
            if let markImg = BrandAssets.markImage {
                Image(nsImage: markImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .opacity(opacity)
            } else {
                // Procedural mark fallback
                proceduralMark
            }
            
            // Pulsing arcs / aura when animated
            if isAnimated && !shouldReduceMotion {
                Circle()
                    .stroke(LumoTheme.brandGradient, lineWidth: max(2, size * 0.05))
                    .frame(width: size * 0.9 * pulseScale, height: size * 0.9 * pulseScale)
                    .opacity(pulseOpacity)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            if isAnimated && !shouldReduceMotion {
                withAnimation(
                    .easeInOut(duration: 1.1)
                    .repeatForever(autoreverses: true)
                ) {
                    pulseScale = 1.25
                    pulseOpacity = 0.15
                }
            }
        }
    }
    
    private var proceduralMark: some View {
        ZStack {
            // L Shape
            Path { path in
                let scale = size / 100.0
                path.move(to: CGPoint(x: 35 * scale, y: 20 * scale))
                path.addLine(to: CGPoint(x: 35 * scale, y: 75 * scale))
                path.addLine(to: CGPoint(x: 75 * scale, y: 75 * scale))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round, lineJoin: .round))
            
            // Spark dot
            Circle()
                .fill(LumoTheme.brandGradient)
                .frame(width: size * 0.22, height: size * 0.22)
                .position(x: size * 0.68, y: size * 0.38)
            
            // Arcs
            Circle()
                .trim(from: 0.85, to: 0.15)
                .stroke(LumoTheme.brandGradient, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
                .frame(width: size * 0.44, height: size * 0.44)
                .position(x: size * 0.68, y: size * 0.38)
        }
        .opacity(opacity)
    }
}

/// Small animated equalizer indicator for the currently playing song in song list rows.
public struct AnimatedEqualizerView: View {
    public var barCount: Int = 3
    public var height: CGFloat = 14
    public var isPlaying: Bool = true
    
    @State private var phase: Double = 0
    
    public init(barCount: Int = 3, height: CGFloat = 14, isPlaying: Bool = true) {
        self.barCount = barCount
        self.height = height
        self.isPlaying = isPlaying
    }
    
    private var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    
    public var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    let seed = Double(i) * 1.6
                    let factor = isPlaying && !shouldReduceMotion ? abs(sin(elapsed * 6.0 + seed)) : 0.4
                    let barHeight = max(3, height * CGFloat(factor))
                    
                    RoundedRectangle(cornerRadius: 1)
                        .fill(LumoTheme.brandGradient)
                        .frame(width: 2.5, height: barHeight)
                }
            }
            .frame(width: CGFloat(barCount) * 4.5, height: height, alignment: .bottom)
        }
    }
}
