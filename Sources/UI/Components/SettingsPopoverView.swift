import SwiftUI
import AppKit

/// Settings popover matching the reference video (frame 4 & frame 8).
/// Controls gradient modes, notch compatibility, thickness, glow,
/// color override wheels, lock-screen player, and dock visibility.
struct SettingsPopoverView: View {
    @AppStorage("visualizerGradientMode") private var gradientMode: String = "musicSync"
    @AppStorage("visualizerNotchCompatible") private var notchCompatible: Bool = true
    @AppStorage("visualizerBorderThickness") private var borderThickness: Double = 4.0
    @AppStorage("visualizerGlowIntensity") private var glowIntensity: Double = 18.0
    @AppStorage("visualizerOverrideColor") private var overrideColor: Bool = false
    @AppStorage("visualizerPrimaryColorHex") private var primaryColorHex: String = "#FF007F"
    @AppStorage("visualizerSecondaryColorHex") private var secondaryColorHex: String = "#7B00FF"
    @AppStorage("visualizerLockScreenPlayer") private var lockScreenPlayer: Bool = true
    @AppStorage("visualizerShowInDock") private var showInDock: Bool = true
    
    @State private var primaryColor: Color = Color(hex: "#FF007F")
    @State private var secondaryColor: Color = Color(hex: "#7B00FF")
    
    var onClose: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("Lumo")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("v1.0")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                
                Spacer()
                
                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 2)
            
            // Gradient Mode Selection
            VStack(alignment: .leading, spacing: 6) {
                Text("Gradient")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                
                HStack(spacing: 4) {
                    modeButton("Default", value: "default")
                    modeButton("Music Sync", value: "musicSync")
                    modeButton("Idle", value: "idle")
                    modeButton("No Animation", value: "none")
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Notch compatibility Toggle
            Toggle(isOn: $notchCompatible) {
                Text("Notch compatibility")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .tint(Color(hex: primaryColorHex))
            
            // Thickness Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Thickness")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(borderThickness)) px")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Slider(value: $borderThickness, in: 2.0...12.0, step: 0.5)
                    .tint(Color(hex: primaryColorHex))
            }
            
            // Glow Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Glow")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(glowIntensity)) px")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Slider(value: $glowIntensity, in: 4.0...36.0, step: 1.0)
                    .tint(Color(hex: secondaryColorHex))
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Override album colour
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $overrideColor) {
                    Text("Override album colour")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white)
                }
                .toggleStyle(.switch)
                .tint(Color(hex: primaryColorHex))
                
                if overrideColor {
                    HStack(spacing: 16) {
                        // Primary Color Picker
                        HStack(spacing: 8) {
                            ColorPicker("", selection: $primaryColor, supportsOpacity: false)
                                .labelsHidden()
                            Text("Primary")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        
                        // Secondary Color Picker
                        HStack(spacing: 8) {
                            ColorPicker("", selection: $secondaryColor, supportsOpacity: false)
                                .labelsHidden()
                            Text("Secondary")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.leading, 4)
                    .onChange(of: primaryColor) { _, newCol in
                        primaryColorHex = newCol.toHex() ?? primaryColorHex
                    }
                    .onChange(of: secondaryColor) { _, newCol in
                        secondaryColorHex = newCol.toHex() ?? secondaryColorHex
                    }
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Display Selector
            HStack {
                Text("Display")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white)
                Spacer()
                Text("Built-in Retina Display")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            // System Options
            Toggle(isOn: $lockScreenPlayer) {
                Text("Lock-screen player")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .tint(Color(hex: primaryColorHex))
            
            Toggle(isOn: $showInDock) {
                Text("Show in Dock")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .tint(Color(hex: primaryColorHex))
            
            Divider().background(Color.white.opacity(0.1))
            
            // Action Buttons
            HStack {
                Button("Check for Updates…") {}
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                
                Spacer()
                
                Button("Quit Lumo") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.red.opacity(0.8))
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 290)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        )
        .onAppear {
            primaryColor = Color(hex: primaryColorHex)
            secondaryColor = Color(hex: secondaryColorHex)
        }
    }
    
    @ViewBuilder
    private func modeButton(_ title: String, value: String) -> some View {
        Button {
            gradientMode = value
        } label: {
            Text(title)
                .font(.system(size: 10, weight: gradientMode == value ? .bold : .medium))
                .foregroundStyle(gradientMode == value ? .white : .white.opacity(0.6))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(gradientMode == value ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}
