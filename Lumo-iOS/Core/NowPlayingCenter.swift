import Foundation
import MediaPlayer
import UIKit

/// Integrates Lumo with iOS Lock Screen, Control Center, Dynamic Island, and Apple Watch
/// using MPNowPlayingInfoCenter and MPRemoteCommandCenter.
@MainActor
public final class iOSNowPlayingCenter {
    public static let shared = iOSNowPlayingCenter()
    
    private init() {}
    
    // MARK: - Setup Remote Commands (Lock Screen Controls)
    
    public func setupRemoteCommands(playbackState: iOSPlaybackState) {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            playbackState.play()
            return .success
        }
        
        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            playbackState.pause()
            return .success
        }
        
        // Toggle Play / Pause (AirPods click)
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            playbackState.togglePlayPause()
            return .success
        }
        
        // Next Track
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            playbackState.nextTrack()
            return .success
        }
        
        // Previous Track
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            playbackState.previousTrack()
            return .success
        }
        
        // Scrubber / Position Slider
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            if let posEvent = event as? MPChangePlaybackPositionCommandEvent {
                playbackState.seek(to: posEvent.positionTime)
                return .success
            }
            return .commandFailed
        }
    }
    
    // MARK: - Update Now Playing Info (Lock Screen Metadata & Artwork)
    
    public func updateNowPlayingInfo(track: iOSTrack?, isPlaying: Bool, currentTime: TimeInterval) {
        guard let track = track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        
        if let data = track.artworkData, let uiImage = UIImage(data: data) {
            let artwork = MPMediaItemArtwork(boundsSize: uiImage.size) { _ in uiImage }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
