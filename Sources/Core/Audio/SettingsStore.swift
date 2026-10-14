import Foundation
import AVFoundation
import SwiftUI

/// Central observable that owns the persisted AppSettings.
/// All settings views bind to this; changes are written to disk automatically.
@Observable
final class SettingsStore: @unchecked Sendable {
    static let shared = SettingsStore()

    // MARK: - Playback
    var crossfadeDuration: Double     { didSet { save(); applyCrossfade() } }
    var isGaplessEnabled: Bool        { didSet { save() } }
    var playbackSpeed: Float          { didSet { save(); applySpeed() } }
    var volumeNormalizationMode: String { didSet { save() } }

    // MARK: - EQ
    var isEQEnabled: Bool             { didSet { save(); applyEQ() } }
    var eqPresetName: String          { didSet { save() } }
    var eqBandGains: [Float]          { didSet { save(); applyEQ() } }

    // MARK: - Appearance
    var appearanceMode: String        { didSet { save(); applyAppearance() } }
    var showMenuBarIcon: Bool         { didSet { save() } }
    var showNowPlayingBar: Bool       { didSet { save() } }

    // MARK: - Behaviour
    var launchAtLogin: Bool           { didSet { save() } }
    var closeToMenuBar: Bool          { didSet { save() } }
    var showTrackChangeNotifications: Bool { didSet { save() } }
    var hasCompletedOnboarding: Bool       { didSet { save() } }

    // MARK: - Now Playing Sync
    var preferredExternalSource: String    {
        didSet {
            save()
            Task {
                await NowPlayingCoordinator.shared.setPreferredSource(preferredExternalSource)
            }
        }
    }

    // MARK: - Lyrics Providers
    var enableLRCLibLyrics: Bool           { didSet { save() } }
    var enableNetEaseLyrics: Bool          { didSet { save() } }
    var enableGroqLyrics: Bool             { didSet { save() } }
    var groqLanguage: String               { didSet { save() } }
    var groqModel: String                  { didSet { save() } }
    
    // MARK: - Init

    private init() {
        let s = SettingsStore.loadFromDisk() ?? .defaults

        crossfadeDuration           = s.crossfadeDuration
        isGaplessEnabled            = s.isGaplessEnabled
        playbackSpeed               = s.playbackSpeed
        volumeNormalizationMode     = s.volumeNormalizationMode
        isEQEnabled                 = s.isEQEnabled
        eqPresetName                = s.eqPresetName
        eqBandGains                 = s.eqBandGains
        appearanceMode              = s.appearanceMode
        showMenuBarIcon             = s.showMenuBarIcon
        showNowPlayingBar           = s.showNowPlayingBar
        launchAtLogin               = s.launchAtLogin
        closeToMenuBar              = s.closeToMenuBar
        showTrackChangeNotifications = s.showTrackChangeNotifications
        hasCompletedOnboarding      = s.hasCompletedOnboarding
        preferredExternalSource     = s.preferredExternalSource
        enableLRCLibLyrics          = s.enableLRCLibLyrics
        enableNetEaseLyrics         = s.enableNetEaseLyrics
        enableGroqLyrics            = s.enableGroqLyrics
        groqLanguage                = s.groqLanguage
        groqModel                   = s.groqModel
        
        Task {
            await NowPlayingCoordinator.shared.setPreferredSource(s.preferredExternalSource)
        }
    }

    // MARK: - Apply to engine

    func applyAll() {
        applyEQ()
        applySpeed()
        applyCrossfade()
        applyAppearance()
    }

    func applyEQ() {
        Task {
            await AudioEngine.shared.setEQ(
                enabled: isEQEnabled,
                gains: eqBandGains
            )
        }
    }

    func applySpeed() {
        Task {
            await AudioEngine.shared.setPlaybackRate(playbackSpeed)
        }
    }

    func applyCrossfade() {
        Task {
            await AudioEngine.shared.setCrossfadeDuration(crossfadeDuration)
        }
    }

    func applyAppearance() {
        DispatchQueue.main.async {
            guard NSApplication.shared.isActive || NSApp != nil else { return }
            switch self.appearanceMode {
            case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
            case "dark":  NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
            default:      NSApplication.shared.appearance = nil
            }
        }
    }

    // MARK: - Preset helpers

    var availablePresets: [EQPreset] { EQPresetLibrary.shared.presets }

    func applyPreset(_ preset: EQPreset) {
        eqPresetName = preset.name
        eqBandGains  = preset.gains
    }

    // MARK: - Persistence

    private static let storeURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Lumo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }()

    private func save() {
        let s = AppSettings(
            id: UUID(),
            volume: AppConstants.Playback.defaultVolume,
            crossfadeDuration: crossfadeDuration,
            isGaplessEnabled: isGaplessEnabled,
            playbackSpeed: playbackSpeed,
            volumeNormalizationMode: volumeNormalizationMode,
            isEQEnabled: isEQEnabled,
            eqPresetName: eqPresetName,
            eqBandGains: eqBandGains,
            appearanceMode: appearanceMode,
            showMenuBarIcon: showMenuBarIcon,
            showNowPlayingBar: showNowPlayingBar,
            launchAtLogin: launchAtLogin,
            closeToMenuBar: closeToMenuBar,
            showTrackChangeNotifications: showTrackChangeNotifications,
            isBitPerfectMode: false,
            sleepTimerMinutes: 0,
            hasCompletedOnboarding: hasCompletedOnboarding,
            preferredExternalSource: preferredExternalSource,
            enableLRCLibLyrics: enableLRCLibLyrics,
            enableNetEaseLyrics: enableNetEaseLyrics,
            enableGroqLyrics: enableGroqLyrics,
            groqLanguage: groqLanguage,
            groqModel: groqModel
        )
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }

    private static func loadFromDisk() -> AppSettings? {
        guard let data = try? Data(contentsOf: storeURL) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}

// MARK: - EQ Preset model

struct EQPreset: Identifiable, Codable, Sendable {
    var id: String { name }
    let name: String
    let gains: [Float]
}

private struct EQPresetFile: Codable {
    let presets: [EQPreset]
}

/// Loads the bundled EQ presets from EQPresets.json.
final class EQPresetLibrary: @unchecked Sendable {
    static let shared = EQPresetLibrary()
    let presets: [EQPreset]

    private init() {
        // Try bundle resource first, then fallback to source tree path (debug builds)
        var urls: [URL] = [
            Bundle.main.url(forResource: "EQPresets", withExtension: "json")
        ].compactMap { $0 }
        let currentDirURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(currentDirURL.appendingPathComponent("Sources/Resources/EQPresets.json"))

        for url in urls {
            if let data = try? Data(contentsOf: url),
               let file = try? JSONDecoder().decode(EQPresetFile.self, from: data) {
                presets = file.presets
                return
            }
        }
        // Hardcoded fallback
        presets = [EQPreset(name: "Flat", gains: Array(repeating: 0, count: 10))]
    }
}
