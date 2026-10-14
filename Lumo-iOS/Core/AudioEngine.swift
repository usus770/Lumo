import Foundation
import AVFoundation
import Combine

/// Core Audio Player Engine for Lumo iOS.
/// Handles AVAudioSession background configuration, interruption handling,
/// and smooth high-resolution audio playback.
@MainActor
public final class iOSAudioEngine: ObservableObject {
    public static let shared = iOSAudioEngine()
    
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var cancellables = Set<AnyCancellable>()
    
    public var onTrackDidFinish: (() -> Void)?
    
    private init() {
        configureAudioSession()
        setupNotificationObservers()
    }
    
    deinit {
        removeTimeObserver()
    }
    
    // MARK: - Audio Session Configuration
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
    }
    
    private func setupNotificationObservers() {
        // Interruption handling (phone calls, FaceTime, alarms)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notif in
                self?.handleAudioInterruption(notif)
            }
            .store(in: &cancellables)
        
        // Route changes (AirPods disconnect, headphones unplugged)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notif in
                self?.handleRouteChange(notif)
            }
            .store(in: &cancellables)
    }
    
    private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        if type == .began {
            pause()
        } else if type == .ended {
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    play()
                }
            }
        }
    }
    
    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        // Automatically pause when headphones or Bluetooth disconnected
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }
    
    // MARK: - Playback Controls
    
    public func loadAndPlay(track: iOSTrack) {
        guard let url = track.fileURL else { return }
        
        removeTimeObserver()
        let item = AVPlayerItem(url: url)
        
        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        
        duration = track.duration
        currentTime = 0
        
        // Notify when track ends
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.onTrackDidFinish?()
        }
        
        addPeriodicTimeObserver()
        play()
    }
    
    public func play() {
        player?.play()
        isPlaying = true
    }
    
    public func pause() {
        player?.pause()
        isPlaying = false
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.currentTime = time
        }
    }
    
    // MARK: - Time Observer
    
    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let secs = CMTimeGetSeconds(time)
            if !secs.isNaN && !secs.isInfinite {
                self.currentTime = secs
            }
        }
    }
    
    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
}
