import SwiftUI

// MARK: - Button Styles

/// Primary action button style with brand gradient background and responsive press animation.
public struct LumoPrimaryButtonStyle: ButtonStyle {
    public var cornerRadius: CGFloat = LumoTheme.Radius.small
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LumoFonts.bodyMedium.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, LumoTheme.Spacing.m)
            .padding(.vertical, LumoTheme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(LumoTheme.brandGradient)
                    .shadow(color: LumoTheme.accentPink.opacity(configuration.isPressed ? 0.2 : 0.4), radius: 6, y: 2)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Secondary button style: surfaceRaised with stroke.
public struct LumoSecondaryButtonStyle: ButtonStyle {
    public var cornerRadius: CGFloat = LumoTheme.Radius.small
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LumoFonts.bodyMedium)
            .foregroundStyle(LumoTheme.textPrimary)
            .padding(.horizontal, LumoTheme.Spacing.s)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(LumoTheme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(LumoTheme.stroke, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.65 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Transparent icon-only button for toolbars and controls.
public struct LumoIconButtonStyle: ButtonStyle {
    public var size: CGFloat = 28
    public var isActive: Bool = false
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? LumoTheme.accentPink : LumoTheme.textSecondary)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .background(
                Circle()
                    .fill(configuration.isPressed ? LumoTheme.surfaceRaised : (isActive ? LumoTheme.accentPink.opacity(0.12) : .clear))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Large circular play/pause button with brandGradient and playing state glow.
public struct LumoPlayButtonStyle: ButtonStyle {
    public var isPlaying: Bool = false
    public var size: CGFloat = 36
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(LumoTheme.brandGradient)
                    .shadow(
                        color: isPlaying ? LumoTheme.accentPink.opacity(0.65) : LumoTheme.accentViolet.opacity(0.3),
                        radius: isPlaying ? 10 : 4,
                        y: isPlaying ? 2 : 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Button Style Extensions

extension ButtonStyle where Self == LumoPrimaryButtonStyle {
    public static var lumoPrimary: LumoPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == LumoSecondaryButtonStyle {
    public static var lumoSecondary: LumoSecondaryButtonStyle { .init() }
}

extension ButtonStyle where Self == LumoPlayButtonStyle {
    public static var lumoPlay: LumoPlayButtonStyle { .init() }
    public static func lumoPlay(isPlaying: Bool, size: CGFloat = 36) -> LumoPlayButtonStyle {
        .init(isPlaying: isPlaying, size: size)
    }
}

// MARK: - View Modifiers

/// Card-style modifier with LumoTheme.surface background, rounded corners, and stroke.
public struct LumoCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = LumoTheme.Radius.medium
    public var padding: CGFloat = LumoTheme.Spacing.s
    
    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(LumoTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(LumoTheme.stroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            )
    }
}

/// Hover highlight modifier for list rows and interactive elements using surfaceRaised.
public struct LumoHoverModifier: ViewModifier {
    @State private var isHovered = false
    public var cornerRadius: CGFloat = LumoTheme.Radius.small
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? LumoTheme.surfaceRaised.opacity(0.7) : .clear)
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    public func lumoCard(cornerRadius: CGFloat = LumoTheme.Radius.medium, padding: CGFloat = LumoTheme.Spacing.s) -> some View {
        modifier(LumoCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
    
    public func lumoHover(cornerRadius: CGFloat = LumoTheme.Radius.small) -> some View {
        modifier(LumoHoverModifier(cornerRadius: cornerRadius))
    }
}
