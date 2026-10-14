import Foundation
import AppKit

/// Manages multiple now-playing providers and selects the best available one.
/// Priority: ExternalNowPlaying (covers all) > MediaRemote > App-specific > Fallback
@Observable
final class NowPlayingProviderManager: @unchecked Sendable {
    static let shared = NowPlayingProviderManager()
    
    // Providers in priority order: BrowserExtension > Electron app > SystemNowPlaying > Chrome AppleScript
    private let providers: [NowPlayingProvider] = {
        var p: [NowPlayingProvider] = []
        
        // 1. Companion Browser Extension (highest fidelity, no Apple Events needed)
        p.append(BrowserExtensionProvider())
        
        // 2. Standalone Electron App
        p.append(YouTubeMusicAppProvider())
        
        // 3. System Now Playing (covers Safari Web App PWAs, Safari tabs, Chrome, Brave, Edge, Arc)
        p.append(SystemNowPlayingProvider())
        
        // 4. Native App Scripting (Apple Music, Spotify, VLC)
        p.append(AppleScriptProvider(appName: "Music", bundleID: "com.apple.Music"))
        p.append(AppleScriptProvider(appName: "Spotify", bundleID: "com.spotify.client"))
        p.append(AppleScriptProvider(appName: "VLC", bundleID: "org.videolan.vlc"))
        
        // 5. Chrome AppleScript fallback
        p.append(ChromeYouTubeMusicProvider())
        
        return p
    }()
    
    /// All registered providers (for diagnostics)
    var allProviders: [NowPlayingProvider] { providers }
    
    private var activeProvider: NowPlayingProvider?
    private var activeState: ExternalPlayerState?
    private var pollTimerTask: Task<Void, Never>?
    
    private init() {
        Task {
            await NowPlayingCoordinator.shared.registerProviders(self.providers)
        }
    }
    
    var currentState: ExternalPlayerState? {
        activeState
    }
    var currentProviderName: String? {
        activeProvider?.appName
    }
    
    /// Starts monitoring with the best available provider and starts coordinator arbitration.
    func startMonitoring() {
        Task {
            await NowPlayingCoordinator.shared.registerProviders(self.providers)
            await NowPlayingCoordinator.shared.start()
        }
    }
    
    func stopMonitoring() {
        Task {
            await NowPlayingCoordinator.shared.stop()
        }
        activeProvider = nil
        pollTimerTask?.cancel()
        pollTimerTask = nil
    }
    
    private func startPollingFallback() {
        pollTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollAllProviders()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
    }
    
    private func pollAllProviders() async {
        for provider in providers {
            guard provider.isAvailable else { continue }
            
            var shouldCheck = false
            if let scriptProvider = provider as? AppleScriptProvider {
                shouldCheck = scriptProvider.isRunning
            } else if let chromeProvider = provider as? ChromeYouTubeMusicProvider {
                shouldCheck = chromeProvider.isRunning
            } else if let ytProvider = provider as? YouTubeMusicAppProvider {
                shouldCheck = ytProvider.isRunning
            }
            
            if shouldCheck {
                if let state = await provider.fetchState() {
                    await NowPlayingCoordinator.shared.handleProviderUpdate(provider: provider, state: state)
                    await MainActor.run {
                        self.handleStateUpdate(state, from: provider)
                    }
                }
            }
        }
    }
    
    private func handleStateUpdate(_ state: ExternalPlayerState, from provider: NowPlayingProvider) {
        if activeProvider == nil || activeProvider === provider || state.isPlaying {
            activeProvider = provider
            activeState = state
            self.notifyObservers()
        }
    }
    
    // MARK: - Playback Control
    
    func playPause() {
        Task {
            await NowPlayingCoordinator.shared.playPause()
        }
        activeProvider?.playPause()
    }
    
    func nextTrack() {
        Task {
            await NowPlayingCoordinator.shared.nextTrack()
        }
        activeProvider?.nextTrack()
    }
    
    func previousTrack() {
        Task {
            await NowPlayingCoordinator.shared.previousTrack()
        }
        activeProvider?.previousTrack()
    }
    
    func seek(to time: TimeInterval) {
        Task {
            await NowPlayingCoordinator.shared.seek(to: time)
        }
        activeProvider?.seek(to: time)
    }
    
