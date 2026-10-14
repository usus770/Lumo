import SwiftUI
import AppKit

/// 3-Screen Onboarding flow matching the brand design system:
/// 1) Add your music folder / import
/// 2) Auto-find covers and lyrics
/// 3) The visualizer and its shortcuts
/// Skippable at any step and stores `hasCompletedOnboarding` flag.
public struct OnboardingView: View {
    @State private var settings = SettingsStore.shared
    @State private var currentStep: Int = 0
    @State private var selectedFolderName: String? = nil
    @State private var isScanningFolder: Bool = false
    @State private var syncEnabled: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Bar
            HStack {
                LumoHorizontalLogoView(height: 20)
                
                Spacer()
                
                Button("Skip") {
                    finishOnboarding()
                }
                .font(LumoTheme.Typography.caption)
                .foregroundStyle(LumoTheme.textTertiary)
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            // Screen Content
            VStack {
                switch currentStep {
                case 0:
                    screenOneMusicFolder
                case 1:
                    screenTwoCoversLyrics
                default:
                    screenThreeVisualizer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)
            
            // Bottom Controls & Indicator
            VStack(spacing: 16) {
                Divider()
                    .padding(.horizontal, 24)
                
                HStack {
                    // Step Dots Indicator
                    HStack(spacing: 8) {
                        ForEach(0..<3) { step in
                            Circle()
                                .fill(step == currentStep ? AnyShapeStyle(LumoTheme.brandGradient) : AnyShapeStyle(LumoTheme.textTertiary.opacity(0.3)))
                                .frame(width: step == currentStep ? 10 : 7, height: step == currentStep ? 10 : 7)
                                .animation(.easeInOut(duration: 0.2), value: currentStep)
                        }
                    }
                    
                    Spacer()
                    
                    // Back Button
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.lumoSecondary)
                    }
                    
                    // Primary Action Button
                    if currentStep < 2 {
                        Button("Next") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(.lumoPrimary)
                    } else {
                        Button("Start Listening") {
                            finishOnboarding()
                        }
                        .buttonStyle(.lumoPrimary)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 580, height: 490)
        .background(LumoTheme.bg0)
    }
    
    // MARK: - Step 1: Music Folder Import
    
    private var screenOneMusicFolder: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(LumoTheme.accentPink.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(LumoTheme.brandGradient)
            }
            
            VStack(spacing: 8) {
                Text("Add Your Music Folder")
                    .font(LumoTheme.Typography.title)
                    .foregroundStyle(LumoTheme.textPrimary)
                
                Text("Import local audio files to build your high-fidelity music library. Lumo monitors folders in real-time and detects true lossless files.")
                    .font(LumoTheme.Typography.body)
                    .foregroundStyle(LumoTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            
            VStack(spacing: 12) {
                if let folderName = selectedFolderName {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(LumoTheme.accentAmber)
                        Text(folderName)
                            .font(LumoTheme.Typography.body)
                            .foregroundStyle(LumoTheme.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: LumoTheme.Radius.small)
                            .fill(LumoTheme.surfaceRaised)
                    )
                }
                
                HStack(spacing: 12) {
                    Button {
                        chooseFolder()
                    } label: {
                        Label(selectedFolderName == nil ? "Choose Folder..." : "Change Folder...", systemImage: "folder")
                    }
                    .buttonStyle(.lumoPrimary)
                    
                    Button("Use ~/Music") {
                        useDefaultMusicFolder()
                    }
                    .buttonStyle(.lumoSecondary)
                }
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - Step 2: Auto-Find Covers and Lyrics
    
    private var screenTwoCoversLyrics: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(LumoTheme.accentViolet.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 34))
                    .foregroundStyle(LumoTheme.brandGradient)
            }
            
            VStack(spacing: 8) {
                Text("Auto-Find Covers & Lyrics")
                    .font(LumoTheme.Typography.title)
                    .foregroundStyle(LumoTheme.textPrimary)
                
                Text("Downloaded tracks often have missing art and no lyrics. Lumo searches iTunes, YouTube Music, and LRCLIB to auto-match high-res covers and synced lyrics.")
                    .font(LumoTheme.Typography.body)
                    .foregroundStyle(LumoTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                featureBullet(icon: "photo.artframe", text: "High-resolution cover art upscaled and cached locally")
                featureBullet(icon: "text.quote", text: "Word-by-word synced LRC lyrics with Devanagari Romanization")
                featureBullet(icon: "magnifyingglass", text: "Right-click any song to search or fine-tune metadata")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: LumoTheme.Radius.small)
                    .fill(LumoTheme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: LumoTheme.Radius.small)
                            .stroke(LumoTheme.stroke, lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Step 3: Kinetic Visualizer & Shortcuts
    
    private var screenThreeVisualizer: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(LumoTheme.accentAmber.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 34))
                    .foregroundStyle(LumoTheme.brandGradient)
            }
            
            VStack(spacing: 6) {
                Text("Kinetic Visualizer & Shortcuts")
                    .font(LumoTheme.Typography.title)
                    .foregroundStyle(LumoTheme.textPrimary)
                
                Text("Immerse yourself in dynamic album aura glow, notch-reactive borders, and synchronized typography.")
                    .font(LumoTheme.Typography.body)
                    .foregroundStyle(LumoTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }
            
            // Shortcuts Table
            VStack(spacing: 8) {
                shortcutRow(keys: "⌘ ⇧ V", description: "Open full-screen visualizer")
                shortcutRow(keys: "Esc / ⌘ W", description: "Exit visualizer")
                shortcutRow(keys: "Space", description: "Play / Pause")
                shortcutRow(keys: "⌘ ← / ⌘ →", description: "Previous / Next song")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: LumoTheme.Radius.small)
                    .fill(LumoTheme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: LumoTheme.Radius.small)
                            .stroke(LumoTheme.stroke, lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Helpers
    
    private func featureBullet(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LumoTheme.accentPink)
                .frame(width: 18)
            Text(text)
                .font(LumoTheme.Typography.caption)
                .foregroundStyle(LumoTheme.textPrimary)
        }
    }
    
    private func shortcutRow(keys: String, description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(LumoTheme.accentAmber)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LumoTheme.bg0)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LumoTheme.stroke, lineWidth: 1))
                )
            
            Spacer()
            
            Text(description)
                .font(LumoTheme.Typography.caption)
                .foregroundStyle(LumoTheme.textSecondary)
        }
    }
    
    private func finishOnboarding() {
        settings.hasCompletedOnboarding = true
        dismiss()
    }
    
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import Folder"
        panel.message = "Choose a music folder to add to your Lumo library"
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedFolderName = url.lastPathComponent
            Task.detached {
                await LibraryScanner.shared.scan(folderURL: url)
                await MainActor.run {
                    NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
                }
            }
        }
    }
    
    private func useDefaultMusicFolder() {
        let musicURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Music")
        selectedFolderName = "~/Music"
        Task.detached {
            await LibraryScanner.shared.scan(folderURL: musicURL)
            await MainActor.run {
                NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
            }
        }
    }
}
