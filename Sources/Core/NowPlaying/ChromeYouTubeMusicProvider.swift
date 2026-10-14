import Foundation
import AppKit
import OSLog

/// State of Chrome's "Allow JavaScript from Apple Events" setting
enum ChromeAppleEventsState: Sendable, Equatable {
    case enabled
    case disabled(errorText: String)
    case permissionDenied
    case browserNotRunning
    case browserNotInstalled
    case unknown
    
    var isOperational: Bool {
        if case .enabled = self { return true }
        return false
    }
}

/// Fallback provider for YouTube Music in Google Chrome, Brave, Edge, and Arc
/// using JavaScript injection via Apple Events.
///
/// Note: This is a lower-priority fallback compared to BrowserExtensionProvider
/// and SystemNowPlayingProvider because it requires Chrome's "Allow JavaScript from Apple Events" setting.
final class ChromeYouTubeMusicProvider: NowPlayingProvider, @unchecked Sendable {
    
    // MARK: - Supported Chromium Targets
    
    struct ChromiumApp: Sendable {
        let bundleID: String
        let appName: String
    }
    
    static let supportedBrowsers: [ChromiumApp] = [
        ChromiumApp(bundleID: "com.google.Chrome", appName: "Google Chrome"),
        ChromiumApp(bundleID: "com.brave.Browser", appName: "Brave Browser"),
        ChromiumApp(bundleID: "com.microsoft.edgemac", appName: "Microsoft Edge"),
        ChromiumApp(bundleID: "company.thebrowser.Browser", appName: "Arc")
    ]
    
    // MARK: - Properties
    
    weak var delegate: NowPlayingProviderDelegate?
    
    let appName = "YouTube Music (Chrome AppleScript)"
    
    var bundleIdentifiers: [String] {
        Self.supportedBrowsers.map { $0.bundleID }
    }
    
    var isRunning: Bool {
        activeBrowser != nil
    }
    
    var isAvailable: Bool {
        isInstalled && preflightState.isOperational
    }
    
    var isInstalled: Bool {
        Self.supportedBrowsers.contains {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }
    }
    
    private(set) var preflightState: ChromeAppleEventsState = .unknown
    private var lastFetchTime: Date = .distantPast
    private var lastKnownState: ExternalPlayerState?
    private var isMonitoring = false
    private var pollTask: Task<Void, Never>?
    
    private var activeBrowser: ChromiumApp? {
        let runningApps = NSWorkspace.shared.runningApplications
        for target in Self.supportedBrowsers {
            if runningApps.contains(where: { $0.bundleIdentifier == target.bundleID }) {
                return target
            }
        }
        return nil
    }
    
    // MARK: - Initialization & Preflight
    
