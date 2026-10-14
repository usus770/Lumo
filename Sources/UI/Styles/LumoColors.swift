import SwiftUI

/// Compatibility bridge and aliases pointing directly to `LumoTheme`.
/// Ensures legacy views and components immediately inherit the brand tokens.
public enum LumoColors {
    
    // MARK: - Brand Accents
    
    public static var accent: Color { LumoTheme.accentPink }
    public static var accentSecondary: Color { LumoTheme.accentViolet }
    public static var accentTertiary: Color { LumoTheme.accentAmber }
    
    // MARK: - Backgrounds & Surfaces
    
    public static var background: Color { LumoTheme.bg1 }
    public static var sidebarBackground: Color { LumoTheme.bg0 }
    public static var cardBackground: Color { LumoTheme.surface }
    public static var surfaceElevated: Color { LumoTheme.surfaceRaised }
    public static var nowPlayingBackground: Color { LumoTheme.surface }
    public static var stroke: Color { LumoTheme.stroke }
    
    // MARK: - Text
    
    public static var textPrimary: Color { LumoTheme.textPrimary }
    public static var textSecondary: Color { LumoTheme.textSecondary }
    public static var textTertiary: Color { LumoTheme.textTertiary }
    
    // MARK: - Semantic
    
    public static var favorite: Color { LumoTheme.accentPink }
    public static var playing: Color { LumoTheme.accentPink }
    public static var error: Color { Color(red: 1.0, green: 0.28, blue: 0.28) }
    public static var success: Color { Color(red: 0.25, green: 0.85, blue: 0.55) }
    
    // MARK: - Gradients
    
    public static var defaultGradient: LinearGradient { LumoTheme.brandGradient }
    public static var shimmerGradient: LinearGradient { LumoTheme.brandHorizontalGradient }
    public static var progressGradient: LinearGradient { LumoTheme.brandHorizontalGradient }
}
