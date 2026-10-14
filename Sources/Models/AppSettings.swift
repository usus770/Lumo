import Foundation

/// Persisted app settings.
struct AppSettings: Codable, Identifiable, Sendable {
    var id: UUID
    
    // MARK: - Playback
    
    /// Master volume (0.0 - 1.0).
    var volume: Float
    
    /// Crossfade duration in seconds (0 = disabled, max 12).
    var crossfadeDuration: Double
    
    /// Whether gapless playback is enabled.
    var isGaplessEnabled: Bool
    
    /// Playback speed multiplier (0.5 - 2.0).
    var playbackSpeed: Float
    
    /// Volume normalization mode: "off", "track", "album".
    var volumeNormalizationMode: String
    
    // MARK: - EQ
    
    /// Whether the equalizer is enabled.
    var isEQEnabled: Bool
    
    /// Name of the active EQ preset (empty = custom).
    var eqPresetName: String
    
    /// Custom EQ band gains in dB (10 values).
    var eqBandGains: [Float]
    
    // MARK: - Appearance
    
    /// Appearance mode: "system", "light", "dark".
    var appearanceMode: String
    
    /// Whether to show the menu bar icon.
    var showMenuBarIcon: Bool
    
    /// Whether to show the now-playing bar in the main window.
    var showNowPlayingBar: Bool
    
    // MARK: - Behavior
    
    /// Whether to launch at login.
    var launchAtLogin: Bool
    
    /// Whether to close to menu bar instead of quitting.
    var closeToMenuBar: Bool
    
    /// Whether to show notifications for track changes.
    var showTrackChangeNotifications: Bool
    
    // MARK: - Audio Output
    
    /// Selected audio output device UID (nil = system default).
    var outputDeviceUID: String?
    
    /// Whether bit-perfect / hog mode is enabled.
    var isBitPerfectMode: Bool
    
    // MARK: - Sleep Timer
    
    /// Sleep timer duration in minutes (0 = disabled).
    var sleepTimerMinutes: Int
    
    // MARK: - Onboarding
    
    /// Whether the onboarding flow has been completed.
    var hasCompletedOnboarding: Bool
    
    // MARK: - External Now Playing Sync
    
    /// Pinned preferred external music source ("auto", "extension", "electron", "system", "chrome", "apple_music", "spotify").
    var preferredExternalSource: String
    
    // MARK: - Lyrics Providers
    
    /// Whether LRCLIB is enabled.
    var enableLRCLibLyrics: Bool
    
    /// Whether NetEase is enabled.
    var enableNetEaseLyrics: Bool
    
    /// Whether Groq lyrics generation is enabled.
    var enableGroqLyrics: Bool
    
    /// Language for Groq transcription ("Auto", "English", "Hindi", etc).
    var groqLanguage: String
    
    /// Groq Whisper model to use.
    var groqModel: String
    
    // MARK: - Cover & Tag Writing
    
    /// Optional setting: Write cover art and tags directly into audio file (default OFF).
    var writeCoverAndTagsToFile: Bool
    
    /// Whether automatic background metadata resolution is enabled.
    var autoFindMissingCoversAndLyrics: Bool
    
    init(
        id: UUID = UUID(),
        volume: Float = AppConstants.Playback.defaultVolume,
        crossfadeDuration: Double = 0,
        isGaplessEnabled: Bool = true,
        playbackSpeed: Float = 1.0,
        volumeNormalizationMode: String = "off",
        isEQEnabled: Bool = false,
        eqPresetName: String = "",
        eqBandGains: [Float] = Array(repeating: 0.0, count: 10),
        appearanceMode: String = "system",
        showMenuBarIcon: Bool = true,
        showNowPlayingBar: Bool = true,
        launchAtLogin: Bool = false,
        closeToMenuBar: Bool = false,
        showTrackChangeNotifications: Bool = true,
        outputDeviceUID: String? = nil,
        isBitPerfectMode: Bool = false,
        sleepTimerMinutes: Int = 0,
        hasCompletedOnboarding: Bool = false,
        preferredExternalSource: String = "auto",
        enableLRCLibLyrics: Bool = true,
        enableNetEaseLyrics: Bool = true,
        enableGroqLyrics: Bool = false,
        groqLanguage: String = "Auto",
        groqModel: String = "whisper-large-v3-turbo",
        writeCoverAndTagsToFile: Bool = false,
        autoFindMissingCoversAndLyrics: Bool = true
    ) {
        self.id = id
        self.volume = volume
        self.crossfadeDuration = crossfadeDuration
        self.isGaplessEnabled = isGaplessEnabled
        self.playbackSpeed = playbackSpeed
        self.volumeNormalizationMode = volumeNormalizationMode
        self.isEQEnabled = isEQEnabled
        self.eqPresetName = eqPresetName
        self.eqBandGains = eqBandGains
        self.appearanceMode = appearanceMode
        self.showMenuBarIcon = showMenuBarIcon
        self.showNowPlayingBar = showNowPlayingBar
        self.launchAtLogin = launchAtLogin
        self.closeToMenuBar = closeToMenuBar
        self.showTrackChangeNotifications = showTrackChangeNotifications
        self.outputDeviceUID = outputDeviceUID
        self.isBitPerfectMode = isBitPerfectMode
        self.sleepTimerMinutes = sleepTimerMinutes
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.preferredExternalSource = preferredExternalSource
        self.enableLRCLibLyrics = enableLRCLibLyrics
        self.enableNetEaseLyrics = enableNetEaseLyrics
        self.enableGroqLyrics = enableGroqLyrics
        self.groqLanguage = groqLanguage
        self.groqModel = groqModel
        self.writeCoverAndTagsToFile = writeCoverAndTagsToFile
        self.autoFindMissingCoversAndLyrics = autoFindMissingCoversAndLyrics
    }
    
