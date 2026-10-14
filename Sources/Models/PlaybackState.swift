import Foundation
import SwiftUI
import Combine

/// Observable playback state shared across the UI.
@Observable
final class PlaybackState: @unchecked Sendable {
    /// Shared singleton instance for global access (e.g., menu bar popover).
    static let shared = PlaybackState()
    
    private init() {
        setupEngineSubscriptions()
        // Apply persisted settings on launch
        SettingsStore.shared.applyAll()
        // Connect media keys / Control Strip
        NowPlayingInfoPublisher.shared.connect(to: self)
    }
    
    // MARK: - Current Track
    
    var currentTrack: TrackInfo? {
        didSet {
            if let track = currentTrack {
                loadAndPlay(track: track)
                NowPlayingInfoPublisher.shared.update(
                    track: track,
                    isPlaying: true,
                    currentTime: 0,
                    rate: SettingsStore.shared.playbackSpeed
                )
                NowPlayingSnapshot.shared.updateLocal(
                    track: track,
                    isPlaying: true,
                    currentTime: 0,
                    duration: track.duration,
                    rate: Double(SettingsStore.shared.playbackSpeed)
                )
            } else {
                Task { await AudioEngine.shared.pause() }
                isPlaying = false
                currentTime = 0
                duration = 0
                NowPlayingInfoPublisher.shared.clear()
                NowPlayingSnapshot.shared.updateLocal(
                    track: nil,
                    isPlaying: false,
                    currentTime: 0,
                    duration: 0,
                    rate: Double(SettingsStore.shared.playbackSpeed)
                )
            }
        }
    }
    
    var isPlaying: Bool = false {
        didSet {
            Task {
                if isPlaying {
                    await AudioEngine.shared.play()
                } else {
                    await AudioEngine.shared.pause()
                }
            }
            // Update system now-playing state
            NowPlayingInfoPublisher.shared.update(
                track: currentTrack,
                isPlaying: isPlaying,
                currentTime: currentTime,
                rate: SettingsStore.shared.playbackSpeed
            )
            NowPlayingSnapshot.shared.updateLocalPlayback(isPlaying: isPlaying, currentTime: currentTime)
        }
    }
    
    var currentTime: TimeInterval = 0 {
        didSet {
            NowPlayingSnapshot.shared.updateLocalTime(currentTime: currentTime)
            // Throttle now-playing updates to every 0.5 s
            let t = currentTime
            if abs(t - _lastReportedTime) > 0.5 {
                _lastReportedTime = t
                NowPlayingInfoPublisher.shared.update(
                    track: currentTrack,
                    isPlaying: isPlaying,
                    currentTime: t,
                    rate: SettingsStore.shared.playbackSpeed
                )
            }
        }
    }
    private var _lastReportedTime: TimeInterval = 0
    var duration: TimeInterval = 0
    
    var volume: Float = AppConstants.Playback.defaultVolume {
        didSet {
            Task { await AudioEngine.shared.setVolume(isMuted ? 0 : volume) }
        }
    }
    
    var isMuted: Bool = false {
        didSet {
            Task { await AudioEngine.shared.setVolume(isMuted ? 0 : volume) }
        }
    }
    
    var isLoading: Bool = false
    
    // MARK: - Queue
    
    var queue: [TrackInfo] = []
    var unshuffledQueue: [TrackInfo] = []
    var history: [TrackInfo] = []
    
    var isShuffleEnabled: Bool = false
    
    var repeatMode: RepeatMode = .off
    
    // MARK: - Source
    
    var source: PlaybackSource = .local
    var sourceAppName: String?
    var sourceAppIcon: NSImage?
    
    // MARK: - Subscriptions
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setupEngineSubscriptions() {
        // Observe time updates
        AudioEngine.shared.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.currentTime = time
            }
            .store(in: &cancellables)
        
        // Observe track end
        NotificationCenter.default.publisher(for: .trackDidEnd)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleTrackEnded()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Engine Integration
    
