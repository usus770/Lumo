import AppKit
import SwiftUI

/// Custom NSWindow that intercepts Esc, Cmd+W, lyrics offset keys, and any click in the top 60px
class VisualizerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func sendEvent(_ event: NSEvent) {
        if event.type == .mouseMoved || event.type == .leftMouseDragged || event.type == .rightMouseDragged {
            NotificationCenter.default.post(name: Notification.Name("LumoVisualizerUserActivity"), object: event.locationInWindow)
        }
        if event.type == .keyDown {
            NotificationCenter.default.post(name: Notification.Name("LumoVisualizerUserActivity"), object: nil)
        }
        // SAFETY FIRST: Clicking anywhere in the top 60px immediately closes the visualizer
        if event.type == .leftMouseDown {
            let loc = event.locationInWindow
            if loc.y >= frame.height - 60.0 {
                VisualizerWindowController.shared.closeFullScreen()
                return
            }
        }
        super.sendEvent(event)
    }
    
    override func keyDown(with event: NSEvent) {
        if VisualizerWindowController.handleVisualizerKey(event: event) {
            return
        }
        super.keyDown(with: event)
    }
    
    override func cancelOperation(_ sender: Any?) {
        VisualizerWindowController.shared.closeFullScreen()
    }
}

final class MainThreadWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var pingDispatchedAt: TimeInterval? = nil
    private var isActive: Bool = false
    private var timer: DispatchSourceTimer?
    private var onStall: (@Sendable () -> Void)?
    
    init() {}
    
    func start(onStall: @escaping @Sendable () -> Void) {
        stop()
        lock.withLock {
            self.pingDispatchedAt = nil
            self.isActive = true
            self.onStall = onStall
        }
        
        let queue = DispatchQueue(label: "com.lumo.visualizer.watchdog", qos: .userInteractive)
        let src = DispatchSource.makeTimerSource(queue: queue)
        src.schedule(deadline: .now() + 0.5, repeating: 0.25)
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            var shouldTrigger = false
            var callback: (@Sendable () -> Void)?
            var needsNewPing = false
            
            self.lock.withLock {
                guard self.isActive else { return }
                if let dispatched = self.pingDispatchedAt {
                    let stallDuration = now - dispatched
                    if stallDuration > 2.0 {
                        shouldTrigger = true
                        callback = self.onStall
                    }
                } else {
                    self.pingDispatchedAt = now
                    needsNewPing = true
                }
            }
            
            if shouldTrigger, let callback = callback {
                NSLog("[WATCHDOG] Main thread stalled > 2s! Emergency close triggered.")
                callback()
                return
            }
            
            if needsNewPing {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.lock.withLock {
                        if self.isActive {
                            self.pingDispatchedAt = nil
                        }
                    }
                }
            }
        }
        src.resume()
        self.timer = src
    }
    
    func stop() {
        lock.withLock {
            self.isActive = false
            self.onStall = nil
            self.pingDispatchedAt = nil
        }
        timer?.cancel()
        timer = nil
    }
}

@MainActor
class VisualizerWindowController: NSWindowController {
    static let shared = VisualizerWindowController()
    
    public private(set) var isOpen: Bool = false
    private var previousPresentationOptions: NSApplication.PresentationOptions? = nil
    private var localKeyMonitor: Any? = nil
    
    // Watchdog components
    private let watchdog = MainThreadWatchdog()
    private var heartbeatTimer: Timer? = nil
    
