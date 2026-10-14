import Foundation
import AppKit
import OSLog

#if DIRECT_DISTRIBUTION
/// System-wide Now Playing Provider using macOS MediaRemote private framework
/// and fallback to mediaremote-adapter helper.
///
/// Captures playback metadata published by ANY application to macOS Now Playing:
/// - Safari Web Apps (PWAs under ~/Applications)
/// - Google Chrome, Brave, Microsoft Edge, Arc
/// - Safari browser tabs
/// - Apple Music, Spotify, VLC, and other native apps
final class SystemNowPlayingProvider: NowPlayingProvider, @unchecked Sendable {
    
    // MARK: - Enums & Types
    
    enum OperationalMode: String, Sendable {
        case direct = "Direct MediaRemote (dlopen)"
        case adapter = "mediaremote-adapter (/usr/bin/swift)"
        case disabled = "Unavailable"
    }
    
    // MRMediaRemote C Callbacks
    private typealias MRGetInfoFn = @convention(c) (DispatchQueue, @escaping @Sendable (NSDictionary?) -> Void) -> Void
    private typealias MRPidFn = @convention(c) (DispatchQueue, @escaping @Sendable (pid_t) -> Void) -> Void
    private typealias MRRegisterNotificationsFn = @convention(c) (DispatchQueue) -> Void
    private typealias MRSendCommandFn = @convention(c) (UInt32, UnsafeMutableRawPointer?) -> Bool
    
    // Standard MediaRemote Command Constants
    private static let kMRPlay: UInt32 = 0
    private static let kMRPause: UInt32 = 1
    private static let kMRTogglePlayPause: UInt32 = 2
    private static let kMRStop: UInt32 = 3
    private static let kMRNextTrack: UInt32 = 4
    private static let kMRPreviousTrack: UInt32 = 5
    private static let kMRBeginFastForward: UInt32 = 6
    private static let kMREndFastForward: UInt32 = 7
    private static let kMRBeginRewind: UInt32 = 8
    private static let kMREndRewind: UInt32 = 9
    
    // MARK: - Shared State
    
    private static let modeLock = NSRecursiveLock()
    private class StateContainer: @unchecked Sendable {
        var mode: OperationalMode?
    }
    private static let container = StateContainer()
    
    private static var cachedOperationalMode: OperationalMode? {
        get {
            modeLock.lock()
            defer { modeLock.unlock() }
            return container.mode
        }
        set {
            modeLock.lock()
            container.mode = newValue
            modeLock.unlock()
        }
    }
    
    // MARK: - Properties
    
    weak var delegate: NowPlayingProviderDelegate?
    
    private(set) var activeMode: OperationalMode = .disabled
    private var isMonitoring = false
    private var pollTask: Task<Void, Never>?
    private var lastKnownState: ExternalPlayerState?
    
    // Direct MediaRemote Handles
    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var getNowPlayingInfoFn: MRGetInfoFn?
    private var getNowPlayingPIDFn: MRPidFn?
    private var registerNotificationsFn: MRRegisterNotificationsFn?
    private var sendCommandFn: MRSendCommandFn?
    
    // Adapter Process Handle
    private var adapterProcess: Process?
    private var adapterStdinPipe: Pipe?
    private var adapterRestartAttempts = 0
    private var isTerminating = false
    
