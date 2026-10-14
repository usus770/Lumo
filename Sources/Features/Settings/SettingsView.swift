import SwiftUI

/// Settings window with tabbed interface for all preferences.
struct SettingsView: View {
    @State private var diagnosticsCollector = ProviderDiagnosticsCollector.shared
    @State private var selectedTab: Int = 4
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)

            PlaybackSettingsTab()
                .tabItem { Label("Playback", systemImage: "play.circle") }
                .tag(1)

            EQSettingsTab()
                .tabItem { Label("Equalizer", systemImage: "slider.horizontal.3") }
                .tag(2)

            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(3)

            SyncDiagnosticsTab()
                .tabItem { Label("Sync Diagnostics", systemImage: "stethoscope") }
                .tag(4)
                
            LyricsSettingsTab()
                .tabItem { Label("Lyrics", systemImage: "music.mic") }
                .tag(5)
                
            TrackDiagnosticsTab()
                .tabItem { Label("Debug", systemImage: "ladybug") }
                .tag(6)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumoSelectSettingsTab"))) { notif in
            if let tab = notif.object as? Int {
                selectedTab = tab
            }
        }
        .frame(width: 820, height: 620)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @State private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Close to Menu Bar", isOn: Bindable(settings).closeToMenuBar)
                Toggle("Show Track Change Notifications", isOn: Bindable(settings).showTrackChangeNotifications)
            }
            Section("Menu Bar") {
                Toggle("Show Menu Bar Icon", isOn: Bindable(settings).showMenuBarIcon)
            }
            Section("Onboarding") {
                Button("Show Onboarding Again") {
                    settings.hasCompletedOnboarding = false
                    NotificationCenter.default.post(name: Notification.Name("LumoShowOnboarding"), object: nil)
                }
                .buttonStyle(.lumoSecondary)
            }
            Section("About & Developer") {
                HStack {
                    Text("Developer")
                    Spacer()
                    Text("Ujjwal Singh")
                        .foregroundStyle(LumoColors.textSecondary)
                }
                HStack {
                    Text("GitHub")
                    Spacer()
                    Link("github.com/usus770", destination: URL(string: "https://github.com/usus770")!)
                        .foregroundStyle(LumoTheme.accentPink)
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0 (1)")
                        .foregroundStyle(LumoColors.textSecondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Playback Tab

struct PlaybackSettingsTab: View {
    @State private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section("Playback") {
                Toggle("Gapless Playback", isOn: Bindable(settings).isGaplessEnabled)

                HStack {
                    Text("Crossfade")
                    Spacer()
                    Slider(
                        value: Bindable(settings).crossfadeDuration,
                        in: 0...12, step: 0.5
                    )
                    .frame(width: 160)
                    Text(settings.crossfadeDuration == 0
                         ? "Off"
                         : String(format: "%.1f s", settings.crossfadeDuration))
                    .frame(width: 44, alignment: .trailing)
                    .foregroundStyle(LumoColors.textSecondary)
                    .font(LumoFonts.bodySmall)
                }

                HStack {
                    Text("Playback Speed")
                    Spacer()
                    Slider(
                        value: Bindable(settings).playbackSpeed,
                        in: 0.5...2.0, step: 0.05
                    )
                    .frame(width: 160)
                    Text(String(format: "%.2fx", settings.playbackSpeed))
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(LumoColors.textSecondary)
                        .font(LumoFonts.bodySmall)
                }
            }

            Section("Volume") {
                Picker("Normalization", selection: Bindable(settings).volumeNormalizationMode) {
                    Text("Off").tag("off")
                    Text("Track").tag("track")
                    Text("Album").tag("album")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - EQ Tab

struct EQSettingsTab: View {
    @State private var settings = SettingsStore.shared
    private let freqLabels = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

    var body: some View {
        VStack(spacing: 16) {
            // Enable toggle + preset picker
            HStack(spacing: 16) {
                Toggle("Enable EQ", isOn: Bindable(settings).isEQEnabled)
                    .toggleStyle(.switch)

                Spacer()

                Picker("Preset", selection: Bindable(settings).eqPresetName) {
                    Text("Custom").tag("")
                    ForEach(settings.availablePresets) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                }
                .frame(width: 160)
                .onChange(of: settings.eqPresetName) { _, newName in
                    if let preset = settings.availablePresets.first(where: { $0.name == newName }) {
                        // Apply without re-triggering the picker loop
                        withAnimation(.easeOut(duration: 0.2)) {
                            settings.eqBandGains = preset.gains
                        }
                    }
                }
                .disabled(!settings.isEQEnabled)

                Button("Reset") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        settings.eqBandGains = Array(repeating: 0, count: 10)
                        settings.eqPresetName = ""
                    }
                }
                .buttonStyle(.lumoSecondary)
                .disabled(!settings.isEQEnabled)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Band sliders
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<10, id: \.self) { idx in
                    EQBandSlider(
                        label: freqLabels[idx],
                        gain: bandBinding(idx),
                        enabled: settings.isEQEnabled
                    )
                    .onChange(of: settings.eqBandGains[idx]) { _, _ in
                        // Clear preset name when manually adjusted
                        if !settings.eqPresetName.isEmpty {
                            settings.eqPresetName = ""
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)

            // dB scale legend
            HStack {
                Text("+12 dB")
                Spacer()
                Text("0 dB").foregroundStyle(LumoColors.accent)
                Spacer()
                Text("-12 dB")
            }
            .font(LumoFonts.micro)
            .foregroundStyle(LumoColors.textTertiary)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .opacity(settings.isEQEnabled ? 1.0 : 0.5)
    }

    private func bandBinding(_ idx: Int) -> Binding<Float> {
        Binding(
            get: { settings.eqBandGains.indices.contains(idx) ? settings.eqBandGains[idx] : 0 },
            set: { newVal in
                if settings.eqBandGains.indices.contains(idx) {
                    settings.eqBandGains[idx] = newVal
                }
            }
        )
    }
}

// MARK: - EQ Band Slider

struct EQBandSlider: View {
    let label: String
    @Binding var gain: Float
    let enabled: Bool

    var body: some View {
        VStack(spacing: 6) {
            // dB value
            Text(gain == 0
                 ? "0"
                 : (gain > 0 ? "+\(Int(gain))" : "\(Int(gain))"))
                .font(LumoFonts.micro)
                .foregroundStyle(
                    gain == 0 ? LumoColors.textTertiary :
                    gain > 0  ? LumoColors.accent        : LumoColors.accentSecondary
                )
                .frame(height: 16)

            // Vertical slider (-12 to +12 dB)
            VerticalSlider(value: $gain, range: -12...12, enabled: enabled)
                .frame(height: 140)

            // Frequency label
            Text(label)
                .font(LumoFonts.micro)
                .foregroundStyle(LumoColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Vertical Slider

struct VerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let enabled: Bool
    @State private var isDragging = false

    private var fraction: Double {
        Double((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    var body: some View {
        GeometryReader { geo in
            let trackH = geo.size.height
            let thumbY = trackH * (1 - fraction)

            ZStack(alignment: .top) {
                // Track background
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.08))
                    .frame(width: 4)
                    .frame(maxWidth: .infinity)

                // Filled portion (zero line to thumb)
                let zeroFraction = Double((0 - range.lowerBound) / (range.upperBound - range.lowerBound))
                let zeroY = trackH * (1 - zeroFraction)
                let filledTop  = min(thumbY, zeroY)
                let filledH    = abs(zeroY - thumbY)

                RoundedRectangle(cornerRadius: 3)
                    .fill(value >= 0 ? LumoColors.accent : LumoColors.accentSecondary)
                    .frame(width: 4, height: max(1, filledH))
                    .frame(maxWidth: .infinity)
                    .offset(y: filledTop)

                // Zero-line tick
                Rectangle()
                    .fill(LumoColors.accent.opacity(0.35))
                    .frame(width: 12, height: 1)
                    .frame(maxWidth: .infinity)
                    .offset(y: zeroY - 0.5)

                // Thumb
                Circle()
                    .fill(enabled ? LumoColors.accent : LumoColors.textTertiary)
                    .frame(width: isDragging ? 14 : 11, height: isDragging ? 14 : 11)
                    .shadow(color: LumoColors.accent.opacity(isDragging ? 0.5 : 0.2),
                            radius: isDragging ? 6 : 3)
                    .frame(maxWidth: .infinity)
                    .offset(y: thumbY - (isDragging ? 7 : 5.5))
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard enabled else { return }
                        isDragging = true
                        let raw = Float(1 - drag.location.y / trackH)
                        let clamped = max(0, min(1, raw))
                        value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                        // Snap to 0
                        if abs(value) < 0.6 { value = 0 }
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
    }
}

// MARK: - Appearance Tab

struct AppearanceSettingsTab: View {
    @State private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: Bindable(settings).appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Menu Bar") {
                Toggle("Show Menu Bar Icon", isOn: Bindable(settings).showMenuBarIcon)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Sync Diagnostics Tab

struct SyncDiagnosticsTab: View {
    @State private var diagnosticsCollector = ProviderDiagnosticsCollector.shared
    @State private var isRefreshing = false
    @State private var selectedProvider: ProviderDiagnostics?
    @State private var showEnableForMeConfirm = false
    @State private var enableForMeMessage: String? = nil
    @State private var settings = SettingsStore.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Now Playing Sync Diagnostics")
                        .font(LumoFonts.headingLarge)
                        .foregroundStyle(LumoColors.textPrimary)
                    Text("System-wide monitoring status, browser integration & automation permissions")
                        .font(LumoFonts.caption)
                        .foregroundStyle(LumoColors.textTertiary)
                }
                
                Spacer()
                
                Button {
                    Task { await refreshAll() }
                } label: {
                    Label(isRefreshing ? "Refreshing..." : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.lumoSecondary)
                .disabled(isRefreshing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .padding(.horizontal, 20)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
            
                    // MARK: - Arbitration & Preferred Source
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.accentColor)
                            Text("Provider Arbitration & Priority Pinning")
                                .font(LumoFonts.bodyMedium.weight(.semibold))
                                .foregroundStyle(LumoColors.textPrimary)
                            Spacer()
                            if let active = diagnosticsCollector.diagnostics.first(where: { $0.status == .active }) {
                                Text("Active: \(active.id)")
                                    .font(LumoFonts.micro)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundStyle(Color.green)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Text("When multiple providers run simultaneously, Lumo arbitrates using active playback, start times, and de-duplicates identical tracks within 2 seconds. You can pin a preferred source below.")
                            .font(LumoFonts.micro)
                            .foregroundStyle(LumoColors.textSecondary)
                        
                        HStack {
                            Text("Pinned Source:")
                                .font(LumoFonts.bodySmall)
                                .foregroundStyle(LumoColors.textPrimary)
                            Spacer()
                            Picker("", selection: Bindable(settings).preferredExternalSource) {
                                Text("Auto (Smart Arbitration)").tag("auto")
                                Text("Browser Extension (Highest Fidelity)").tag("extension")
                                Text("YouTube Music Desktop (Electron)").tag("electron")
                                Text("System Now Playing (Safari & Web Apps)").tag("system")
                                Text("Google Chrome (AppleScript)").tag("chrome")
                                Text("Apple Music").tag("apple_music")
                                Text("Spotify").tag("spotify")
                            }
                            .frame(width: 280)
                        }
                    }
                    .padding(14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // MARK: - System Environment Cards
                    environmentCards
                    
                    // MARK: - Provider Breakdown Header
                    HStack {
                        Text("Active Providers")
                            .font(LumoFonts.headingSmall)
                            .foregroundStyle(LumoColors.textPrimary)
                        
                        Spacer()
                        
                        if let lastRef = diagnosticsCollector.lastRefreshed {
                            Text("Updated \(lastRef, style: .time)")
                                .font(LumoFonts.micro)
                                .foregroundStyle(LumoColors.textTertiary)
                        }
                    }
                    .padding(.top, 4)
                    
                    // Provider List
                    if diagnosticsCollector.diagnostics.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "stethoscope")
                                .font(.system(size: 36, weight: .ultraLight))
                                .foregroundStyle(LumoColors.accent.opacity(0.4))
                            Text("No Provider Diagnostics Collected")
                                .font(LumoFonts.bodyMedium)
                                .foregroundStyle(LumoColors.textSecondary)
                            Button("Run Diagnostics") {
                                Task { await refreshAll() }
                            }
                            .buttonStyle(.lumoPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(diagnosticsCollector.diagnostics) { diag in
                                ProviderDiagnosticsRow(
                                    diag: diag,
                                    isSelected: selectedProvider?.id == diag.id
                                ) {
                                    if selectedProvider?.id == diag.id {
                                        selectedProvider = nil
                                    } else {
                                        selectedProvider = diag
                                    }
                                }
                            }
                        }
                    }
                    
                    // MARK: - Detailed Provider Inspector
                    if let selected = selectedProvider {
                        ProviderDetailView(diag: selected)
                            .transition(.opacity)
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task { await refreshAll() }
        }
    }
    
    private var environmentCards: some View {
        VStack(spacing: 12) {
            // Safari Web App (PWA) Status Card
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.blue)
                    Text("Safari Web App (PWA) Support")
                        .font(LumoFonts.bodyMedium.weight(.semibold))
                        .foregroundStyle(LumoColors.textPrimary)
                    Spacer()
                    Text("Covered by System Now Playing")
                        .font(LumoFonts.micro)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(Color.green)
                        .clipShape(Capsule())
                }
                
                if diagnosticsCollector.safariWebApps.isEmpty {
                    Text("No Safari Web Apps found under ~/Applications. To install YouTube Music as a PWA, open music.youtube.com in Safari and choose File > Add to Dock.")
                        .font(LumoFonts.micro)
                        .foregroundStyle(LumoColors.textTertiary)
                } else {
                    ForEach(diagnosticsCollector.safariWebApps) { app in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(app.isRunning ? Color.green : Color.gray.opacity(0.6))
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(app.name)
                                        .font(LumoFonts.bodySmall.weight(.medium))
                                        .foregroundStyle(LumoColors.textPrimary)
                                    if app.isYouTubeMusic {
                                        Text("YouTube Music PWA")
                                            .font(LumoFonts.micro)
                                            .foregroundStyle(LumoColors.accent)
                                    }
                                }
                                Text("\(app.bundleIdentifier) • \(app.isRunning ? "Running" : "Idle")")
                                    .font(LumoFonts.micro)
                                    .foregroundStyle(LumoColors.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text("Safari Web Apps publish metadata to macOS Now Playing via navigator.mediaSession. Lumo reads this directly without requiring AppleScript or JS injection.")
                        .font(LumoFonts.micro)
                        .foregroundStyle(LumoColors.textSecondary)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Chrome & Chromium Apple Events Card
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.orange)
                    Text("Google Chrome Apple Events Bridge")
                        .font(LumoFonts.bodyMedium.weight(.semibold))
                        .foregroundStyle(LumoColors.textPrimary)
                    Spacer()
                    
                    if diagnosticsCollector.isChromeRunning {
                        if diagnosticsCollector.chromeAppleEventsEnabled == true {
                            Text("JS from Apple Events: ON ✓")
                                .font(LumoFonts.micro)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(Color.green)
                                .clipShape(Capsule())
                        } else {
                            Text("JS from Apple Events: OFF ✗")
                                .font(LumoFonts.micro)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(Color.orange)
                                .clipShape(Capsule())
                        }
                    } else {
                        Text(diagnosticsCollector.isChromeInstalled ? "Chrome Not Running" : "Chrome Not Installed")
                            .font(LumoFonts.micro)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.gray.opacity(0.15))
                            .foregroundStyle(Color.gray)
                            .clipShape(Capsule())
                    }
                }
                
                Text(diagnosticsCollector.chromeAppleEventsDetail)
                    .font(LumoFonts.micro)
                    .foregroundStyle(diagnosticsCollector.chromeAppleEventsEnabled == false ? LumoColors.accent : LumoColors.textTertiary)
                
                if diagnosticsCollector.chromeAppleEventsEnabled == false {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.orange)
                            Text("Steps to enable manually: Chrome menu bar > View > Developer > Allow JavaScript from Apple Events. (This item is in the top macOS menu bar, NOT inside DevTools window.)")
                                .font(LumoFonts.micro)
                                .foregroundStyle(LumoColors.textSecondary)
                        }
                        
                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    await refreshAll()
                                }
                            } label: {
                                Label("Recheck Setting", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.lumoSecondary)
                            
                            Button {
                                showEnableForMeConfirm = true
                            } label: {
                                Label("Enable for me", systemImage: "terminal.fill")
                            }
                            .buttonStyle(.lumoSecondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .alert("Enable JavaScript from Apple Events", isPresented: $showEnableForMeConfirm) {
                Button("Enable & Apply Policy", role: .none) {
                    let success = ChromeYouTubeMusicProvider.enableChromeAppleEventsPolicy()
                    if success {
                        enableForMeMessage = "Preference written successfully! Please completely quit Chrome (Cmd+Q) and reopen it for changes to take effect."
                    } else {
                        enableForMeMessage = "Failed to write preference. Please set it manually via Chrome menu bar > View > Developer."
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This modifies the Chrome policy preference 'AllowJavaScriptAppleEvents' to true via macOS defaults. You must fully quit Chrome (Cmd+Q) and relaunch it for changes to take effect.")
            }
            .alert("Chrome Setting Status", isPresented: Binding(
                get: { enableForMeMessage != nil },
                set: { if !$0 { enableForMeMessage = nil } }
            )) {
                Button("OK") {
                    enableForMeMessage = nil
                    Task { await refreshAll() }
                }
            } message: {
                Text(enableForMeMessage ?? "")
            }
            // Companion Browser Extension Card
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.purple)
                    Text("Companion Browser Extension (Recommended)")
                        .font(LumoFonts.bodyMedium.weight(.semibold))
                        .foregroundStyle(LumoColors.textPrimary)
                    Spacer()
                    
                    if ExtensionServer.shared.isConnected {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 7, height: 7)
                            Text("Connected (Live)")
                                .font(LumoFonts.micro)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(Color.green)
                        .clipShape(Capsule())
                    } else {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 7, height: 7)
                            Text("Waiting for Connection")
                                .font(LumoFonts.micro)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(Color.orange)
                        .clipShape(Capsule())
                    }
                }
                
                Text(ExtensionServer.shared.isConnected
                    ? "Active two-way WebSocket connection with Chrome / Brave / Edge / Arc extension on 127.0.0.1:19847. Provides highest-fidelity album art and millisecond-accurate sync."
                    : "The Manifest V3 companion extension streams rich metadata from music.youtube.com without requiring any browser developer settings or Apple Events.")
                    .font(LumoFonts.micro)
                    .foregroundStyle(LumoColors.textSecondary)
                
                HStack(spacing: 10) {
                    Button {
                        let localPath = FileManager.default.currentDirectoryPath + "/BrowserExtension"
                        let bundlePath = (Bundle.main.resourcePath ?? "") + "/BrowserExtension"
                        let path = FileManager.default.fileExists(atPath: localPath) ? localPath : bundlePath
                        NSWorkspace.shared.selectFile(path + "/manifest.json", inFileViewerRootedAtPath: "")
                    } label: {
                        Label("Reveal Extension Folder", systemImage: "folder")
                    }
                    .buttonStyle(.lumoSecondary)
                    
                    Button {
                        let localScript = FileManager.default.currentDirectoryPath + "/BrowserExtension/install-native-host.sh"
                        let bundleScript = (Bundle.main.resourcePath ?? "") + "/BrowserExtension/install-native-host.sh"
                        let script = FileManager.default.fileExists(atPath: localScript) ? localScript : bundleScript
                        let proc = Process()
                        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                        proc.arguments = [script]
                        try? proc.run()
                    } label: {
                        Label("Register Native Host", systemImage: "terminal")
                    }
                    .buttonStyle(.lumoSecondary)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let providers = NowPlayingProviderManager.shared.allProviders
        await diagnosticsCollector.refreshAll(providers: providers)
    }
}

/// Individual provider row in the diagnostics list
struct ProviderDiagnosticsRow: View {
    let diag: ProviderDiagnostics
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Status indicator
                Image(systemName: diag.status.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(diag.status.color))
                    .frame(width: 24)
                
                // Provider info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(diag.id)
                            .font(LumoFonts.bodyMedium.weight(.semibold))
                            .foregroundStyle(LumoColors.textPrimary)
                        
                        Text(diag.status.rawValue)
                            .font(LumoFonts.micro)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(diag.status.color).opacity(0.15))
                            .foregroundStyle(Color(diag.status.color))
                            .clipShape(Capsule())
                        
                        if diag.requiresAppleEvents {
                            Image(systemName: "applescript")
                                .font(.system(size: 10))
                                .foregroundStyle(LumoColors.textTertiary)
                        }
                    }
                    
                    Text(diag.reason)
                        .font(LumoFonts.micro)
                        .foregroundStyle(LumoColors.textSecondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Automation status badge if applicable
                if let perm = diag.automationPermission {
                    Text(perm.rawValue)
                        .font(LumoFonts.micro)
                        .foregroundStyle(perm == .granted ? Color.green : (perm == .denied ? Color.red : Color.gray))
                }
                
                Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(LumoColors.textTertiary)
            }
            .padding(12)
            .background(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Detailed view for a selected provider
struct ProviderDetailView: View {
    let diag: ProviderDiagnostics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Diagnostics Details: \(diag.id)")
                    .font(LumoFonts.headingSmall)
                    .foregroundStyle(LumoColors.textPrimary)
                Spacer()
                Image(systemName: diag.status.systemImage)
                    .foregroundStyle(Color(diag.status.color))
            }
            .padding(.bottom, 4)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                DetailRow(label: "Provider Class", value: diag.providerType)
                DetailRow(label: "Available", value: diag.isAvailable ? "Yes" : "No")
                DetailRow(label: "Running Status", value: diag.isRunning ? "Running" : "Not Running")
                
                if diag.requiresAppleEvents {
                    DetailRow(label: "Requires Apple Events", value: "Yes")
                    if let appleEvents = diag.appleEventsEnabled {
                        DetailRow(label: "JS Apple Events", value: appleEvents ? "Enabled ✓" : "Disabled ✗", error: !appleEvents)
                    }
                }
                
                if let perm = diag.automationPermission {
                    DetailRow(label: "TCC Automation", value: perm.description, error: perm == .denied)
                }
                
                if !diag.bundleIdentifiers.isEmpty {
                    DetailRow(label: "Target Bundle IDs", value: diag.bundleIdentifiers.joined(separator: ", "))
                }
                
                if let lastUpdate = diag.lastUpdate {
                    DetailRow(label: "Last Playback Update", value: lastUpdate.formatted(date: .omitted, time: .standard))
                }
                
                if let error = diag.lastError {
                    DetailRow(label: "Last Error", value: error, error: true)
                }
                
                if let state = diag.lastState {
                    Divider()
                    Text("Last Captured Playback State")
                        .font(LumoFonts.bodyMedium.weight(.semibold))
                        .foregroundStyle(LumoColors.textPrimary)
                    
                    DetailRow(label: "Track Title", value: state.trackName ?? "—")
                    DetailRow(label: "Artist", value: state.artistName ?? "—")
                    DetailRow(label: "Album", value: state.albumName ?? "—")
                    DetailRow(label: "Playback State", value: state.isPlaying ? "Playing ▶" : "Paused ⏸")
                    DetailRow(label: "Position / Duration", value: "\(Int(state.currentTime))s / \(Int(state.duration))s")
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var error: Bool = false
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(LumoFonts.bodySmall)
                .foregroundStyle(LumoColors.textSecondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(LumoFonts.bodySmall.weight(.medium))
                .foregroundStyle(error ? LumoColors.error : LumoColors.textPrimary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - Lyrics Tab

struct LyricsSettingsTab: View {
    @State private var settings = SettingsStore.shared
    @State private var apiKey: String = ""
    @State private var showPrivacyNotice = false
    @State private var tempEnableToggle = false
    
    let languages = [
        "Auto", "English", "Hindi", "Punjabi", "Korean", "Japanese", "Spanish", "French", "German"
    ]
    let models = [
        "whisper-large-v3-turbo", "whisper-large-v3"
    ]
    
    var body: some View {
        Form {
            Section("Transcription Setup") {
                HStack {
                    SecureField("Groq API Key (saved securely in Keychain)", text: $apiKey)
                        .onChange(of: apiKey) { _, newValue in
                            GroqKeychain.saveKey(newValue)
                        }
                    
                    Button("Test key") {
                        // Implement test key later
                    }
                    .buttonStyle(.lumoSecondary)
                }
                
                Toggle("Generate lyrics with Groq (uploads audio to Groq)", isOn: $tempEnableToggle)
                    .onChange(of: tempEnableToggle) { _, newValue in
                        if newValue && !settings.enableGroqLyrics {
                            showPrivacyNotice = true
                            tempEnableToggle = false // Revert until accepted
                        } else {
                            settings.enableGroqLyrics = newValue
                        }
                    }
            }
            
            if settings.enableGroqLyrics {
                Section("Whisper Settings") {
                    Picker("Language", selection: Bindable(settings).groqLanguage) {
                        ForEach(languages, id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    
                    Picker("Model", selection: Bindable(settings).groqModel) {
                        ForEach(models, id: \.self) { model in
                            Text(model == "whisper-large-v3-turbo" ? "\(model) (Fast)" : "\(model) (Accurate)").tag(model)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            self.apiKey = GroqKeychain.getKey() ?? ""
            self.tempEnableToggle = settings.enableGroqLyrics
        }
        .alert("Privacy Notice", isPresented: $showPrivacyNotice) {
            Button("Accept & Enable", role: .none) {
                settings.enableGroqLyrics = true
                tempEnableToggle = true
            }
            Button("Cancel", role: .cancel) {
                tempEnableToggle = false
            }
        } message: {
            Text("By enabling this feature, Lumo will extract up to 25MB of audio from the currently playing song and upload it to Groq's API servers to generate word-level lyric timestamps. Your API key will be used for these requests. Do you wish to continue?")
        }
    }
}

// MARK: - Track Diagnostics Tab (Phase 6)

struct TrackDiagnosticsTab: View {
    @State private var snapshot = NowPlayingSnapshot.shared
    @State private var copiedConfirmation = false
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let hostNow = ProcessInfo.processInfo.systemUptime
            let currentPos = snapshot.position(at: hostNow)
            let lyricsPos = snapshot.lyricsTime(at: hostNow)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header & Quick Actions
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Track Diagnostics & Debugger")
                                .font(LumoFonts.headingMedium)
                                .foregroundStyle(LumoColors.textPrimary)
                            Text("Real-time inspection of active track metadata, lyrics provider, artwork, and clock anchor.")
                                .font(LumoFonts.bodySmall)
                                .foregroundStyle(LumoColors.textSecondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            copyDiagnosticsToClipboard(currentPos: currentPos, lyricsPos: lyricsPos)
                        } label: {
                            Label(copiedConfirmation ? "Copied!" : "Copy Report", systemImage: copiedConfirmation ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    // 1. Current Track Metadata Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Metadata Resolution")
                            .font(LumoFonts.headingSmall)
                            .foregroundStyle(LumoColors.accent)
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                Text("Playback Source:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(snapshot.isExternal ? "External (\(snapshot.appName))" : "Local File")
                                    .font(LumoFonts.bodySmall.weight(.semibold))
                            }
                            GridRow {
                                Text("Stable ID:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(snapshot.id.isEmpty ? "(None)" : snapshot.id)
                                    .font(LumoFonts.mono)
                            }
                            GridRow {
                                Text("Raw Title:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(snapshot.title.isEmpty ? "(Empty)" : snapshot.title)
                                    .font(LumoFonts.bodySmall)
                            }
                            GridRow {
                                Text("Cleaned Title:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(TitleCleaner.clean(snapshot.title).cleanedString)
                                    .font(LumoFonts.bodySmall.weight(.medium))
                            }
                            GridRow {
                                Text("Chosen Artist:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(snapshot.artist.isEmpty ? "(Unknown)" : snapshot.artist)
                                    .font(LumoFonts.bodySmall)
                            }
                            GridRow {
                                Text("Cleaned Artist:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(TitleCleaner.clean(snapshot.artist).cleanedString)
                                    .font(LumoFonts.bodySmall.weight(.medium))
                            }
                            GridRow {
                                Text("Album:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(snapshot.album.isEmpty ? "(None)" : snapshot.album)
                                    .font(LumoFonts.bodySmall)
                            }
                            if let vid = snapshot.videoId, !vid.isEmpty {
                                GridRow {
                                    Text("YouTube Video ID:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                    Text(vid).font(LumoFonts.mono)
                                }
                            }
                            if !snapshot.filePath.isEmpty {
                                GridRow {
                                    Text("File Path:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                    Text(snapshot.filePath).font(LumoFonts.mono).lineLimit(1)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LumoColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // 2. Lyrics Pipeline Diagnostics
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Lyrics Pipeline")
                                .font(LumoFonts.headingSmall)
                                .foregroundStyle(LumoColors.accent)
                            Spacer()
                            Button("Refetch Lyrics") {
                                snapshot.refetchLyrics(forceRemote: true)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                Text("Winning Provider:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(snapshot.lyricsSource ?? (snapshot.isFetchingLyrics ? "Searching..." : "None"))
                                    .font(LumoFonts.bodySmall.weight(.semibold))
                            }
                            GridRow {
                                Text("Time Sync Type:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(snapshot.hasSyncedLyrics ? "Synced (LRC / Enhanced)" : "Plain Text / None")
                                    .font(LumoFonts.bodySmall)
                            }
                            GridRow {
                                Text("Look-Ahead Offset:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(String(format: "%.0f ms", snapshot.globalLyricsOffset * 1000)).font(LumoFonts.mono)
                            }
                            GridRow {
                                Text("User Offset:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(String(format: "%.0f ms", snapshot.userLyricsOffset * 1000)).font(LumoFonts.mono)
                            }
                            GridRow {
                                Text("Total Applied Offset:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(String(format: "%.0f ms", snapshot.totalLyricsOffset * 1000)).font(LumoFonts.mono.weight(.semibold))
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LumoColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // 3. Artwork Pipeline Diagnostics
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Artwork Pipeline")
                                .font(LumoFonts.headingSmall)
                                .foregroundStyle(LumoColors.accent)
                            Spacer()
                            Button("Refetch Artwork") {
                                snapshot.refetchArtwork()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                Text("Artwork Status:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(snapshot.artworkData != nil ? "Loaded" : (snapshot.isFetchingArtwork ? "Fetching..." : "No Artwork"))
                                    .font(LumoFonts.bodySmall.weight(.semibold))
                            }
                            if let data = snapshot.artworkData {
                                GridRow {
                                    Text("Resolution Quality:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                    Text(ArtworkPipeline.isHighResolution(data: data) ? "High Resolution (>= 300px)" : "Low Resolution (< 300px)")
                                        .font(LumoFonts.bodySmall)
                                }
                                GridRow {
                                    Text("Payload Size:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                                        .font(LumoFonts.mono)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LumoColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // 4. Smooth Clock & Anchor Diagnostics
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clock Anchor & Synchronization")
                            .font(LumoFonts.headingSmall)
                            .foregroundStyle(LumoColors.accent)
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                Text("Current Clock:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(String(format: "%.3f s / %.1f s", currentPos, snapshot.duration)).font(LumoFonts.mono.weight(.semibold))
                            }
                            GridRow {
                                Text("Lyrics Synchronized Clock:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(String(format: "%.3f s", lyricsPos)).font(LumoFonts.mono)
                            }
                            GridRow {
                                Text("Anchor Time:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(String(format: "%.3f s (host: %.3f s)", snapshot.positionAnchor.time, snapshot.positionAnchor.hostTime)).font(LumoFonts.mono)
                            }
                            GridRow {
                                Text("Playback Rate:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(String(format: "%.2fx", snapshot.playbackRate)).font(LumoFonts.mono)
                            }
                            GridRow {
                                Text("Playback State:").font(LumoFonts.bodySmall).foregroundStyle(LumoColors.textSecondary)
                                Text(snapshot.isPlaying ? "Playing" : "Paused").font(LumoFonts.bodySmall.weight(.medium))
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LumoColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
        }
    }
    
    private func copyDiagnosticsToClipboard(currentPos: TimeInterval, lyricsPos: TimeInterval) {
        let report = """
        === LUMO TRACK DIAGNOSTICS REPORT ===
        Time: \(Date())
        Source: \(snapshot.isExternal ? "External (\(snapshot.appName))" : "Local")
        Stable ID: \(snapshot.id)
        Raw Title: \(snapshot.title)
        Cleaned Title: \(TitleCleaner.clean(snapshot.title).cleanedString)
        Raw Artist: \(snapshot.artist)
        Cleaned Artist: \(TitleCleaner.clean(snapshot.artist).cleanedString)
        Album: \(snapshot.album)
        Duration: \(String(format: "%.2f s", snapshot.duration))
        File Path: \(snapshot.filePath)
        Video ID: \(snapshot.videoId ?? "none")
        
        [Lyrics Pipeline]
        Provider: \(snapshot.lyricsSource ?? "none")
        Synced: \(snapshot.hasSyncedLyrics)
        Look-Ahead Offset: \(String(format: "%.0f ms", snapshot.globalLyricsOffset * 1000))
        User Offset: \(String(format: "%.0f ms", snapshot.userLyricsOffset * 1000))
        Total Offset: \(String(format: "%.0f ms", snapshot.totalLyricsOffset * 1000))
        
        [Artwork Pipeline]
        Loaded: \(snapshot.artworkData != nil)
        High-Res: \(snapshot.artworkData != nil ? String(ArtworkPipeline.isHighResolution(data: snapshot.artworkData!)) : "false")
        Byte Size: \(snapshot.artworkData?.count ?? 0) bytes
        
        [Clock Synchronization]
        Playing: \(snapshot.isPlaying)
        Rate: \(snapshot.playbackRate)
        Current Time: \(String(format: "%.3f s", currentPos))
        Lyrics Time: \(String(format: "%.3f s", lyricsPos))
        Anchor Time: \(snapshot.positionAnchor.time)
        Anchor Host: \(snapshot.positionAnchor.hostTime)
        =====================================
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        withAnimation {
            copiedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                copiedConfirmation = false
            }
        }
    }
}