    /// Returns the source app name for display (e.g., "Apple Music", "Spotify")
    var sourceAppName: String? {
        activeState?.appName
    }
    
    /// Returns the source app icon if available
    var sourceAppIcon: NSImage? {
        guard let bundleID = activeState?.bundleIdentifier else { return nil }
        return NSWorkspace.shared.icon(forFile: bundleID)
    }
}

// MARK: - Provider Delegate

extension NowPlayingProviderManager: NowPlayingProviderDelegate {
    func nowPlayingProvider(_ provider: NowPlayingProvider, didUpdateState state: ExternalPlayerState?) {
        if let state = state {
            handleStateUpdate(state, from: provider)
        } else if activeProvider === provider {
            // Provider says nothing is playing, check others
            Task { await pollAllProviders() }
        }
    }
}

// MARK: - App-Specific Providers

/// Generic AppleScript-based provider for scriptable apps (Music, Spotify, VLC, etc.)
final class AppleScriptProvider: NowPlayingProvider, @unchecked Sendable {
    let appName: String
    let bundleID: String
    weak var delegate: NowPlayingProviderDelegate?
    
    init(appName: String, bundleID: String) {
        self.appName = appName
        self.bundleID = bundleID
    }
    
    var isAvailable: Bool { true }
    var bundleIdentifiers: [String] { [bundleID] }
    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }
    
    func startMonitoring() {
        // AppleScript providers use polling via the manager
    }
    
    func stopMonitoring() {}
    
    func fetchAndNotify() {
        Task {
            if let state = await fetchState() {
                await MainActor.run {
                    delegate?.nowPlayingProvider(self, didUpdateState: state)
                }
            }
        }
    }
    
    func fetchState() async -> ExternalPlayerState? {
        guard isRunning else { return nil }
        
        let script = """
        if application "\(appName)" is running then
            tell application "\(appName)"
                try
                    set pState to player state as string
                    set tName to name of current track as string
                    set tArtist to artist of current track as string
                    set tAlbum to album of current track as string
                    set tDuration to duration of current track as string
                    set tTime to player position as string
                    return pState & "|!|" & tName & "|!|" & tArtist & "|!|" & tAlbum & "|!|" & tDuration & "|!|" & tTime
                on error
                    return "error"
                end try
            end tell
        else
            return "not running"
        end if
        """
        
        let output = await runAppleScript(script)
        guard let output = output, output != "error", output != "not running" else {
            return nil
        }
        
        let components = output.components(separatedBy: "|!|")
        guard components.count >= 6 else { return nil }
        
        let isPlaying = components[0].lowercased() == "playing"
        let trackName = components[1]
        let artistName = components[2]
        let albumName = components[3]
        
        let rawDuration = Double(components[4]) ?? 0
        let duration = appName == "Spotify" ? (rawDuration > 1000 ? rawDuration / 1000 : rawDuration) : rawDuration
        let currentTime = Double(components[5]) ?? 0
        
        // Fetch artwork for Music app
        var artworkData: Data? = nil
        if appName == "Music" {
            let artScript = """
            tell application "Music"
                try
                    set artData to raw data of artwork 1 of current track
                    return artData
                on error
                    return ""
                end try
            end tell
            """
            if let scriptObj = NSAppleScript(source: artScript) {
                var error: NSDictionary?
                let desc = scriptObj.executeAndReturnError(&error)
                if error == nil {
                    artworkData = desc.data
                }
            }
        }
        
        return ExternalPlayerState(
            isPlaying: isPlaying,
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            duration: duration,
            currentTime: currentTime,
            artworkData: artworkData,
            appName: appName
        )
    }
    
    func playPause() {
        Task { await runAppleScript("tell application \"\(appName)\" to playpause") }
    }
    
    func nextTrack() {
        Task { await runAppleScript("tell application \"\(appName)\" to next track") }
    }
    
    func previousTrack() {
        Task { await runAppleScript("tell application \"\(appName)\" to previous track") }
    }
    
    func seek(to time: TimeInterval) {
        Task { await runAppleScript("tell application \"\(appName)\" to set player position to \(time)") }
    }
    
    @discardableResult
    private func runAppleScript(_ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(returning: nil)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}

