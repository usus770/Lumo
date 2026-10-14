import Foundation
import AppKit

/// Top-priority Now Playing Provider that receives rich real-time metadata
/// from the Lumo Companion Browser Extension via loopback WebSocket transport.
final class BrowserExtensionProvider: NowPlayingProvider, @unchecked Sendable {
    
    // MARK: - Properties
    
    weak var delegate: NowPlayingProviderDelegate?
    private let server = ExtensionServer.shared
    
    let appName = "YouTube Music (Browser Extension)"
    
    var isAvailable: Bool {
        server.isConnected
    }
    
    var bundleIdentifiers: [String] {
        if let bundleID = server.lastReceivedState?.sourceBundleIdentifier, !bundleID.isEmpty {
            return [bundleID]
        }
        return [
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser"
        ]
    }
    
    // MARK: - Lifecycle
    
    init() {
        server.onStateUpdate { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor in
                self.delegate?.nowPlayingProvider(self, didUpdateState: state)
            }
        }
    }
    
    func startMonitoring() {
        server.start()
    }
    
    func stopMonitoring() {
        // Keep server running in background to detect browser reconnects
    }
    
    func fetchAndNotify() {
        if let state = server.lastReceivedState {
            delegate?.nowPlayingProvider(self, didUpdateState: state)
        }
    }
    
    func fetchState() async -> ExternalPlayerState? {
        server.lastReceivedState
    }
    
    // MARK: - Playback Control Commands
    
    func playPause() {
        server.sendControlCommand(action: "togglePlayPause")
    }
    
    func nextTrack() {
        server.sendControlCommand(action: "next")
    }
    
    func previousTrack() {
        server.sendControlCommand(action: "previous")
    }
    
    func seek(to time: TimeInterval) {
        server.sendControlCommand(action: "seek", time: time)
    }
    
    func like() {
        server.sendControlCommand(action: "like")
    }
    
    func dislike() {
        server.sendControlCommand(action: "dislike")
    }
}