    private func loadAndPlay(track: TrackInfo) {
        let url = URL(fileURLWithPath: track.filePath)
        self.isLoading = true
        Task {
            do {
                try await AudioEngine.shared.load(url: url)
                await MainActor.run {
                    self.duration = track.duration
                    self.currentTime = 0
                    self.isPlaying = true // This setter triggers engine.play()
                    self.isLoading = false
                    NowPlayingSnapshot.shared.updateLocal(
                        track: track,
                        isPlaying: true,
                        currentTime: 0,
                        duration: track.duration,
                        rate: Double(SettingsStore.shared.playbackSpeed)
                    )
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
                print("Failed to load track: \(error)")
            }
        }
    }
    
    private func handleTrackEnded() {
        if repeatMode == .one {
            // Re-play current
            seek(to: 0)
            isPlaying = true
        } else {
            nextTrack(isAutoAdvance: true)
        }
    }
    
    // MARK: - Queue & Playlist Playback
    
    /// Starts playback from a list of tracks, beginning at the specified index.
    func play(tracks: [TrackInfo], startingAt index: Int = 0) {
        guard !tracks.isEmpty, index >= 0, index < tracks.count else { return }
        
        let targetTrack = tracks[index]
        let priorTracks = Array(tracks[0..<index])
        let upcomingTracks = Array(tracks[(index + 1)...])
        
        history = priorTracks
        unshuffledQueue = upcomingTracks
        
        if isShuffleEnabled {
            queue = upcomingTracks.shuffled()
        } else {
            queue = upcomingTracks
        }
        
        currentTrack = targetTrack
        isPlaying = true
    }
    
    /// Plays a standalone track outside a list.
    func play(singleTrack: TrackInfo) {
        history.removeAll()
        unshuffledQueue.removeAll()
        queue.removeAll()
        currentTrack = singleTrack
        isPlaying = true
    }
    
    /// Inserts a track to be played right after the current track.
    func insertNext(track: TrackInfo) {
        queue.insert(track, at: 0)
        unshuffledQueue.insert(track, at: 0)
    }
    
    /// Appends a track to the end of the upcoming queue.
    func appendToQueue(track: TrackInfo) {
        queue.append(track)
        unshuffledQueue.append(track)
    }
    
    /// Plays a specific item from the queue, moving preceding items into history.
    func playQueueItem(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        
        if let current = currentTrack {
            history.append(current)
        }
        
        if index > 0 {
            let skipped = Array(queue[0..<index])
            history.append(contentsOf: skipped)
            for item in skipped {
                if let uIdx = unshuffledQueue.firstIndex(where: { $0.id == item.id }) {
                    unshuffledQueue.remove(at: uIdx)
                }
            }
        }
        
        let target = queue[index]
        queue.removeSubrange(0...index)
        if let uIdx = unshuffledQueue.firstIndex(where: { $0.id == target.id }) {
            unshuffledQueue.remove(at: uIdx)
        }
        
        currentTrack = target
        isPlaying = true
    }
    
    /// Moves items in the queue (drag-and-drop reordering: "put one song over another song to play").
    func moveQueueItem(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        if !isShuffleEnabled {
            unshuffledQueue = queue
        }
    }
    
    /// Removes a specific track from the queue.
    func removeQueueItem(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        let removed = queue.remove(at: index)
        if let uIdx = unshuffledQueue.firstIndex(where: { $0.id == removed.id }) {
            unshuffledQueue.remove(at: uIdx)
        }
    }
    
    /// Removes multiple tracks from the queue by IndexSet.
    func removeQueueItems(at offsets: IndexSet) {
        let removed = offsets.compactMap { $0 < queue.count ? queue[$0] : nil }
        queue.remove(atOffsets: offsets)
        for item in removed {
            if let uIdx = unshuffledQueue.firstIndex(where: { $0.id == item.id }) {
                unshuffledQueue.remove(at: uIdx)
            }
        }
    }
    
    /// Clears all upcoming tracks.
    func clearQueue() {
        queue.removeAll()
        unshuffledQueue.removeAll()
    }
    
    /// Re-shuffles the upcoming queue.
    func shuffleQueue() {
        queue.shuffle()
    }
    
    // MARK: - Transport Controls
    
    func togglePlayPause() {
        isPlaying.toggle()
    }
    
    func nextTrack(isAutoAdvance: Bool = false) {
        if let current = currentTrack {
            history.append(current)
        }
        
        if !queue.isEmpty {
            let next = queue.removeFirst()
            if let idx = unshuffledQueue.firstIndex(where: { $0.id == next.id }) {
                unshuffledQueue.remove(at: idx)
            }
            currentTrack = next
        } else {
            if repeatMode == .all && (!history.isEmpty || currentTrack != nil) {
                // Loop back to history start
                var fullList = history
                history.removeAll()
                if let first = fullList.first {
                    fullList.removeFirst()
                    unshuffledQueue = fullList
                    queue = isShuffleEnabled ? fullList.shuffled() : fullList
                    currentTrack = first
                } else {
                    currentTrack = nil
                }
            } else {
                currentTrack = nil
            }
        }
    }
    
    func previousTrack() {
        // If we are more than 3 seconds in, restart track
        if currentTime > 3.0 || history.isEmpty {
            seek(to: 0)
            if !isPlaying { isPlaying = true }
        } else if let prev = history.popLast() {
            if let current = currentTrack {
                queue.insert(current, at: 0)
                unshuffledQueue.insert(current, at: 0)
            }
            currentTrack = prev
        }
    }
    
    func seek(to time: TimeInterval) {
        let maxDur = duration > 0 ? duration : (currentTrack?.duration ?? time)
        let safeTime = min(max(time, 0), maxDur > 0 ? maxDur : time)
        currentTime = safeTime
        NowPlayingSnapshot.shared.updateLocalTime(currentTime: safeTime)
        Task {
            await AudioEngine.shared.seek(to: safeTime)
        }
    }
    
    func adjustVolume(by delta: Float) {
        volume = min(max(volume + delta, 0), 1)
        if isMuted && volume > 0 {
            isMuted = false
        }
    }
    
    func toggleShuffle() {
        isShuffleEnabled.toggle()
        if isShuffleEnabled {
            // Keep unshuffledQueue as original reference, shuffle active queue
            queue = queue.shuffled()
        } else {
            // Restore original ordering for remaining items
            let currentIds = Set(queue.map(\.id))
            let restored = unshuffledQueue.filter { currentIds.contains($0.id) }
            let restoredIds = Set(restored.map(\.id))
            let extras = queue.filter { !restoredIds.contains($0.id) }
            queue = restored + extras
        }
    }
    
    func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }
    
