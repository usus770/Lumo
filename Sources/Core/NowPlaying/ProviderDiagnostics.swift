import Foundation
import os.log
import AppKit
import CoreServices
import Carbon

// MARK: - Subsystem Loggers (os.Logger)

public enum LumoLogger {
    public static let subsystem = "com.lumo.music"
    
    public static let systemNowPlaying = Logger(subsystem: subsystem, category: "system-nowplaying")
    public static let browserExtension = Logger(subsystem: subsystem, category: "browser-extension")
    public static let chrome = Logger(subsystem: subsystem, category: "chrome-applescript")
    public static let safari = Logger(subsystem: subsystem, category: "safari")
    public static let electron = Logger(subsystem: subsystem, category: "electron-app")
    public static let appleScript = Logger(subsystem: subsystem, category: "applescript")
    public static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
    public static let coordinator = Logger(subsystem: subsystem, category: "coordinator")
    
    public static func logger(for category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}

// Legacy wrapper to keep backward compatibility
struct NowPlayingLogger {
    static func debug(_ message: String, provider: String = "general") {
        LumoLogger.logger(for: provider).debug("\(message, privacy: .public)")
    }
    static func info(_ message: String, provider: String = "general") {
        LumoLogger.logger(for: provider).info("\(message, privacy: .public)")
    }
    static func warning(_ message: String, provider: String = "general") {
        LumoLogger.logger(for: provider).warning("\(message, privacy: .public)")
    }
    static func error(_ message: String, provider: String = "general") {
        LumoLogger.logger(for: provider).error("\(message, privacy: .public)")
    }
}

// MARK: - Provider Status

enum ProviderStatus: String, Codable, Sendable {
    case active = "Active"
    case available = "Available"
    case unavailable = "Unavailable"
    case permissionNeeded = "Permission Needed"
    case error = "Error"
    
    var systemImage: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        case .available: return "circle.fill"
        case .unavailable: return "xmark.circle.fill"
        case .permissionNeeded: return "exclamationmark.shield.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .active: return "green"
        case .available: return "blue"
        case .unavailable: return "gray"
        case .permissionNeeded: return "orange"
        case .error: return "red"
        }
    }
}

// MARK: - TCC Automation Permission

enum AutomationPermissionStatus: String, Codable, Sendable {
    case granted = "Granted"
    case denied = "Denied"
    case notDetermined = "Not Yet Asked"
    case targetNotRunning = "Not Running (Cannot Check)"
    case unknown = "Unknown"
    
    var description: String {
        switch self {
        case .granted:
            return "Automation permission granted ✓"
        case .denied:
            return "Automation permission denied — enable in System Settings > Privacy & Security > Automation"
        case .notDetermined:
            return "Not yet asked — macOS will prompt when automation is first requested"
        case .targetNotRunning:
            return "Target app is not currently running to verify automation consent"
        case .unknown:
            return "Unable to determine permission"
        }
    }
}

// MARK: - Safari Web App (PWA) Info

struct SafariWebAppDiagnosticInfo: Identifiable, Codable, Sendable, Hashable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let appPath: String
    let startURL: String?
    let isRunning: Bool
    let isYouTubeMusic: Bool
    let note: String
}

// MARK: - Detailed Provider Diagnostics

struct ProviderDiagnostics: Identifiable, Codable, Sendable, Hashable {
    let id: String // provider appName
    let providerType: String // class name
    var status: ProviderStatus
    var reason: String // plain English explanation
    var lastUpdate: Date?
    var lastError: String?
    var isRunning: Bool
    var isAvailable: Bool
    var requiresAppleEvents: Bool
    var appleEventsEnabled: Bool?
    var automationPermission: AutomationPermissionStatus?
    var bundleIdentifiers: [String]
    var lastState: ExternalPlayerStateSnapshot?
    
    init(
        id: String,
        providerType: String,
        status: ProviderStatus = .unavailable,
        reason: String = "",
        isRunning: Bool = false,
        isAvailable: Bool = false,
        requiresAppleEvents: Bool = false,
        bundleIdentifiers: [String] = []
    ) {
        self.id = id
        self.providerType = providerType
        self.status = status
        self.reason = reason
        self.isRunning = isRunning
        self.isAvailable = isAvailable
        self.requiresAppleEvents = requiresAppleEvents
        self.bundleIdentifiers = bundleIdentifiers
    }
    
