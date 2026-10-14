import SwiftUI

/// Typography system for Lumo using SF Pro (system font) with defined scales.
enum LumoFonts {
    
    // MARK: - Display
    
    /// Large display text for hero elements (album title in detail view).
    static let displayLarge = Font.system(size: 28, weight: .bold, design: .default)
    
    /// Medium display text.
    static let displayMedium = Font.system(size: 24, weight: .semibold, design: .default)
    
    // MARK: - Headings
    
    static let headingLarge = Font.system(size: 20, weight: .semibold, design: .default)
    static let headingMedium = Font.system(size: 17, weight: .semibold, design: .default)
    static let headingSmall = Font.system(size: 15, weight: .medium, design: .default)
    
    // MARK: - Body
    
    static let bodyLarge = Font.system(size: 14, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 13, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .default)
    
    // MARK: - Labels
    
    /// Monospaced font for timestamps and technical info.
    static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
    
    /// Caption text.
    static let caption = Font.system(size: 11, weight: .regular, design: .default)
    
    /// Tiny metadata labels.
    static let micro = Font.system(size: 10, weight: .medium, design: .default)
    
    // MARK: - Now Playing
    
    /// Track title in the now-playing bar.
    static let nowPlayingTitle = Font.system(size: 13, weight: .semibold, design: .default)
    
    /// Artist name in the now-playing bar.
    static let nowPlayingSubtitle = Font.system(size: 11, weight: .regular, design: .default)
    
    /// Large track title in the full player view.
    static let playerTitle = Font.system(size: 22, weight: .bold, design: .default)
    
    /// Artist in the full player view.
    static let playerArtist = Font.system(size: 16, weight: .medium, design: .default)
}