    func toggleMute() {
        isMuted.toggle()
    }
    
    // MARK: - Progress
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var formattedCurrentTime: String {
        Self.formatTime(currentTime)
    }
    
    var formattedDuration: String {
        Self.formatTime(duration)
    }
    
    var formattedRemainingTime: String {
        let remaining = max(duration - currentTime, 0)
        return "-" + Self.formatTime(remaining)
    }
    
    static func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(time, 0))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Supporting Types

/// Lightweight track info for display (avoids referencing SwiftData model on non-main threads).
struct TrackInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    var queueId: UUID = UUID()
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artworkData: Data?
    let filePath: String
    let fileExtension: String
    var lyricsText: String? = nil
    var hasSyncedLyrics: Bool = false
    
    init(
        id: UUID,
        queueId: UUID = UUID(),
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        artworkData: Data?,
        filePath: String,
        fileExtension: String,
        lyricsText: String? = nil,
        hasSyncedLyrics: Bool = false
    ) {
        self.id = id
        self.queueId = queueId
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkData = artworkData
        self.filePath = filePath
        self.fileExtension = fileExtension
        self.lyricsText = lyricsText
        self.hasSyncedLyrics = hasSyncedLyrics
    }
    
    var formattedDuration: String {
        PlaybackState.formatTime(duration)
    }
    
    /// Placeholder for when nothing is playing.
    static let empty = TrackInfo(
        id: UUID(),
        queueId: UUID(),
        title: "Not Playing",
        artist: "",
        album: "",
        duration: 0,
        artworkData: nil,
        filePath: "",
        fileExtension: "",
        lyricsText: nil,
        hasSyncedLyrics: false
    )
}

/// Repeat mode options.
enum RepeatMode: String, Sendable {
    case off
    case all
    case one
    
    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
    
    var icon: String {
        switch self {
        case .off: "repeat"
        case .all: "repeat"
        case .one: "repeat.1"
        }
    }
    
    var isActive: Bool {
        self != .off
    }
}

/// Source of the current playback.
enum PlaybackSource: String, Sendable {
    case local = "Lumo"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case systemWide = "System"
    case unknown = "Unknown"
}