    static func == (lhs: ProviderDiagnostics, rhs: ProviderDiagnostics) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Player State Snapshot

struct ExternalPlayerStateSnapshot: Codable, Sendable {
    let isPlaying: Bool
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: TimeInterval
    let currentTime: TimeInterval
    let appName: String
    let timestamp: Date
    
    init(from state: ExternalPlayerState) {
        self.isPlaying = state.isPlaying
        self.trackName = state.trackName
        self.artistName = state.artistName
        self.albumName = state.albumName
        self.duration = state.duration
        self.currentTime = state.currentTime
        self.appName = state.appName
        self.timestamp = Date()
    }
}

// MARK: - Native Automation Permission Helper

enum AutomationPermissionChecker {
    /// Checks macOS TCC automation permission using AEDeterminePermissionToAutomateTarget
    /// without showing a modal prompt (askUserIfNeeded: false).
    static func check(targetBundleID: String) -> AutomationPermissionStatus {
        var target = AEAddressDesc()
        let data = Array(targetBundleID.utf8)
        let createStatus = data.withUnsafeBytes { rawBuffer in
            AECreateDesc(typeApplicationBundleID, rawBuffer.baseAddress, rawBuffer.count, &target)
        }
        
        guard createStatus == noErr else {
            LumoLogger.diagnostics.error("AECreateDesc failed with OSStatus \(createStatus) for \(targetBundleID, privacy: .public)")
            return .unknown
        }
        defer { AEDisposeDesc(&target) }
        
        let status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
        LumoLogger.diagnostics.debug("AEDeterminePermissionToAutomateTarget for \(targetBundleID, privacy: .public): \(status)")
        
        switch Int(status) {
        case Int(noErr):
            return .granted
        case errAEEventNotPermitted: // -1743
            return .denied
        case errAEEventWouldRequireUserConsent: // -1744
            return .notDetermined
        case procNotFound: // -600
            // App is not running right now
            return .targetNotRunning
        default:
            return .unknown
        }
    }
    
    /// Explicitly requests macOS TCC automation permission using AEDeterminePermissionToAutomateTarget
    /// by showing the native OS permission modal prompt (askUserIfNeeded: true).
    @discardableResult
    static func request(targetBundleID: String) -> AutomationPermissionStatus {
        var target = AEAddressDesc()
        let data = Array(targetBundleID.utf8)
        let createStatus = data.withUnsafeBytes { rawBuffer in
            AECreateDesc(typeApplicationBundleID, rawBuffer.baseAddress, rawBuffer.count, &target)
        }
        guard createStatus == noErr else {
            LumoLogger.diagnostics.error("AECreateDesc failed with OSStatus \(createStatus) for \(targetBundleID, privacy: .public)")
            return .unknown
        }
        defer { AEDisposeDesc(&target) }
        
        let status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, true)
        LumoLogger.diagnostics.info("AEDeterminePermissionToAutomateTarget (requested) for \(targetBundleID, privacy: .public): \(status)")
        
        switch Int(status) {
        case Int(noErr):
            return .granted
        case errAEEventNotPermitted:
            return .denied
        case errAEEventWouldRequireUserConsent:
            return .notDetermined
        case procNotFound:
            return .targetNotRunning
        default:
            return .unknown
        }
    }
}

// MARK: - Safari Web App Detector

enum SafariWebAppDetector {
    /// Scans ~/Applications for Safari Web Apps (PWAs)
    static func detectInstalledWebApps() -> [SafariWebAppDiagnosticInfo] {
        var results: [SafariWebAppDiagnosticInfo] = []
        let fileManager = FileManager.default
        let homeAppURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        
        guard let items = try? fileManager.contentsOfDirectory(at: homeAppURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return results
        }
        
        let runningApps = NSWorkspace.shared.runningApplications
        
        for item in items where item.pathExtension == "app" {
            let plistURL = item.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                continue
            }
            
            let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
            let bundleName = plist["CFBundleName"] as? String ?? item.deletingPathExtension().lastPathComponent
            let templateParams = plist["LSTemplateApplicationParameters"] as? [String: Any]
            let isSafariWebApp = bundleID.hasPrefix("com.apple.Safari.WebApp.") || templateParams?["CFBundleIdentifier"] as? String == "com.apple.Safari.WebApp"
            
            if isSafariWebApp {
                var startURL: String? = nil
                var isYTM = false
                if let manifest = plist["Manifest"] as? [String: Any] {
                    startURL = manifest["start_url"] as? String
                    if let start = startURL?.lowercased(), start.contains("music.youtube.com") {
                        isYTM = true
                    }
                    if let name = manifest["name"] as? String, name.lowercased().contains("youtube music") {
                        isYTM = true
                    }
                }
                if bundleName.lowercased().contains("yt music") || bundleName.lowercased().contains("youtube music") {
                    isYTM = true
                }
                
                let isRunning = runningApps.contains { app in
                    app.bundleIdentifier == bundleID || (app.bundleIdentifier?.hasPrefix("com.apple.Safari.WebApp.") == true && app.localizedName == bundleName)
                }
                
                let note = "Covered by System Now Playing provider (MediaRemote captures navigator.mediaSession metadata system-wide with no browser settings or Apple Events required)."
                
                results.append(SafariWebAppDiagnosticInfo(
                    name: bundleName,
                    bundleIdentifier: bundleID,
                    appPath: item.path,
                    startURL: startURL,
                    isRunning: isRunning,
                    isYouTubeMusic: isYTM,
                    note: note
                ))
            }
        }
        
