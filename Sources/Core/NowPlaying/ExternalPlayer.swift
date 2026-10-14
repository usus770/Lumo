import Foundation
import AppKit

/// Represents the state of an external player.
struct ExternalPlayerState: Sendable, Equatable {
    var isPlaying: Bool
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var duration: TimeInterval
    var currentTime: TimeInterval
    var artworkData: Data?
    var appName: String
    var sourceBundleIdentifier: String? = nil
    var sourceURL: String? = nil
    var videoId: String? = nil
    var playbackRate: Double = 1.0
    var lastUpdated: Date = Date()
    var timestamp: TimeInterval = Date().timeIntervalSince1970
    var hostTime: TimeInterval = ProcessInfo.processInfo.systemUptime
    
    var bundleIdentifier: String {
        if let sourceBundleIdentifier, !sourceBundleIdentifier.isEmpty {
            return sourceBundleIdentifier
        }
        switch appName {
        case "Apple Music", "Music": return "com.apple.Music"
        case "Spotify": return "com.spotify.client"
        case "Google Chrome", "YouTube Music (Chrome)": return "com.google.Chrome"
        case "Safari", "YouTube Music (Safari)": return "com.apple.Safari"
        default: return ""
        }
    }
    
    // Explicit Equatable ignoring minor timestamp jitter
    static func == (lhs: ExternalPlayerState, rhs: ExternalPlayerState) -> Bool {
        lhs.isPlaying == rhs.isPlaying &&
        lhs.trackName == rhs.trackName &&
        lhs.artistName == rhs.artistName &&
        lhs.albumName == rhs.albumName &&
        abs(lhs.duration - rhs.duration) < 0.5 &&
        abs(lhs.currentTime - rhs.currentTime) < 1.0 &&
        lhs.appName == rhs.appName &&
        lhs.sourceBundleIdentifier == rhs.sourceBundleIdentifier
    }
}

/// A protocol for controlling an external media player.
protocol ExternalPlayer: Sendable {
    var appName: String { get }
    var isRunning: Bool { get }
    func fetchState() async -> ExternalPlayerState?
    func playPause() async
    func nextTrack() async
    func previousTrack() async
    func seek(to time: TimeInterval) async
}
