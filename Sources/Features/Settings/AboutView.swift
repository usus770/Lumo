import SwiftUI
import AppKit

/// Clean, branded About window for Lumo.
/// Displays logo, app name, version + build number from Info.plist,
/// "Made for personal use" line, with zero fake external links.
public struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            // App Icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [LumoTheme.accentPink.opacity(0.25), LumoTheme.accentViolet.opacity(0.1), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                
                if let appIcon = BrandAssets.appIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: LumoTheme.accentPink.opacity(0.35), radius: 12, y: 4)
                } else {
                    LumoMarkView(size: 80, opacity: 1.0, isAnimated: false)
                }
            }
            .padding(.top, 12)
            
            // Name & Version
            VStack(spacing: 6) {
                Text("Lumo")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(LumoTheme.textPrimary)
                
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(LumoTheme.Typography.caption)
                    .foregroundStyle(LumoTheme.textSecondary)
            }
            
            // Developer & Description Card
            VStack(spacing: 10) {
                Text("Universal lossless audio playback & reactive kinetic visualizer.")
                    .font(LumoTheme.Typography.caption)
                    .foregroundStyle(LumoTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                
                Divider()
                    .background(LumoTheme.stroke)
                
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(LumoTheme.accentPink)
                    Text("Created by")
                        .font(LumoTheme.Typography.caption)
                        .foregroundStyle(LumoTheme.textSecondary)
                    Text("Ujjwal Singh")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LumoTheme.textPrimary)
                }
                
                Link(destination: URL(string: "https://github.com/usus770")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .semibold))
                        Text("github.com/usus770")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(LumoTheme.accentPink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(LumoTheme.accentPink.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(LumoTheme.accentPink.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: LumoTheme.Radius.small)
                    .fill(LumoTheme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: LumoTheme.Radius.small)
                            .stroke(LumoTheme.stroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
            
            Divider()
                .padding(.horizontal, 24)
            
            // Footer
            HStack {
                Text("macOS Sonoma 14.0+")
                    .font(LumoTheme.Typography.caption)
                    .foregroundStyle(LumoTheme.textTertiary)
                
                Spacer()
                
                Text("© 2026 Ujjwal Singh")
                    .font(LumoTheme.Typography.caption)
                    .foregroundStyle(LumoTheme.textTertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .frame(width: 380, height: 430)
        .background(LumoTheme.bg0)
    }
}

/// Controller to present the About window as a standalone modal or key window.
@MainActor
public final class AboutWindowController: NSObject {
    public static let shared = AboutWindowController()
    
    private var window: NSWindow?
    
    private override init() {
        super.init()
    }
    
    public func showAboutWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "About Lumo"
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.backgroundColor = LumoTheme.nsBg0
        newWindow.titlebarAppearsTransparent = true
        newWindow.contentViewController = NSHostingController(rootView: AboutView())
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
