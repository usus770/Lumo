import SwiftUI
import AppKit

/// Manages and observes the state of external media players (Apple Music, Spotify, VLC, etc.)
/// Provides a unified `activeState` that the UI can display when Lumo itself is not playing.
/// This is now a thin wrapper around NowPlayingProviderManager for backward compatibility.
@Observable
final class UniversalNowPlayingManager: @unchecked Sendable {
    static let shared = UniversalNowPlayingManager()
    
    /// The currently active (or most recently active) external player state.
    var activeState: ExternalPlayerState?
    
    /// The name of the source app (e.g., "Apple Music", "Spotify")
    var sourceAppName: String?
    
    /// The icon of the source app
    var sourceAppIcon: NSImage?
    
    private let providerManager = NowPlayingProviderManager.shared
    private var streamTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    
    private init() {
        startStreamObserver()
        NotificationCenter.default.addObserver(forName: .nowPlayingProviderDidUpdate, object: nil, queue: .main) { [weak self] _ in
            Task { [weak self] in
                if let state = await NowPlayingCoordinator.shared.getCurrentState() {
                    await self?.updateState(state)
                }
            }
        }
    }
    
    deinit {
        streamTask?.cancel()
    }
    
    private func startStreamObserver() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            let stream = await NowPlayingCoordinator.shared.stateStream
            for await state in stream {
                await self?.updateState(state)
            }
        }
    }
    
    @MainActor
    private func updateState(_ state: ExternalPlayerState?) {
        self.activeState = state
        self.sourceAppName = state?.appName
        if let bundleID = state?.sourceBundleIdentifier, !bundleID.isEmpty {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                self.sourceAppIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            } else {
                self.sourceAppIcon = NSWorkspace.shared.icon(forFile: bundleID)
            }
        } else {
            self.sourceAppIcon = nil
        }
        
        // Push state to the unified NowPlayingSnapshot
        NowPlayingSnapshot.shared.updateExternal(state: state)
    }
    
    /// Starts monitoring external players. Should be called when Lumo stops playing.
    func startMonitoring() {
        startStreamObserver()
        providerManager.startMonitoring()
    }
    
    /// Stops monitoring external players. Should be called when Lumo starts playing.
    func stopMonitoring() {
        providerManager.stopMonitoring()
    }
    
    // MARK: - Controls
    
    func playPause() {
        providerManager.playPause()
    }
    
    func nextTrack() {
        providerManager.nextTrack()
    }
    
    func previousTrack() {
        providerManager.previousTrack()
    }
    
    func seek(to time: TimeInterval) {
        providerManager.seek(to: time)
    }
}

extension Notification.Name {
    static let nowPlayingProviderDidUpdate = Notification.Name("nowPlayingProviderDidUpdate")
}

// Extension to notify the UniversalNowPlayingManager of changes
extension NowPlayingProviderManager {
    func notifyObservers() {
        NotificationCenter.default.post(name: .nowPlayingProviderDidUpdate, object: nil)
    }
    
    // Call this after updating activeState
    func _notifyObservers() {
        notifyObservers()
    }
}