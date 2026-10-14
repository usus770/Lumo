import Foundation
import MediaPlayer
import AppKit

/// Pushes Lumo's own active playback metadata to MPNowPlayingInfoCenter (macOS Control Strip,
/// lock screen, and remote control surfaces) and registers MPRemoteCommandCenter
/// handlers so media keys and AirPlay controls control Lumo playback.
final class NowPlayingInfoPublisher: @unchecked Sendable {
    static let shared = NowPlayingInfoPublisher()

    private weak var playbackState: PlaybackState?
    private var isRegistered = false

    private init() {}

    /// Call once from the app entry point after PlaybackState is available.
    func connect(to playbackState: PlaybackState) {
        self.playbackState = playbackState
        registerRemoteCommands()
        isRegistered = true
    }

    // MARK: - Now Playing Info

    func update(track: TrackInfo?, isPlaying: Bool, currentTime: TimeInterval, rate: Float = 1) {
        let center = MPNowPlayingInfoCenter.default()

        guard let track = track else {
            center.nowPlayingInfo = nil
            center.playbackState  = .stopped
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle:           track.title,
            MPMediaItemPropertyArtist:          track.artist,
            MPMediaItemPropertyAlbumTitle:      track.album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate:        isPlaying ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]

        if let artworkData = track.artworkData, let nsImage = NSImage(data: artworkData) {
            let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in nsImage }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        center.nowPlayingInfo = info
        center.playbackState  = isPlaying ? .playing : .paused
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState  = .stopped
    }

    // MARK: - Remote Commands

    private func registerRemoteCommands() {
        let cmd = MPRemoteCommandCenter.shared()

        cmd.playCommand.addTarget { [weak self] _ in
            self?.playbackState?.isPlaying = true
            return .success
        }
        cmd.pauseCommand.addTarget { [weak self] _ in
            self?.playbackState?.isPlaying = false
            return .success
        }
        cmd.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.playbackState?.togglePlayPause()
            return .success
        }
        cmd.nextTrackCommand.addTarget { [weak self] _ in
            self?.playbackState?.nextTrack()
            return .success
        }
        cmd.previousTrackCommand.addTarget { [weak self] _ in
            self?.playbackState?.previousTrack()
            return .success
        }
        cmd.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                self?.playbackState?.seek(to: e.positionTime)
            }
            return .success
        }
        cmd.changePlaybackRateCommand.addTarget { event in
            if let e = event as? MPChangePlaybackRateCommandEvent {
                SettingsStore.shared.playbackSpeed = Float(e.playbackRate)
            }
            return .success
        }

        // Enable the commands we support
        cmd.playCommand.isEnabled                  = true
        cmd.pauseCommand.isEnabled                 = true
        cmd.togglePlayPauseCommand.isEnabled       = true
        cmd.nextTrackCommand.isEnabled             = true
        cmd.previousTrackCommand.isEnabled         = true
        cmd.changePlaybackPositionCommand.isEnabled = true
        cmd.changePlaybackRateCommand.isEnabled    = true
        cmd.skipForwardCommand.isEnabled           = false
        cmd.skipBackwardCommand.isEnabled          = false
        cmd.seekForwardCommand.isEnabled           = false
        cmd.seekBackwardCommand.isEnabled          = false
    }
}