/// Provider for YouTube Music (standalone app, Electron, Safari/Chrome Web Apps)
/// Tries multiple known bundle identifiers and app names for YouTube Music
final class YouTubeMusicAppProvider: NowPlayingProvider, @unchecked Sendable {
    let appName = "YouTube Music (Electron)"
    weak var delegate: NowPlayingProviderDelegate?
    
    // Known bundle identifiers for standalone Electron apps
    private let knownBundleIdentifiers = [
        "com.github.th-ch.youtube-music",
        "com.google.youtube.music",
        "com.youtube.music",
        "com.google.YouTubeMusic",
        "com.youtube.YouTubeMusic"
    ]
    
    // App names to try in AppleScript
    private let appNames = [
        "YouTube Music",
        "yt music",
        "YT Music",
        "YouTubeMusic"
    ]
    
    var isAvailable: Bool { true }
    var bundleIdentifiers: [String] { knownBundleIdentifiers }
    var isRunning: Bool {
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier?.lowercased() else { continue }
            // Explicitly exclude all browsers and browser-based PWAs
            if bid.hasPrefix("com.apple.") || bid.hasPrefix("com.google.chrome") ||
               bid.hasPrefix("company.thebrowser.") || bid.hasPrefix("com.brave.") ||
               bid.hasPrefix("com.microsoft.edgemac") {
                continue
            }
            if knownBundleIdentifiers.contains(where: { bid == $0.lowercased() || bid.hasPrefix($0.lowercased()) }) {
                return true
            }
            if let name = app.localizedName?.lowercased(), name == "electron" {
                return true
            }
        }
        return false
    }
    
    private func runAppleScriptSync(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    
    func startMonitoring() {}
    func stopMonitoring() {}
    
    func fetchAndNotify() {
        Task {
            if let state = await fetchState() {
                await MainActor.run {
                    delegate?.nowPlayingProvider(self, didUpdateState: state)
                }
            }
        }
    }
    
    func fetchState() async -> ExternalPlayerState? {
        NSLog("[YouTubeMusicAppProvider] fetchState called, isRunning: \(isRunning)")
        
        guard isRunning else { 
            NSLog("[YouTubeMusicAppProvider] App not running")
            return nil 
        }
        
        // Debug: print all running apps with "youtube" or "music" in name
        let runningApps = NSWorkspace.shared.runningApplications
        var detectedAppName: String? = nil
        var detectedBundleID: String? = nil
        
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier?.lowercased() else { continue }
            if bundleID.hasPrefix("com.apple.") || bundleID.hasPrefix("com.google.chrome") ||
               bundleID.hasPrefix("company.thebrowser.") || bundleID.hasPrefix("com.brave.") ||
               bundleID.hasPrefix("com.microsoft.edgemac") {
                continue
            }
            if let name = app.localizedName?.lowercased() {
                if name.contains("youtube music") || name == "yt music" || name == "ytmusic" {
                    detectedAppName = name
                    detectedBundleID = bundleID
                    break
                }
            }
        }
        _ = detectedBundleID
        
        // Try AppleScript with detected app name, then fallback names
        let namesToTry = [detectedAppName].compactMap { $0 } + appNames
        
        for appName in namesToTry {
            let script = """
            if application "\(appName)" is running then
                tell application "\(appName)"
                    try
                        set pState to player state as string
                        set tName to name of current track as string
                        set tArtist to artist of current track as string
                        set tAlbum to album of current track as string
                        set tDuration to duration of current track as string
                        set tTime to player position as string
                        return pState & "|!|" & tName & "|!|" & tArtist & "|!|" & tAlbum & "|!|" & tDuration & "|!|" & tTime
                    on error
                        return "error"
                    end try
                end tell
            else
                return "not running"
            end if
            """
            
            let output = await runAppleScript(script)
            
            if let output = output, output != "error", output != "not running" {
                let components = output.components(separatedBy: "|!|")
                if components.count >= 6 {
                    let isPlaying = components[0].lowercased() == "playing"
                    let trackName = components[1]
                    let artistName = components[2]
                    let albumName = components[3]
                    let rawDuration = Double(components[4]) ?? 0
                    let duration = rawDuration > 1000 ? rawDuration / 1000 : rawDuration
                    let currentTime = Double(components[5]) ?? 0
                    
                    return ExternalPlayerState(
                        isPlaying: isPlaying,
                        trackName: trackName.isEmpty ? "Unknown" : trackName,
                        artistName: artistName,
                        albumName: albumName,
                        duration: duration,
                        currentTime: currentTime,
                        artworkData: nil,
                        appName: "YouTube Music"
                    )
                }
            }
        }
        
        // Fallback: Try JavaScript injection via AppleScript (if app exposes web contents)
        return await fetchStateViaJavaScript()
    }
    
    private func fetchStateViaJavaScript() async -> ExternalPlayerState? {
        let js = """
        try {
            var v = document.querySelector('video');
            var m = navigator.mediaSession.metadata;
            var isP = !v.paused;
            var t = m ? m.title : '';
            var a = m ? m.artist : '';
            var al = m ? m.album : '';
            var d = v.duration || 0;
            var c = v.currentTime || 0;
            (isP ? 'playing' : 'paused') + '|!|' + t + '|!|' + a + '|!|' + al + '|!|' + d + '|!|' + c;
        } catch(e) { 'error'; }
        """
        
        // Get detected bundle IDs from running Electron apps (strictly excluding browsers)
        let runningApps = NSWorkspace.shared.runningApplications
        var detectedBundleIDs: [String] = []
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier?.lowercased() else { continue }
            if bundleID.hasPrefix("com.apple.") || bundleID.hasPrefix("com.google.chrome") ||
               bundleID.hasPrefix("company.thebrowser.") || bundleID.hasPrefix("com.brave.") ||
               bundleID.hasPrefix("com.microsoft.edgemac") {
                continue
            }
            if knownBundleIdentifiers.contains(where: { bundleID == $0.lowercased() || bundleID.hasPrefix($0.lowercased()) }) {
                detectedBundleIDs.append(bundleID)
            }
        }
        
        // Try detected bundle IDs first, then known ones
        let bundleIDsToTry = Array(Set(detectedBundleIDs + bundleIdentifiers))
        
        // Try to find the YouTube Music app window and inject JS
        for bundleID in bundleIDsToTry {
            let script = """
            tell application id "\(bundleID)"
                if not running then return "not running"
                try
                    -- Try to execute JavaScript in the main window
                    tell front window
                        execute javascript "\(js.replacingOccurrences(of: "\"", with: "\\\""))"
                    end tell
                on error
                    return "error"
                end try
            end tell
            """
            
            let output = await runAppleScript(script)
            NSLog("[YouTubeMusicAppProvider] JS injection for \(bundleID): \(output ?? "nil")")
            
            guard let output = output, output != "error", output != "not running", !output.isEmpty, output != "missing value" else {
                continue
            }
            
            let components = output.components(separatedBy: "|!|")
            guard components.count >= 6 else { continue }
            
            return ExternalPlayerState(
                isPlaying: components[0] == "playing",
                trackName: components[1].isEmpty ? "Unknown" : components[1],
                artistName: components[2],
                albumName: components[3],
                duration: Double(components[4]) ?? 0,
                currentTime: Double(components[5]) ?? 0,
                artworkData: nil,
                appName: "YouTube Music"
            )
        }
        
        return nil
    }
    
    func playPause() {
        Task { await executeCommand("playpause") }
    }
    
    func nextTrack() {
        Task { await executeCommand("next track") }
    }
    
    func previousTrack() {
        Task { await executeCommand("previous track") }
    }
    
    func seek(to time: TimeInterval) {
        Task { await executeCommand("set player position to \(time)") }
    }
    
    private func executeCommand(_ command: String) async {
        // Try AppleScript command with all known app names
        for appName in appNames {
            let script = """
            if application "\(appName)" is running then
                tell application "\(appName)" to \(command)
            end if
            """
            await runAppleScript(script)
        }
        
        // Also try bundle ID approach
        for bundleID in bundleIdentifiers {
            let bundleScript = """
            tell application id "\(bundleID)"
                if running then \(command)
            end tell
            """
            await runAppleScript(bundleScript)
        }
    }
    
    @discardableResult
    private func runAppleScript(_ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(returning: nil)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}