    // Supported Browser & PWA Bundle Identifiers
    private static let supportedBrowserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi"
    ]
    
    // MARK: - Protocol Conformance
    
    var appName: String {
        "System Now Playing"
    }
    
    var isAvailable: Bool {
        activeMode != .disabled
    }
    
    var bundleIdentifiers: [String] {
        if let id = lastKnownState?.sourceBundleIdentifier, !id.isEmpty {
            return [id]
        }
        return Array(Self.supportedBrowserBundleIDs)
    }
    
    // MARK: - Initialization
    
    init() {
        LumoLogger.systemNowPlaying.info("Initializing SystemNowPlayingProvider")
        configureMode()
    }
    
    deinit {
        isTerminating = true
        stopMonitoring()
    }
    
    // MARK: - Mode Discovery & Caching
    
    private func configureMode() {
        Self.modeLock.lock()
        defer { Self.modeLock.unlock() }
        
        if let cached = Self.cachedOperationalMode {
            self.activeMode = cached
            LumoLogger.systemNowPlaying.info("Using cached operational mode: \(cached.rawValue, privacy: .public)")
            setupMode(cached)
            return
        }
        
        // 1. Try Apple-signed adapter helper via /usr/bin/swift (100% reliable across macOS processes)
        if trySetupAdapter() {
            self.activeMode = .adapter
            Self.cachedOperationalMode = .adapter
            LumoLogger.systemNowPlaying.info("mediaremote-adapter helper verified and operational")
            return
        }
        
        // 2. Direct MediaRemote (fallback)
        if tryLoadDirectMediaRemote() {
            self.activeMode = .direct
            Self.cachedOperationalMode = .direct
            LumoLogger.systemNowPlaying.info("Direct MediaRemote verified and operational")
            return
        }
        
        self.activeMode = .disabled
        Self.cachedOperationalMode = .disabled
        LumoLogger.systemNowPlaying.warning("SystemNowPlayingProvider is unavailable on this system")
    }
    
    private func setupMode(_ mode: OperationalMode) {
        switch mode {
        case .adapter:
            _ = trySetupAdapter()
        case .direct:
            _ = tryLoadDirectMediaRemote()
        case .disabled:
            break
        }
    }
    
    // MARK: - Direct MediaRemote Loading
    
    private func tryLoadDirectMediaRemote() -> Bool {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else {
            LumoLogger.systemNowPlaying.info("dlopen MediaRemote failed: \(String(cString: dlerror()))")
            return false
        }
        
        guard let getInfoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
              let sendCmdSym = dlsym(handle, "MRMediaRemoteSendCommand"),
              let registerSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") else {
            LumoLogger.systemNowPlaying.info("dlsym failed for core MediaRemote functions: \(String(cString: dlerror()))")
            return false
        }
        
        self.mediaRemoteHandle = handle
        self.getNowPlayingInfoFn = unsafeBitCast(getInfoSym, to: MRGetInfoFn.self)
        self.sendCommandFn = unsafeBitCast(sendCmdSym, to: MRSendCommandFn.self)
        self.registerNotificationsFn = unsafeBitCast(registerSym, to: MRRegisterNotificationsFn.self)
        
        if let pidSym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            self.getNowPlayingPIDFn = unsafeBitCast(pidSym, to: MRPidFn.self)
        }
        
        return true
    }
    
    // MARK: - Adapter Helper Fallback
    
    private func trySetupAdapter() -> Bool {
        let swiftURL = URL(fileURLWithPath: "/usr/bin/swift")
        guard FileManager.default.isExecutableFile(atPath: swiftURL.path) else {
            return false
        }
        
        // Find vendored adapter script
        let scriptPath = findAdapterScriptPath()
        guard let scriptPath = scriptPath, FileManager.default.fileExists(atPath: scriptPath) else {
            LumoLogger.systemNowPlaying.debug("Adapter script not found at expected paths")
            return false
        }
        
        return startAdapterProcess(scriptPath: scriptPath)
    }
    
    private func findAdapterScriptPath() -> String? {
        if let path = Bundle.main.path(forResource: "mediaremote-adapter", ofType: "swift") {
            return path
        }
        let localPath = Bundle.main.bundlePath + "/Contents/Resources/mediaremote-adapter.swift"
        if FileManager.default.fileExists(atPath: localPath) {
            return localPath
        }
        let devSwift = FileManager.default.currentDirectoryPath + "/Sources/Resources/mediaremote-adapter.swift"
        if FileManager.default.fileExists(atPath: devSwift) {
            return devSwift
        }
        return nil
    }
    
    private func startAdapterProcess(scriptPath: String) -> Bool {
        guard !isTerminating else { return false }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [scriptPath]
        
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        
        self.adapterStdinPipe = inPipe
        self.adapterProcess = process
        
        // Process termination handler
        process.terminationHandler = { [weak self] proc in
            guard let self = self, !self.isTerminating else { return }
            LumoLogger.systemNowPlaying.warning("Adapter process exited with code \(proc.terminationStatus)")
            self.handleAdapterCrash(scriptPath: scriptPath)
        }
        
        do {
            try process.run()
            LumoLogger.systemNowPlaying.info("mediaremote-adapter process launched via /usr/bin/swift (PID: \(process.processIdentifier))")
            
            // Read lines from stdout
            Task { [weak self] in
                guard let self = self else { return }
                for try await line in outPipe.fileHandleForReading.bytes.lines {
                    self.parseAdapterLine(line)
                }
            }
            
            return true
        } catch {
            LumoLogger.systemNowPlaying.error("Failed to run adapter process: \(error, privacy: .public)")
            return false
        }
    }
    
    private func handleAdapterCrash(scriptPath: String) {
        guard adapterRestartAttempts < 5 else {
            LumoLogger.systemNowPlaying.error("Adapter exceeded maximum restart attempts, disabling")
            self.activeMode = .disabled
            return
        }
        adapterRestartAttempts += 1
        let delay = Double(adapterRestartAttempts) * 1.5
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            _ = self.startAdapterProcess(scriptPath: scriptPath)
        }
    }
    
    private func parseAdapterLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        if let type = json["type"] as? String {
            if type == "READY" || type == "COMMAND_ACK" { return }
            if type == "EMPTY" {
                self.lastKnownState = nil
                Task { @MainActor in
                    self.delegate?.nowPlayingProvider(self, didUpdateState: nil)
                }
                return
            }
        }
        
        var parsedDict = json
        if let artB64 = json["artworkData"] as? String, let artData = Data(base64Encoded: artB64) {
            parsedDict["artworkData"] = artData
        }
        
        if let state = parseMediaRemoteDictionary(parsedDict) {
            self.lastKnownState = state
            Task { @MainActor in
                self.delegate?.nowPlayingProvider(self, didUpdateState: state)
            }
        }
    }
    
    // MARK: - State Fetching
    
    func fetchState() async -> ExternalPlayerState? {
        switch activeMode {
        case .direct:
            return await fetchDirectState()
        case .adapter:
            return lastKnownState
        case .disabled:
            return nil
        }
    }
    
    private struct DictWrapper: @unchecked Sendable {
        let dict: NSDictionary?
    }

    private func fetchDirectState() async -> ExternalPlayerState? {
        guard let getInfo = getNowPlayingInfoFn else { return nil }
        
        // 1. Get Now Playing Info Dict
        let wrappedDict = await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.lumo.mediaremote.fetch")
            getInfo(queue) { result in
                continuation.resume(returning: DictWrapper(dict: result))
            }
        }
        
        guard let dict = wrappedDict.dict as? [String: Any] else {
            return nil
        }
        
        // 2. Resolve PID and Bundle Identifier
        let pid: pid_t = await withCheckedContinuation { continuation in
            if let getPID = self.getNowPlayingPIDFn {
                let queue = DispatchQueue(label: "com.lumo.mediaremote.pid")
                getPID(queue) { pid in
                    continuation.resume(returning: pid)
                }
            } else {
                continuation.resume(returning: 0)
            }
        }
        
        var sourceBundleID: String? = nil
        if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
            sourceBundleID = app.bundleIdentifier
        }
        
        let state = parseMediaRemoteDictionary(dict, sourceBundleID: sourceBundleID)
        return state
    }
    
    // MARK: - Metadata Parsing & YouTube Music Identification
    
    private func parseMediaRemoteDictionary(_ dict: [String: Any], sourceBundleID: String? = nil) -> ExternalPlayerState? {
        let title = (dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String) ??
                    (dict["title"] as? String)
        let artist = (dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ??
                     (dict["artist"] as? String)
        let album = (dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String) ??
                    (dict["album"] as? String)
        let artworkData = (dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data) ??
                          (dict["artworkData"] as? Data)
        
        let duration = (dict["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ??
                       (dict["duration"] as? Double) ?? 0.0
        let elapsedTime = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ??
                          (dict["elapsedTime"] as? Double) ?? 0.0
        let playbackRate = (dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ??
                           (dict["playbackRate"] as? Double) ?? 0.0
        
        // Bundle Identifier from dictionary or PID resolution
        var bundleID = sourceBundleID ??
                       (dict["kMRMediaRemoteNowPlayingInfoBundleIdentifier"] as? String) ??
                       (dict["bundleIdentifier"] as? String)
        
        // If not found, inspect running applications
        if bundleID == nil || bundleID?.isEmpty == true {
            bundleID = inferBundleIdentifier(title: title, artist: artist)
        }
        
        let isPlaying = playbackRate > 0.0
        
        // YouTube Music & Source App Identification
        let (resolvedAppName, isYouTubeMusic) = identifySource(bundleID: bundleID, title: title, artist: artist, album: album)
        
        let finalAppName = isYouTubeMusic ? "YouTube Music" : resolvedAppName
        
        return ExternalPlayerState(
            isPlaying: isPlaying,
            trackName: title,
            artistName: artist,
            albumName: album,
            duration: duration,
            currentTime: elapsedTime,
            artworkData: artworkData,
            appName: finalAppName,
            sourceBundleIdentifier: bundleID,
            sourceURL: nil,
            playbackRate: playbackRate > 0 ? playbackRate : 1.0,
            lastUpdated: Date()
        )
    }
    
    private func inferBundleIdentifier(title: String?, artist: String?) -> String? {
        let runningApps = NSWorkspace.shared.runningApplications
        // 1. Check for running Safari Web Apps
        for app in runningApps {
            if let bid = app.bundleIdentifier, bid.hasPrefix("com.apple.Safari.WebApp.") {
                return bid
            }
        }
        // 2. Check for running browsers
        for app in runningApps {
            if let bid = app.bundleIdentifier, Self.supportedBrowserBundleIDs.contains(bid) {
                return bid
            }
        }
        return nil
    }
    
    private func identifySource(bundleID: String?, title: String?, artist: String?, album: String?) -> (appName: String, isYTM: Bool) {
        guard let bundleID = bundleID else {
            return ("System Media", false)
        }
        
        // 1. Safari Web App (PWA) Detection
        if bundleID.hasPrefix("com.apple.Safari.WebApp.") {
            let runningApps = NSWorkspace.shared.runningApplications
            let app = runningApps.first { $0.bundleIdentifier == bundleID }
            let name = app?.localizedName?.lowercased() ?? ""
            if name.contains("yt music") || name.contains("youtube music") || name.contains("music") {
                return ("YouTube Music", true)
            }
            return ("YouTube Music (Safari Web App)", true)
        }
        
        // 2. Chrome Web App (PWA) Detection
        if bundleID.hasPrefix("com.google.Chrome.app.") {
            let runningApps = NSWorkspace.shared.runningApplications
            let app = runningApps.first { $0.bundleIdentifier == bundleID }
            let name = app?.localizedName?.lowercased() ?? ""
            if name.contains("youtube") || name.contains("music") || name.contains("yt") {
                return ("YouTube Music", true)
            }
            return ("YouTube Music (Chrome Web App)", true)
        }
        
        // 3. Check App Name for any running app
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            let name = app.localizedName?.lowercased() ?? ""
            if name.contains("youtube music") || name == "yt music" {
                return ("YouTube Music", true)
            }
        }
        
        // 4. Native players
        if bundleID == "com.apple.Music" { return ("Apple Music", false) }
        if bundleID == "com.spotify.client" { return ("Spotify", false) }
        if bundleID == "org.videolan.vlc" { return ("VLC", false) }
        
        // 5. Chromium Browsers & Safari
        let browserName: String
        var isBrowser = true
        switch bundleID {
        case "com.google.Chrome": browserName = "Google Chrome"
        case "com.apple.Safari": browserName = "Safari"
        case "com.brave.Browser": browserName = "Brave"
        case "com.microsoft.edgemac": browserName = "Microsoft Edge"
        case "company.thebrowser.Browser": browserName = "Arc"
        case "com.operasoftware.Opera": browserName = "Opera"
        case "com.vivaldi.Vivaldi": browserName = "Vivaldi"
        default:
            if bundleID.lowercased().contains("chrome") {
                browserName = "Google Chrome"
            } else if bundleID.lowercased().contains("safari") {
                browserName = "Safari"
            } else {
                browserName = bundleID
                isBrowser = false
            }
        }
        
        // Identify YouTube Music inside the browser via metadata patterns
        if isBrowser {
            let t = (title ?? "").lowercased()
            let a = (artist ?? "").lowercased()
            let al = (album ?? "").lowercased()
            
            if t.contains("youtube") || a.contains("youtube") || al.contains("youtube") ||
               a.contains("• topic") || a.contains("topic") ||
               (title != nil && !title!.isEmpty && artist != nil && !artist!.isEmpty) {
                // Highly probable YouTube Music stream
                return ("YouTube Music", true)
            }
            return (browserName, false)
        }
        
        return (browserName, false)
    }
    
    // MARK: - Monitoring Lifecycle
    
    func startMonitoring() {
        guard !isMonitoring, isAvailable else { return }
        isMonitoring = true
        LumoLogger.systemNowPlaying.info("Starting monitoring in mode: \(self.activeMode.rawValue, privacy: .public)")
        
        // 1. Register for direct notifications if available
        if activeMode == .direct, let regFn = registerNotificationsFn {
            regFn(DispatchQueue.main)
        }
        
        // 2. Fetch immediately
        fetchAndNotify()
        
        // 3. Periodic polling backup to catch track position and edge changes
        startPolling()
    }
    
    func stopMonitoring() {
        isMonitoring = false
        pollTask?.cancel()
        pollTask = nil
        
        if let process = adapterProcess, process.isRunning {
            process.terminate()
            adapterProcess = nil
        }
        LumoLogger.systemNowPlaying.info("SystemNowPlayingProvider monitoring stopped")
    }
    
    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 Hz
                guard let self = self, self.isMonitoring else { break }
                
                if let state = await self.fetchState() {
                    let changed = (self.lastKnownState == nil) ||
                                  (self.lastKnownState != state) ||
                                  (self.lastKnownState?.isPlaying != state.isPlaying) ||
                                  (abs((self.lastKnownState?.currentTime ?? 0) - state.currentTime) >= 1.0)
                    if changed {
                        self.lastKnownState = state
                        await MainActor.run {
                            self.delegate?.nowPlayingProvider(self, didUpdateState: state)
                        }
                    }
                } else if self.lastKnownState != nil {
                    self.lastKnownState = nil
                    await MainActor.run {
                        self.delegate?.nowPlayingProvider(self, didUpdateState: nil)
                    }
                }
            }
        }
    }
    
    func fetchAndNotify() {
        Task {
            if let state = await fetchState() {
                self.lastKnownState = state
                await MainActor.run {
                    self.delegate?.nowPlayingProvider(self, didUpdateState: state)
                }
            }
        }
    }
    
    // MARK: - Playback Controls
    
    func playPause() {
        LumoLogger.systemNowPlaying.info("Dispatching playPause command")
        if sendMediaRemoteCommand(Self.kMRTogglePlayPause) {
            return
        }
        // Fallback: Simulate media key NX_KEYTYPE_PLAY (16)
        simulateMediaKey(key: 16)
    }
    
    func nextTrack() {
        LumoLogger.systemNowPlaying.info("Dispatching nextTrack command")
        if sendMediaRemoteCommand(Self.kMRNextTrack) {
            return
        }
        // Fallback: Simulate media key NX_KEYTYPE_NEXT (17)
        simulateMediaKey(key: 17)
    }
    
    func previousTrack() {
        LumoLogger.systemNowPlaying.info("Dispatching previousTrack command")
        if sendMediaRemoteCommand(Self.kMRPreviousTrack) {
            return
        }
        // Fallback: Simulate media key NX_KEYTYPE_PREVIOUS (18)
        simulateMediaKey(key: 18)
    }
    
    func seek(to time: TimeInterval) {
        LumoLogger.systemNowPlaying.info("Dispatching seek command to \(time)s")
        guard let current = lastKnownState?.currentTime else { return }
        let delta = time - current
        if delta > 3.0 {
            _ = sendMediaRemoteCommand(Self.kMRBeginFastForward)
            Thread.sleep(forTimeInterval: 0.1)
            _ = sendMediaRemoteCommand(Self.kMREndFastForward)
        } else if delta < -3.0 {
            _ = sendMediaRemoteCommand(Self.kMRBeginRewind)
            Thread.sleep(forTimeInterval: 0.1)
            _ = sendMediaRemoteCommand(Self.kMREndRewind)
        }
    }
    
    @discardableResult
    private func sendMediaRemoteCommand(_ command: UInt32) -> Bool {
        if activeMode == .direct, let sendCmd = sendCommandFn {
            let success = sendCmd(command, nil)
            LumoLogger.systemNowPlaying.debug("MRMediaRemoteSendCommand(\(command)) result: \(success)")
            if success { return true }
        }
        
        if activeMode == .adapter, let pipe = adapterStdinPipe {
            let msg = "COMMAND:\(command)\n"
            if let data = msg.data(using: .utf8) {
                try? pipe.fileHandleForWriting.write(contentsOf: data)
                return true
            }
        }
        
        return false
    }
    
    private func simulateMediaKey(key: Int32) {
        LumoLogger.systemNowPlaying.info("Simulating media key \(key)")
        let keyFlags = 0xa00
        let down = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyFlags)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | (0xa << 8)),
            data2: -1
        )
        down?.cgEvent?.post(tap: .cghidEventTap)
        
        let up = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyFlags)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | (0xb << 8)),
            data2: -1
        )
        up?.cgEvent?.post(tap: .cghidEventTap)
    }
}

#else

/// App Store stub implementation when DIRECT_DISTRIBUTION is disabled
final class SystemNowPlayingProvider: NowPlayingProvider, @unchecked Sendable {
    weak var delegate: NowPlayingProviderDelegate?
    let appName = "System Now Playing (Disabled)"
    var isAvailable: Bool { false }
    var bundleIdentifiers: [String] { [] }
    
    init() {}
    func startMonitoring() {}
    func stopMonitoring() {}
    func fetchAndNotify() {}
    func fetchState() async -> ExternalPlayerState? { nil }
    func playPause() {}
    func nextTrack() {}
    func previousTrack() {}
    func seek(to time: TimeInterval) {}
}
#endif
