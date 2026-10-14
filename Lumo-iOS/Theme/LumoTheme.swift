import SwiftUI

/// Unified Design System tokens for Lumo on iOS.
/// Matches the macOS Lumo palette: high-contrast, dark mode, rich neon gradients.
public enum LumoTheme {
    // MARK: - Colors
    public static let bg0 = Color(red: 0.027, green: 0.016, blue: 0.051)       // #07040D
    public static let bg1 = Color(red: 0.043, green: 0.027, blue: 0.063)       // #0B0710
    public static let surface = Color(red: 0.082, green: 0.051, blue: 0.133)   // #150D22
    public static let surfaceRaised = Color(red: 0.118, green: 0.075, blue: 0.188) // #1E1330
    public static let stroke = Color.white.opacity(0.10)
    
    // Brand Accents
    public static let accentAmber = Color(red: 1.0, green: 0.784, blue: 0.341) // #FFC857
    public static let accentPink = Color(red: 1.0, green: 0.239, blue: 0.604)  // #FF3D9A
    public static let accentViolet = Color(red: 0.486, green: 0.361, blue: 1.0) // #7C5CFF
    
    // Text Hierarchy
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.65)
    public static let textTertiary = Color.white.opacity(0.40)
    
    // Brand Gradient (Amber -> Pink -> Violet)
    public static let brandGradient = LinearGradient(
        colors: [accentAmber, accentPink, accentViolet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let pinkVioletGradient = LinearGradient(
        colors: [accentPink, accentViolet],
        startPoint: .leading,
        endPoint: .trailing
    )
}
