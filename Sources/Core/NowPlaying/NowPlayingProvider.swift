import Foundation

/// Unified protocol representing a provider of now-playing metadata and transport controls.
protocol NowPlayingProvider: AnyObject, Sendable {
    var isAvailable: Bool { get }
    var appName: String { get }
    var bundleIdentifiers: [String] { get }
    var delegate: NowPlayingProviderDelegate? { get set }
    func startMonitoring()
    func stopMonitoring()
    func fetchAndNotify()
    func fetchState() async -> ExternalPlayerState?
    func playPause()
    func nextTrack()
    func previousTrack()
    func seek(to time: TimeInterval)
}

/// Delegate receiving external player state updates from providers.
protocol NowPlayingProviderDelegate: AnyObject, Sendable {
    func nowPlayingProvider(_ provider: NowPlayingProvider, didUpdateState state: ExternalPlayerState?)
}
