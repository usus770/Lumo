import SwiftUI
import AppKit

/// Short, non-blocking splash screen on launch.
/// Displays the Lumo mark with arcs animating outward for < 1.2s, then fades into the main window.
/// Skippable on click or keypress, and respects Reduce Motion.
public struct SplashView: View {
    @Binding var isPresented: Bool
    
    @State private var markOpacity: Double = 0.0
    @State private var arcScale: CGFloat = 0.6
    @State private var arcOpacity: Double = 0.0
    @State private var glowOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    
    private var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    public var body: some View {
        ZStack {
            // Background
            LumoTheme.bg0
                .ignoresSafeArea()
            
            // Subtle ambient gradient background glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            LumoTheme.accentPink.opacity(0.18),
                            LumoTheme.accentViolet.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 240
                    )
                )
                .frame(width: 480, height: 480)
                .opacity(glowOpacity)
            
            VStack(spacing: 24) {
                ZStack {
                    // Outward expanding arc rings
                    if !shouldReduceMotion {
                        Circle()
                            .stroke(
                                LumoTheme.brandGradient,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [12, 10])
                            )
                            .frame(width: 140 * arcScale, height: 140 * arcScale)
                            .opacity(arcOpacity)
                        
                        Circle()
                            .stroke(
                                LumoTheme.brandGradient,
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                            )
                            .frame(width: 190 * arcScale, height: 190 * arcScale)
                            .opacity(arcOpacity * 0.6)
                    }
                    
                    // Center Mark
                    LumoMarkView(size: 96, opacity: 1.0, isAnimated: false)
                        .shadow(color: LumoTheme.accentPink.opacity(0.5), radius: 24, y: 4)
                        .scaleEffect(shouldReduceMotion ? 1.0 : (0.85 + arcScale * 0.15))
                }
                .opacity(markOpacity)
                
                VStack(spacing: 6) {
                    Text("Lumo")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LumoTheme.brandGradient
                        )
                    
                    Text("Universal Music & Visualizer")
                        .font(LumoTheme.Typography.caption)
                        .foregroundStyle(LumoTheme.textTertiary)
                }
                .opacity(textOpacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissSplash()
        }
        .onAppear {
            runAnimationSequence()
        }
    }
    
    private func dismissSplash() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
    
    private func runAnimationSequence() {
        if shouldReduceMotion {
            // Instant fade in and out for reduced motion
            markOpacity = 1.0
            textOpacity = 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                dismissSplash()
            }
            return
        }
        
        // 0.0s - 0.25s: Fade in mark
        withAnimation(.easeOut(duration: 0.25)) {
            markOpacity = 1.0
            glowOpacity = 1.0
        }
        
        // 0.1s - 0.75s: Arcs expand outward
        withAnimation(.easeOut(duration: 0.65).delay(0.05)) {
            arcScale = 1.25
            arcOpacity = 0.85
        }
        
        // 0.2s - 0.45s: Wordmark fades in
        withAnimation(.easeOut(duration: 0.3).delay(0.15)) {
            textOpacity = 1.0
        }
        
        // 0.85s - 1.05s: Smooth exit fade into main UI (total time ~1.05s < 1.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.easeInOut(duration: 0.25)) {
                arcOpacity = 0.0
                markOpacity = 0.0
                textOpacity = 0.0
                glowOpacity = 0.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isPresented = false
            }
        }
    }
}