        return results
    }
}

// MARK: - Diagnostics Collector

@Observable
final class ProviderDiagnosticsCollector: @unchecked Sendable {
    static let shared = ProviderDiagnosticsCollector()
    
    var diagnostics: [ProviderDiagnostics] = []
    var safariWebApps: [SafariWebAppDiagnosticInfo] = []
    var isChromeInstalled: Bool = false
    var isChromeRunning: Bool = false
    var chromeAppleEventsEnabled: Bool? = nil
    var chromeAppleEventsDetail: String = ""
    var lastRefreshed: Date? = nil
    
    private init() {}
    
    /// Update diagnostics for a provider
    func updateDiagnostics(_ newDiag: ProviderDiagnostics) {
        if let idx = diagnostics.firstIndex(where: { $0.id == newDiag.id }) {
            diagnostics[idx] = newDiag
        } else {
            diagnostics.append(newDiag)
        }
    }
    
    /// Refresh all diagnostics including system environment checks
    func refreshAll(providers: [NowPlayingProvider]) async {
        LumoLogger.diagnostics.info("Starting diagnostics refresh across \(providers.count) providers")
        
        // 1. Detect Safari Web Apps
        self.safariWebApps = SafariWebAppDetector.detectInstalledWebApps()
        LumoLogger.diagnostics.info("Detected \(self.safariWebApps.count) Safari Web App(s)")
        
        // 2. Check Chrome environment
        await checkChromeEnvironment()
        
        // 3. Refresh each provider
        for provider in providers {
            await refreshDiagnostics(for: provider)
        }
        
        await MainActor.run {
            self.lastRefreshed = Date()
        }
        LumoLogger.diagnostics.info("Diagnostics refresh complete")
    }
    
    private func checkChromeEnvironment() async {
        isChromeInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil
        isChromeRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.google.Chrome" }
        
        if isChromeRunning {
            let (enabled, detail) = await testChromeAppleEvents()
            chromeAppleEventsEnabled = enabled
            chromeAppleEventsDetail = detail
            LumoLogger.chrome.info("Chrome Apple Events status: enabled=\(enabled), detail=\(detail, privacy: .public)")
        } else {
            chromeAppleEventsEnabled = nil
            chromeAppleEventsDetail = isChromeInstalled ? "Chrome is installed but not currently running" : "Google Chrome is not installed"
        }
    }
    
    private func testChromeAppleEvents() async -> (Bool, String) {
        let script = """
        tell application "Google Chrome"
            if not running then return "not_running"
            try
                execute front window's active tab javascript "1"
                return "enabled"
            on error errMsg number errNum
                return "error:" & errNum & ":" & errMsg
            end try
        end tell
        """
        
        guard let output = await runAppleScript(script) else {
            return (false, "Could not communicate with Google Chrome")
        }
        
        if output == "enabled" {
            return (true, "JavaScript execution from Apple Events is active and operational.")
        }
        
        if output.contains(":12:") || output.contains("turned off") || output.contains("Apple Events") {
            return (false, "Turned off (Error 12): 'Allow JavaScript from Apple Events' is disabled in Chrome (View > Developer > Allow JavaScript from Apple Events).")
        }
        
        if output.contains(":-1743:") {
            return (false, "Permission denied (Error -1743): macOS Automation permission is denied for Google Chrome.")
        }
        
        // If there are no open windows or tabs, try a harmless one-shot test tab
        if output.contains("window") || output.contains("tab") {
            let windowlessScript = """
            tell application "Google Chrome"
                try
                    set w to make new window
                    set res to "enabled"
                    try
                        execute active tab of w javascript "1"
                    on error errMsg number errNum
                        set res to "error:" & errNum & ":" & errMsg
                    end try
                    close w
                    return res
                on error e
                    return "error:-1:" & e
                end try
            end tell
            """
            if let windowlessOutput = await runAppleScript(windowlessScript) {
                if windowlessOutput == "enabled" {
                    return (true, "JavaScript execution from Apple Events is enabled.")
                }
                if windowlessOutput.contains(":12:") || windowlessOutput.contains("turned off") {
                    return (false, "Turned off (Error 12): 'Allow JavaScript from Apple Events' is disabled in Chrome.")
                }
            }
        }
        
        return (false, output)
    }
    
