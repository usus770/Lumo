import SwiftUI
import AppKit

/// Unified Design System & Brand Identity for Lumo.
/// All colors, typography, radii, spacing, and gradients are centralized here.
public enum LumoTheme {
    
    // MARK: - Surfaces & Backgrounds
    
    /// Deepest background color (#07040D).
    public static let bg0 = Color(red: 0.0275, green: 0.0157, blue: 0.0510) // #07040D
    
    /// Standard window background color (#0B0710).
    public static let bg1 = Color(red: 0.0431, green: 0.0275, blue: 0.0627) // #0B0710
    
    /// Card / base surface color (#150D22).
    public static let surface = Color(red: 0.0824, green: 0.0510, blue: 0.1333) // #150D22
    
    /// Elevated surface for popovers, active items, and elevated cards (#1E1330).
    public static let surfaceRaised = Color(red: 0.1176, green: 0.0745, blue: 0.1882) // #1E1330
    
    /// Translucent border stroke (white at 10% opacity).
    public static let stroke = Color.white.opacity(0.10)
    
    /// Slightly stronger stroke for active / focused borders.
    public static let strokeActive = Color.white.opacity(0.20)
    
    // MARK: - Typography Colors
    
    /// Primary high-contrast text (#FFFFFF, 100% white, > 19:1 contrast).
    public static let textPrimary = Color.white
    
    /// Secondary text (white at 65% opacity, > 8.5:1 contrast).
    public static let textSecondary = Color.white.opacity(0.65)
    
    /// Tertiary / metadata text (white at 40% opacity, > 4.5:1 contrast).
    public static let textTertiary = Color.white.opacity(0.40)
    
    // MARK: - Brand Accents
    
    /// Brand Accent Amber (#FFC857).
    public static let accentAmber = Color(red: 1.0, green: 0.7843, blue: 0.3412) // #FFC857
    
    /// Brand Accent Pink (#FF3D9A).
    public static let accentPink = Color(red: 1.0, green: 0.2392, blue: 0.6039) // #FF3D9A
    
    /// Brand Accent Violet (#7C5CFF).
    public static let accentViolet = Color(red: 0.4863, green: 0.3608, blue: 1.0) // #7C5CFF
    
    // MARK: - Gradients
    
    /// Diagonal Brand Gradient: amber -> pink -> violet (topLeading to bottomTrailing).
    public static let brandGradient = LinearGradient(
        colors: [accentAmber, accentPink, accentViolet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Horizontal Brand Gradient: amber -> pink -> violet (leading to trailing).
    public static let brandHorizontalGradient = LinearGradient(
        colors: [accentAmber, accentPink, accentViolet],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    /// Angular Brand Gradient for rotating rings and glowing perimeters.
    public static let brandAngularGradient = AngularGradient(
        colors: [accentAmber, accentPink, accentViolet, accentAmber],
        center: .center
    )
    
    // MARK: - Radii Scale
    
    public enum Radius {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 14
        public static let large: CGFloat = 22
    }
    
    // MARK: - Spacing Scale (4, 8, 12, 16, 24, 32)
    
    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let s: CGFloat = 12
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 32
    }
    
    // MARK: - Typography System
    
    public enum Typography {
        /// Large numbers and titles in player (rounded SF Pro).
        public static let playerTitle = Font.system(size: 22, weight: .bold, design: .rounded)
        public static let playerTime = Font.system(size: 11, weight: .semibold, design: .monospaced)
        public static let playerArtist = Font.system(size: 14, weight: .medium, design: .default)
        public static let playerAlbum = Font.system(size: 12, weight: .regular, design: .default)
        
        /// Large display titles (e.g. Hero headers, Visualizer kinetic display).
        public static let displayLarge = Font.system(size: 28, weight: .bold, design: .rounded)
        public static let displayMedium = Font.system(size: 24, weight: .bold, design: .rounded)
        public static let title = displayMedium
        
        /// Headings.
        public static let headingLarge = Font.system(size: 20, weight: .semibold, design: .rounded)
        public static let headingMedium = Font.system(size: 16, weight: .semibold, design: .default)
        public static let headingSmall = Font.system(size: 14, weight: .semibold, design: .default)
        
        /// Body text.
        public static let bodyLarge = Font.system(size: 14, weight: .regular, design: .default)
        public static let bodyMedium = Font.system(size: 13, weight: .regular, design: .default)
        public static let bodySmall = Font.system(size: 12, weight: .regular, design: .default)
        public static let body = bodyMedium
        
        /// Metadata & captions.
        public static let caption = Font.system(size: 11, weight: .regular, design: .default)
        public static let micro = Font.system(size: 10, weight: .medium, design: .default)
        public static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
    }
    
    // MARK: - AppKit (NSColor) Equivalents
    
    public static let nsBg0 = NSColor(red: 0.0275, green: 0.0157, blue: 0.0510, alpha: 1.0)
    public static let nsBg1 = NSColor(red: 0.0431, green: 0.0275, blue: 0.0627, alpha: 1.0)
    public static let nsSurface = NSColor(red: 0.0824, green: 0.0510, blue: 0.1333, alpha: 1.0)
    public static let nsSurfaceRaised = NSColor(red: 0.1176, green: 0.0745, blue: 0.1882, alpha: 1.0)
    public static let nsStroke = NSColor(white: 1.0, alpha: 0.10)
    
    public static let nsAccentAmber = NSColor(red: 1.0, green: 0.7843, blue: 0.3412, alpha: 1.0)
    public static let nsAccentPink = NSColor(red: 1.0, green: 0.2392, blue: 0.6039, alpha: 1.0)
    public static let nsAccentViolet = NSColor(red: 0.4863, green: 0.3608, blue: 1.0, alpha: 1.0)
}