    private init() {
        let initialFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1792, height: 1120)
        let window = VisualizerWindow(
            contentRect: initialFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        
        window.acceptsMouseMovedEvents = true
        
        super.init(window: window)
        
        let rootView = KineticVisualizerView()
            .environment(PlaybackState.shared)
        
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.black.cgColor
        
        window.contentViewController = hostingController
        
        // Ensure options are restored if the app terminates while visualizer is open
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closeFullScreen()
            }
        }
        
        // Local event monitor for keyboard shortcuts as redundant safeguard
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isOpen else { return event }
            if VisualizerWindowController.handleVisualizerKey(event: event) {
                return nil
            }
            return event
        }
    }
    
    @MainActor
    public static func handleVisualizerKey(event: NSEvent) -> Bool {
        // 1. Exit / Close
        if event.keyCode == 53 { // ESC
            VisualizerWindowController.shared.closeFullScreen()
            return true
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w" {
            VisualizerWindowController.shared.closeFullScreen()
            return true
        }
        if event.charactersIgnoringModifiers == "f" && !event.modifierFlags.contains(.command) {
            VisualizerWindowController.shared.closeFullScreen()
            return true
        }
        
        // 2. Play / Pause (Space)
        if event.keyCode == 49 { // Space
            PlaybackState.shared.togglePlayPause()
            NotificationCenter.default.post(name: Notification.Name("LumoFlashPlayPauseFeedback"), object: nil)
            return true
        }
        
        // 3. Arrow Keys: Seek vs Prev/Next
        if event.keyCode == 123 { // Left Arrow
            if event.modifierFlags.contains(.shift) {
                PlaybackState.shared.previousTrack()
            } else {
                let cur = NowPlayingSnapshot.shared.position()
                PlaybackState.shared.seek(to: max(0, cur - 5.0))
            }
            return true
        }
        if event.keyCode == 124 { // Right Arrow
            if event.modifierFlags.contains(.shift) {
                PlaybackState.shared.nextTrack()
            } else {
                let cur = NowPlayingSnapshot.shared.position()
                PlaybackState.shared.seek(to: min(NowPlayingSnapshot.shared.duration, cur + 5.0))
            }
            return true
        }
        
        // 4. Volume Up / Down
        if event.keyCode == 126 { // Up Arrow
            PlaybackState.shared.adjustVolume(by: 0.1)
            return true
        }
        if event.keyCode == 125 { // Down Arrow
            PlaybackState.shared.adjustVolume(by: -0.1)
            return true
        }
        
        // 5. Mute (M)
        if event.charactersIgnoringModifiers?.lowercased() == "m" && !event.modifierFlags.contains(.command) {
            PlaybackState.shared.toggleMute()
            return true
        }
        
        // 6. Lyrics Offset ([ and ])
        if event.charactersIgnoringModifiers == "[" {
            let current = NowPlayingSnapshot.shared.userLyricsOffset
            NowPlayingSnapshot.shared.setUserLyricsOffset(current - 0.1)
            return true
        }
        if event.charactersIgnoringModifiers == "]" {
            let current = NowPlayingSnapshot.shared.userLyricsOffset
            NowPlayingSnapshot.shared.setUserLyricsOffset(current + 0.1)
            return true
        }
        
        // 7. Transliteration (L)
        if event.charactersIgnoringModifiers?.lowercased() == "l" && !event.modifierFlags.contains(.command) {
            NotificationCenter.default.post(name: Notification.Name("LumoToggleRomanized"), object: nil)
            return true
        }
        
        // 8. Shortcuts Help Overlay (? or /)
        if event.charactersIgnoringModifiers == "?" || event.charactersIgnoringModifiers == "/" {
            NotificationCenter.default.post(name: Notification.Name("LumoToggleHelpOverlay"), object: nil)
            return true
        }
        
        // 9. Debug HUD (D or Cmd+D)
        if event.charactersIgnoringModifiers == "d" || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "d") {
            NotificationCenter.default.post(name: Notification.Name("LumoToggleDebugOverlay"), object: nil)
            return true
        }
        
        return false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showFullScreen() {
        guard let window = self.window else { return }
        
        // Target screen and frame: full screen frame, covering notch and menu bar
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let s = screen {
            window.setFrame(s.frame, display: true)
        }
        
        // Hide macOS Menu Bar and Dock
        if previousPresentationOptions == nil {
            previousPresentationOptions = NSApp.presentationOptions
        }
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        isOpen = true
        NotificationCenter.default.post(name: Notification.Name("LumoVisualizerVisibilityChanged"), object: true)
        
        startWatchdog()
    }
    
    func closeFullScreen() {
        stopWatchdog()
        
        // Restore presentation options immediately
        if let saved = previousPresentationOptions {
            NSApp.presentationOptions = saved
            previousPresentationOptions = nil
        }
        
        if let window = self.window {
            window.orderOut(nil)
        }
        isOpen = false
        NotificationCenter.default.post(name: Notification.Name("LumoVisualizerVisibilityChanged"), object: false)
    }
    
    // MARK: - Watchdog (2-Second Main Thread Stall Protection)
    
    private func startWatchdog() {
        stopWatchdog()
        watchdog.start {
            DispatchQueue.main.async {
                VisualizerWindowController.shared.closeFullScreen()
            }
        }
    }
    
    private func stopWatchdog() {
        watchdog.stop()
    }
}

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        
        let rootView = SettingsView()
            .environment(PlaybackState.shared)
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show(tab: Int = 4) {
        NotificationCenter.default.post(name: Notification.Name("LumoSelectSettingsTab"), object: tab)
        if let window = self.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    override func close() {
        window?.orderOut(nil)
    }
}