    private func refreshDiagnostics(for provider: NowPlayingProvider) async {
        let bundleIDs = await getBundleIdentifiers(for: provider)
        let isRunning = await checkIsRunning(provider, bundleIDs: bundleIDs)
        let requiresAE = providerRequiresAppleEvents(provider)
        
        var diag = ProviderDiagnostics(
            id: provider.appName,
            providerType: String(describing: type(of: provider)),
            isRunning: isRunning,
            isAvailable: provider.isAvailable,
            requiresAppleEvents: requiresAE,
            bundleIdentifiers: bundleIDs
        )
        
        // Check TCC Automation permission if target bundles exist
        if let primaryBundleID = bundleIDs.first {
            let perm = AutomationPermissionChecker.check(targetBundleID: primaryBundleID)
            diag.automationPermission = perm
            if perm == .denied {
                diag.status = .permissionNeeded
                diag.reason = "macOS Automation (TCC) permission denied for \(primaryBundleID). Enable in System Settings > Privacy & Security > Automation."
            }
        }
        
        // Special check for Chrome AppleScript provider
        if provider.appName.contains("Chrome") && requiresAE {
            diag.appleEventsEnabled = self.chromeAppleEventsEnabled
            if self.chromeAppleEventsEnabled == false {
                diag.status = .permissionNeeded
                diag.reason = "Chrome 'Allow JavaScript from Apple Events' is disabled. Go to Chrome menu bar > View > Developer > Allow JavaScript from Apple Events."
            }
        }
        
        // Status resolution
        if diag.status != .permissionNeeded {
            if !diag.isAvailable {
                diag.status = .unavailable
                diag.reason = "Provider reports unavailable on this system."
            } else if requiresAE && !isRunning {
                diag.status = .unavailable
                diag.reason = "Target application is not running."
            } else if isRunning || !requiresAE {
                diag.status = .available
                diag.reason = "Ready and monitoring for playback."
            }
        }
        
        // Check current playback state
        if diag.isAvailable {
            if let state = await provider.fetchState() {
                diag.lastState = ExternalPlayerStateSnapshot(from: state)
                diag.lastUpdate = Date()
                if state.isPlaying {
                    diag.status = .active
                    let trackTitle = state.trackName ?? "Unknown track"
                    let artistTitle = state.artistName ?? state.appName
                    diag.reason = "Actively playing: \"\(trackTitle)\" by \(artistTitle)"
                }
            } else if diag.status == .active {
                diag.status = .available
                diag.reason = "Playback paused or idle."
            }
        }
        
        LumoLogger.diagnostics.info("Provider [\(provider.appName, privacy: .public)] status: \(diag.status.rawValue, privacy: .public) - \(diag.reason, privacy: .public)")
        
        let finalDiag = diag
        await MainActor.run {
            self.updateDiagnostics(finalDiag)
        }
    }
    
    private func checkIsRunning(_ provider: NowPlayingProvider, bundleIDs: [String]) async -> Bool {
        if bundleIDs.isEmpty {
            return true // System-wide providers don't target a single app
        }
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { app in
            guard let appID = app.bundleIdentifier else { return false }
            return bundleIDs.contains { target in
                appID == target || appID.hasPrefix(target)
            }
        }
    }
    
    private func providerRequiresAppleEvents(_ provider: NowPlayingProvider) -> Bool {
        let typeName = String(describing: type(of: provider))
        return typeName.contains("AppleScript") || typeName.contains("ChromeYouTubeMusic")
    }
    
    private func getBundleIdentifiers(for provider: NowPlayingProvider) async -> [String] {
        return provider.bundleIdentifiers
    }
    
    private func runAppleScript(_ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - NowPlayingProvider Default Implementations

extension NowPlayingProvider {
    var bundleIdentifiers: [String] { [] }
}