    enum CodingKeys: String, CodingKey {
        case id, volume, crossfadeDuration, isGaplessEnabled, playbackSpeed, volumeNormalizationMode
        case isEQEnabled, eqPresetName, eqBandGains
        case appearanceMode, showMenuBarIcon, showNowPlayingBar
        case launchAtLogin, closeToMenuBar, showTrackChangeNotifications
        case outputDeviceUID, isBitPerfectMode, sleepTimerMinutes, hasCompletedOnboarding
        case preferredExternalSource
        case enableLRCLibLyrics, enableNetEaseLyrics
        case enableGroqLyrics, groqLanguage, groqModel
        case writeCoverAndTagsToFile, autoFindMissingCoversAndLyrics
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? AppConstants.Playback.defaultVolume
        self.crossfadeDuration = try container.decodeIfPresent(Double.self, forKey: .crossfadeDuration) ?? 0
        self.isGaplessEnabled = try container.decodeIfPresent(Bool.self, forKey: .isGaplessEnabled) ?? true
        self.playbackSpeed = try container.decodeIfPresent(Float.self, forKey: .playbackSpeed) ?? 1.0
        self.volumeNormalizationMode = try container.decodeIfPresent(String.self, forKey: .volumeNormalizationMode) ?? "off"
        self.isEQEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEQEnabled) ?? false
        self.eqPresetName = try container.decodeIfPresent(String.self, forKey: .eqPresetName) ?? ""
        self.eqBandGains = try container.decodeIfPresent([Float].self, forKey: .eqBandGains) ?? Array(repeating: 0.0, count: 10)
        self.appearanceMode = try container.decodeIfPresent(String.self, forKey: .appearanceMode) ?? "system"
        self.showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        self.showNowPlayingBar = try container.decodeIfPresent(Bool.self, forKey: .showNowPlayingBar) ?? true
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.closeToMenuBar = try container.decodeIfPresent(Bool.self, forKey: .closeToMenuBar) ?? false
        self.showTrackChangeNotifications = try container.decodeIfPresent(Bool.self, forKey: .showTrackChangeNotifications) ?? true
        self.outputDeviceUID = try container.decodeIfPresent(String.self, forKey: .outputDeviceUID)
        self.isBitPerfectMode = try container.decodeIfPresent(Bool.self, forKey: .isBitPerfectMode) ?? false
        self.sleepTimerMinutes = try container.decodeIfPresent(Int.self, forKey: .sleepTimerMinutes) ?? 0
        self.hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        self.preferredExternalSource = try container.decodeIfPresent(String.self, forKey: .preferredExternalSource) ?? "auto"
        self.enableLRCLibLyrics = try container.decodeIfPresent(Bool.self, forKey: .enableLRCLibLyrics) ?? true
        self.enableNetEaseLyrics = try container.decodeIfPresent(Bool.self, forKey: .enableNetEaseLyrics) ?? true
        self.enableGroqLyrics = try container.decodeIfPresent(Bool.self, forKey: .enableGroqLyrics) ?? false
        self.groqLanguage = try container.decodeIfPresent(String.self, forKey: .groqLanguage) ?? "Auto"
        self.groqModel = try container.decodeIfPresent(String.self, forKey: .groqModel) ?? "whisper-large-v3-turbo"
        self.writeCoverAndTagsToFile = try container.decodeIfPresent(Bool.self, forKey: .writeCoverAndTagsToFile) ?? false
        self.autoFindMissingCoversAndLyrics = try container.decodeIfPresent(Bool.self, forKey: .autoFindMissingCoversAndLyrics) ?? true
    }
    
    /// Creates default settings.
    static var defaults: AppSettings {
        AppSettings()
    }
}
