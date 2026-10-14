import Foundation
import Combine
import SwiftUI

public enum iOSRepeatMode: String, CaseIterable, Codable {
    case off = "Off"
    case all = "All"
    case one = "One"
    
    public var icon: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
    
    public var isActive: Bool {
        self != .off
    }
}

/// Central playback and queue state coordinator for Lumo iOS.
@MainActor
public final class iOSPlaybackState: ObservableObject {
    public static let shared = iOSPlaybackState()
    
    @Published public var currentTrack: iOSTrack?
    @Published public var queue: [iOSTrack] = []
    @Published public var unshuffledQueue: [iOSTrack] = []
    @Published public var history: [iOSTrack] = []
    
    @Published public var isShuffleEnabled: Bool = false
    @Published public var repeatMode: iOSRepeatMode = .off
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let engine = iOSAudioEngine.shared
        engine.onTrackDidFinish = { [weak self] in
            self?.handleTrackEnded()
        }
        
        // Update Now Playing Center when engine updates
        engine.$currentTime
            .sink { [weak self] time in
                guard let self = self else { return }
                iOSNowPlayingCenter.shared.updateNowPlayingInfo(
                    track: self.currentTrack,
                    isPlaying: engine.isPlaying,
                    currentTime: time
                )
            }
            .store(in: &cancellables)
        
        engine.$isPlaying
            .sink { [weak self] playing in
                guard let self = self else { return }
                iOSNowPlayingCenter.shared.updateNowPlayingInfo(
                    track: self.currentTrack,
                    isPlaying: playing,
                    currentTime: engine.currentTime
                )
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Playback Core
    
    public func play(tracks: [iOSTrack], startingAt index: Int = 0) {
        guard !tracks.isEmpty, index >= 0, index < tracks.count else { return }
        
        let selected = tracks[index]
        let previousSlice = Array(tracks[0..<index])
        let upcomingSlice = Array(tracks[(index + 1)...])
        
        history = previousSlice
        unshuffledQueue = upcomingSlice
        
        if isShuffleEnabled {
            queue = upcomingSlice.shuffled()
        } else {
            queue = upcomingSlice
        }
        
        loadAndPlay(track: selected)
    }
    
    public func loadAndPlay(track: iOSTrack) {
        currentTrack = track
        iOSAudioEngine.shared.loadAndPlay(track: track)
        iOSNowPlayingCenter.shared.updateNowPlayingInfo(
            track: track,
            isPlaying: true,
            currentTime: 0
        )
    }
    
    public func play() {
        iOSAudioEngine.shared.play()
    }
    
    public func pause() {
        iOSAudioEngine.shared.pause()
    }
    
    public func togglePlayPause() {
        iOSAudioEngine.shared.togglePlayPause()
    }
    
    public func seek(to time: TimeInterval) {
        iOSAudioEngine.shared.seek(to: time)
    }
    
    // MARK: - Navigation
    
    public func nextTrack() {
        guard let current = currentTrack else { return }
        
        if repeatMode == .one {
            seek(to: 0)
            play()
            return
        }
        
        history.append(current)
        
        guard !queue.isEmpty else {
            if repeatMode == .all, !history.isEmpty {
                let allTracks = history
                history = []
                play(tracks: allTracks, startingAt: 0)
            } else {
                pause()
            }
            return
        }
        
        let next = queue.removeFirst()
        if let idx = unshuffledQueue.firstIndex(where: { $0.id == next.id }) {
            unshuffledQueue.remove(at: idx)
        }
        loadAndPlay(track: next)
    }
    
    public func previousTrack() {
        // If more than 3 seconds in, rewind to beginning
        if iOSAudioEngine.shared.currentTime > 3.0 {
            seek(to: 0)
            return
        }
        
        guard let prev = history.popLast() else {
            seek(to: 0)
            return
        }
        
        if let current = currentTrack {
            queue.insert(current, at: 0)
            unshuffledQueue.insert(current, at: 0)
        }
        loadAndPlay(track: prev)
    }
    
    private func handleTrackEnded() {
        nextTrack()
    }
    
    // MARK: - Shuffle & Repeat
    
    public func toggleShuffle() {
        isShuffleEnabled.toggle()
        if isShuffleEnabled {
            queue = queue.shuffled()
        } else {
            // Restore original canonical order for remaining songs
            let activeIds = Set(queue.map { $0.id })
            queue = unshuffledQueue.filter { activeIds.contains($0.id) }
        }
    }
    
    public func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }
    
    // MARK: - Queue Management
    
    public func insertNext(track: iOSTrack) {
        queue.insert(track, at: 0)
        unshuffledQueue.insert(track, at: 0)
    }
    
    public func appendToQueue(track: iOSTrack) {
        queue.append(track)
        unshuffledQueue.append(track)
    }
    
    public func playQueueItem(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        if let current = currentTrack {
            history.append(current)
        }
        let skipped = queue[0..<index]
        history.append(contentsOf: skipped)
        
        let target = queue[index]
        queue.removeSubrange(0...index)
        
        let activeIds = Set(queue.map { $0.id })
        unshuffledQueue.removeAll { !activeIds.contains($0.id) }
        
        loadAndPlay(track: target)
    }
    
    public func moveQueueItem(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        if !isShuffleEnabled {
            unshuffledQueue = queue
        }
    }
    
    public func removeQueueItem(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        let removed = queue.remove(at: index)
        unshuffledQueue.removeAll { $0.id == removed.id }
    }
    
    public func clearQueue() {
        queue.removeAll()
        unshuffledQueue.removeAll()
    }
}