    init() {
        Task { await runPreflight() }
        
        // Auto-recheck on app activation
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.runPreflight() }
        }
    }
    
    deinit {
        stopMonitoring()
    }
    
    @discardableResult
    func runPreflight() async -> ChromeAppleEventsState {
        guard let browser = activeBrowser else {
            let state: ChromeAppleEventsState = isInstalled ? .browserNotRunning : .browserNotInstalled
            self.preflightState = state
            return state
        }
        
        let testScript = """
        tell application "\(browser.appName)"
            if not running then return "not_running"
            try
                execute front window's active tab javascript "1"
                return "enabled"
            on error errMsg number errNum
                return "err:" & errNum & ":" & errMsg
            end try
        end tell
        """
        
        guard let output = await AppleScriptRunner.shared.run(script: testScript, timeout: 2.0) else {
            self.preflightState = .unknown
            return .unknown
        }
        
        if output == "enabled" {
            self.preflightState = .enabled
            LumoLogger.chrome.info("Preflight check passed: Apple Events JS enabled in \(browser.appName, privacy: .public)")
            return .enabled
        }
        
        if output.contains("12") || output.contains("turned off") || output.contains("Apple Events") {
            let state = ChromeAppleEventsState.disabled(errorText: output)
            self.preflightState = state
            LumoLogger.chrome.warning("Preflight check failed (Error 12): JavaScript from Apple Events is turned off in \(browser.appName, privacy: .public)")
            return state
        }
        
        if output.contains("-1743") {
            self.preflightState = .permissionDenied
            LumoLogger.chrome.warning("Preflight check failed (-1743): Automation permission denied for \(browser.appName, privacy: .public)")
            return .permissionDenied
        }
        
        self.preflightState = .disabled(errorText: output)
        return self.preflightState
    }
    
    // MARK: - "Enable For Me" Policy Helper
    
    /// Configures `defaults write com.google.Chrome AllowJavaScriptAppleEvents -bool true`
    /// and verifies the written policy setting.
    static func enableChromeAppleEventsPolicy() -> Bool {
        let writeProcess = Process()
        writeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        writeProcess.arguments = ["write", "com.google.Chrome", "AllowJavaScriptAppleEvents", "-bool", "true"]
        try? writeProcess.run()
        writeProcess.waitUntilExit()
        
        // Verify
        let readProcess = Process()
        readProcess.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        readProcess.arguments = ["read", "com.google.Chrome", "AllowJavaScriptAppleEvents"]
        let pipe = Pipe()
        readProcess.standardOutput = pipe
        try? readProcess.run()
        readProcess.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result == "1"
    }
    
    // MARK: - State Fetching
    
    func fetchState() async -> ExternalPlayerState? {
        guard let browser = activeBrowser else { return nil }
        
        // Respect rate limit: 1 Hz playing, 0.2 Hz (5s) paused
        let now = Date()
        let isPlaying = lastKnownState?.isPlaying ?? false
        let minInterval: TimeInterval = isPlaying ? 0.9 : 4.5
        if now.timeIntervalSince(lastFetchTime) < minInterval, let cached = lastKnownState {
            return cached
        }
        lastFetchTime = now
        
        // Preflight verification if unknown
        if preflightState == .unknown {
            _ = await runPreflight()
            if !preflightState.isOperational { return nil }
        }
        
        let js = """
        (function() {
            try {
                var v = document.querySelector('video');
                var m = navigator.mediaSession ? navigator.mediaSession.metadata : null;
                var isP = v ? !v.paused : false;
                var t = m ? m.title : (document.querySelector('ytmusic-player-bar .title') ? document.querySelector('ytmusic-player-bar .title').innerText : '');
                var a = m ? m.artist : (document.querySelector('ytmusic-player-bar .byline') ? document.querySelector('ytmusic-player-bar .byline').innerText : '');
                var al = m ? m.album : '';
                var d = v ? v.duration || 0 : 0;
                var c = v ? v.currentTime || 0 : 0;
                return (isP ? 'playing' : 'paused') + '|!|' + t + '|!|' + a + '|!|' + al + '|!|' + d + '|!|' + c;
            } catch(e) {
                return 'error';
            }
        })();
        """
        
        let script = """
        tell application "\(browser.appName)"
            if not running then return "not running"
            set foundTab to false
            set res to "error"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabURL to URL of t
                    if tabURL contains "music.youtube.com" then
                        try
                            set res to execute t javascript "\(js.replacingOccurrences(of: "\"", with: "\\\""))"
                            set foundTab to true
                            exit repeat
                        on error errMsg number errNum
                            return "err:" & errNum & ":" & errMsg
                        end try
                    end if
                end repeat
                if foundTab then exit repeat
            end repeat
            return res
        end tell
        """
        
        guard let output = await AppleScriptRunner.shared.run(script: script, timeout: 2.5) else {
            return nil
        }
        
        if output.contains("12") || output.contains("turned off") {
            preflightState = .disabled(errorText: output)
            return nil
        }
        
        guard !output.isEmpty, output != "error", output != "not running", output != "missing value" else {
            return nil
        }
        
        let components = output.components(separatedBy: "|!|")
        guard components.count >= 6 else { return nil }
        
        let state = ExternalPlayerState(
            isPlaying: components[0] == "playing",
            trackName: components[1].isEmpty ? "Unknown" : components[1],
            artistName: components[2],
            albumName: components[3],
            duration: Double(components[4]) ?? 0,
            currentTime: Double(components[5]) ?? 0,
            artworkData: nil,
            appName: "YouTube Music",
            sourceBundleIdentifier: browser.bundleID,
            sourceURL: "https://music.youtube.com",
            playbackRate: 1.0,
            lastUpdated: Date()
        )
        
        self.lastKnownState = state
        return state
    }
    
    func fetchAndNotify() {
        Task {
            if let state = await fetchState() {
                await MainActor.run {
                    self.delegate?.nowPlayingProvider(self, didUpdateState: state)
                }
            }
        }
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.isMonitoring else { break }
                let isPlaying = self.lastKnownState?.isPlaying ?? false
                let delaySeconds = isPlaying ? 1.0 : 5.0
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                
                if let state = await self.fetchState() {
                    if state != self.lastKnownState {
                        self.lastKnownState = state
                        await MainActor.run {
                            self.delegate?.nowPlayingProvider(self, didUpdateState: state)
                        }
                    }
                }
            }
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        pollTask?.cancel()
        pollTask = nil
    }
    
    // MARK: - Playback Controls
    
    func playPause() {
        executeJSOnYouTubeMusicTab("""
        var v = document.querySelector('video');
        if (v) { v.paused ? v.play() : v.pause(); }
        else { document.querySelector('#play-pause-button')?.click(); }
        """)
    }
    
    func nextTrack() {
        executeJSOnYouTubeMusicTab("""
        var nextBtn = document.querySelector('.next-button, button[aria-label="Next song"], button[aria-label="Next"]');
        if (nextBtn) nextBtn.click();
        """)
    }
    
    func previousTrack() {
        executeJSOnYouTubeMusicTab("""
        var prevBtn = document.querySelector('.previous-button, button[aria-label="Previous song"], button[aria-label="Previous"]');
        if (prevBtn) prevBtn.click();
        """)
    }
    
    func seek(to time: TimeInterval) {
        executeJSOnYouTubeMusicTab("""
        var v = document.querySelector('video');
        if (v) v.currentTime = \(time);
        """)
    }
    
    private func executeJSOnYouTubeMusicTab(_ js: String) {
        guard let browser = activeBrowser else { return }
        let script = """
        tell application "\(browser.appName)"
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "music.youtube.com" then
                        try
                            execute t javascript "\(js.replacingOccurrences(of: "\"", with: "\\\""))"
                            return
                        end try
                    end if
                end repeat
            end repeat
        end tell
        """
        Task {
            _ = await AppleScriptRunner.shared.run(script: script, timeout: 2.0)
        }
    }
}
