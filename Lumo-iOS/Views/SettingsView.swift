import SwiftUI

/// Settings and Developer Credits view for Lumo iOS.
public struct iOSSettingsView: View {
    @AppStorage("lumo_gapless") private var gaplessEnabled: Bool = true
    @AppStorage("lumo_crossfade") private var crossfadeSeconds: Double = 0.0
    @AppStorage("lumo_romanize_lyrics") private var romanizeLyrics: Bool = true
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                LumoTheme.bg0.ignoresSafeArea()
                
                Form {
                    // MARK: - Playback Settings
                    Section("Audio & Playback") {
                        Toggle("Gapless Playback", isOn: $gaplessEnabled)
                            .tint(LumoTheme.accentPink)
                        
                        Toggle("Auto-Romanize Indic / Asian Lyrics", isOn: $romanizeLyrics)
                            .tint(LumoTheme.accentPink)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Crossfade")
                                Spacer()
                                Text(crossfadeSeconds == 0 ? "Off" : String(format: "%.1f s", crossfadeSeconds))
                                    .foregroundStyle(LumoTheme.textSecondary)
                            }
                            Slider(value: $crossfadeSeconds, in: 0...10, step: 0.5)
                                .tint(LumoTheme.accentPink)
                        }
                    }
                    .listRowBackground(LumoTheme.surface)
                    
                    // MARK: - iOS System Integration
                    Section("System Integration") {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(LumoTheme.accentAmber)
                            Text("Lock Screen Controls")
                            Spacer()
                            Text("Active")
                                .foregroundStyle(LumoTheme.textSecondary)
                        }
                        
                        HStack {
                            Image(systemName: "airpodsmax")
                                .foregroundStyle(LumoTheme.accentViolet)
                            Text("AirPods & Bluetooth")
                            Spacer()
                            Text("Automatic")
                                .foregroundStyle(LumoTheme.textSecondary)
                        }
                    }
                    .listRowBackground(LumoTheme.surface)
                    
                    // MARK: - Developer & About Section
                    Section("About & Developer") {
                        VStack(alignment: .center, spacing: 14) {
                            // Logo Mark
                            ZStack {
                                Circle()
                                    .fill(LumoTheme.brandGradient)
                                    .frame(width: 64, height: 64)
                                    .shadow(color: LumoTheme.accentPink.opacity(0.4), radius: 12)
                                
                                Image(systemName: "waveform")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(Color.black)
                            }
                            .padding(.top, 8)
                            
                            VStack(spacing: 4) {
                                Text("Lumo")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(LumoTheme.textPrimary)
                                
                                Text("Version 1.0.0 (1) • iOS")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(LumoTheme.textSecondary)
                            }
                            
                            Text("Universal lossless audio playback & reactive kinetic visualizer.")
                                .font(.system(size: 13))
                                .foregroundStyle(LumoTheme.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                            
                            Divider()
                                .background(LumoTheme.stroke)
                            
                            // Creator Attribution
                            HStack(spacing: 6) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(LumoTheme.accentPink)
                                Text("Created by")
                                    .font(.system(size: 13))
                                    .foregroundStyle(LumoTheme.textSecondary)
                                Text("Ujjwal Singh")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(LumoTheme.textPrimary)
                            }
                            
                            // Clickable GitHub Link
                            Link(destination: URL(string: "https://github.com/usus770")!) {
                                HStack(spacing: 6) {
                                    Image(systemName: "link")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("github.com/usus770")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(LumoTheme.accentPink)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(LumoTheme.accentPink.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(LumoTheme.accentPink.opacity(0.35), lineWidth: 1)
                                )
                            }
                            
                            Text("© 2026 Ujjwal Singh. All rights reserved.")
                                .font(.system(size: 11))
                                .foregroundStyle(LumoTheme.textTertiary)
                                .padding(.bottom, 6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(LumoTheme.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
        }
    }
}
