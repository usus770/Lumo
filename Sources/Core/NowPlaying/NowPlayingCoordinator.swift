import Foundation
import AppKit
import os.log

typealias NowPlayingState = ExternalPlayerState

/// Priority ranking for provider arbitration.
/// Higher value indicates higher priority when arbitrating ties or selecting candidates.
enum ProviderRank: Int, Comparable, Sendable {
    case browserExtension = 500
    case electronApp = 400
    case systemNowPlaying = 300
    case nativeApp = 200      // Apple Music, Spotify, VLC
    case chromeAppleScript = 100
    case localPlayer = 50
    case unknown = 0
    
    static func < (lhs: ProviderRank, rhs: ProviderRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Actor that coordinates, monitors, ranks, and de-duplicates all now-playing providers concurrently.
/// Emits a single, unified `AsyncStream<NowPlayingState?>` for the UI.
actor NowPlayingCoordinator {
    static let shared = NowPlayingCoordinator()
    
    // MARK: - Internal Candidate Tracking
    
    struct CandidateRecord: Sendable {
        let id: String
        let providerName: String
        let provider: NowPlayingProvider
        let rank: ProviderRank
        var state: ExternalPlayerState?
        var lastUpdated: Date
        var playbackStartedAt: Date?
        
        var isPlaying: Bool {
            state?.isPlaying == true
        }
    }
    
    private var candidates: [String: CandidateRecord] = [:]
    private var registeredProviders: [NowPlayingProvider] = []
    private var bridgeDelegates: [CoordinatorBridgeDelegate] = []
    
    private var preferredSource: String = "auto"
    private var isMonitoring = false
    private var pollTask: Task<Void, Never>?
    
    // Arbitrated state & winning provider
    private var currentArbitratedState: ExternalPlayerState?
    private var currentActiveProvider: NowPlayingProvider?
    
    // 3-second teardown / grace period task
    private var teardownTask: Task<Void, Never>?
    
    // Flicker debouncing task
    private var debounceTask: Task<Void, Never>?
    
    // Subscriber continuations
    private var continuations: [UUID: AsyncStream<NowPlayingState?>.Continuation] = [:]
    
    // MARK: - Initialization
    
    init() {
        LumoLogger.coordinator.info("NowPlayingCoordinator initialized.")
    }
    
    // MARK: - Configuration & Registration
    
    /// Registers all providers for concurrent monitoring and arbitration.
    func registerProviders(_ providers: [NowPlayingProvider]) {
        self.registeredProviders = providers
        self.bridgeDelegates.removeAll()
        self.candidates.removeAll()
        
        for provider in providers {
            let rank = Self.rank(for: provider)
            let id = provider.appName
            candidates[id] = CandidateRecord(
                id: id,
                providerName: provider.appName,
                provider: provider,
                rank: rank,
                state: nil,
                lastUpdated: Date(),
                playbackStartedAt: nil
            )
            
            let bridge = CoordinatorBridgeDelegate(coordinator: self, provider: provider)
            self.bridgeDelegates.append(bridge)
            provider.delegate = bridge
        }
        
        LumoLogger.coordinator.info("Registered \(providers.count) providers for concurrent arbitration.")
    }
    
    /// Maps a provider instance to its arbitration rank.
    static func rank(for provider: NowPlayingProvider) -> ProviderRank {
        if provider is BrowserExtensionProvider { return .browserExtension }
        if provider is YouTubeMusicAppProvider { return .electronApp }
        if provider is SystemNowPlayingProvider { return .systemNowPlaying }
        if provider is ChromeYouTubeMusicProvider { return .chromeAppleScript }
        if provider is AppleScriptProvider { return .nativeApp }
        if provider.appName.localizedCaseInsensitiveContains("extension") { return .browserExtension }
        if provider.appName.localizedCaseInsensitiveContains("electron") { return .electronApp }
        if provider.appName.localizedCaseInsensitiveContains("system") { return .systemNowPlaying }
        if provider.appName.localizedCaseInsensitiveContains("chrome") { return .chromeAppleScript }
        return .unknown
    }
    
    /// Sets user's pinned source preference ("auto", "extension", "electron", "system", "chrome", "apple_music", "spotify").
    func setPreferredSource(_ source: String) {
        self.preferredSource = source
        LumoLogger.coordinator.info("User preferred source updated to: \(source, privacy: .public)")
        arbitrate()
    }
    
    func getPreferredSource() -> String {
        self.preferredSource
    }
    
    func getCurrentState() -> ExternalPlayerState? {
        self.currentArbitratedState
    }
    
    func getActiveProviderName() -> String? {
        self.currentActiveProvider?.appName
    }
    
    func getAllCandidates() -> [CandidateRecord] {
        Array(candidates.values)
    }
    
    // MARK: - Monitoring Lifecycle
    
    /// Starts concurrent monitoring across all registered providers.
    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        LumoLogger.coordinator.info("Starting concurrent monitoring across all providers.")
        
        for provider in registeredProviders {
            provider.startMonitoring()
        }
        
        startPollingFallback()
    }
    
    /// Stops monitoring across all registered providers.
    func stop() {
        isMonitoring = false
        pollTask?.cancel()
        pollTask = nil
        teardownTask?.cancel()
        teardownTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        
        for provider in registeredProviders {
            provider.stopMonitoring()
        }
        
        LumoLogger.coordinator.info("NowPlayingCoordinator stopped.")
    }
    
    private func startPollingFallback() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second fallback polling
                guard !Task.isCancelled else { break }
                await self?.pollAvailableProviders()
            }
        }
    }
    
    private func pollAvailableProviders() async {
        for provider in registeredProviders {
            guard provider.isAvailable else { continue }
            
            // Only pull-poll providers that do not have active push-event streams
            var shouldPoll = false
            if let scriptProvider = provider as? AppleScriptProvider {
                shouldPoll = scriptProvider.isRunning
            } else if let chromeProvider = provider as? ChromeYouTubeMusicProvider {
                shouldPoll = chromeProvider.isRunning
            } else if let ytProvider = provider as? YouTubeMusicAppProvider {
                shouldPoll = ytProvider.isRunning
            } else if let systemProvider = provider as? SystemNowPlayingProvider {
                shouldPoll = systemProvider.isAvailable
            }
            
            if shouldPoll {
                if let state = await provider.fetchState() {
                    self.handleProviderUpdate(provider: provider, state: state)
                }
            }
        }
    }
    
    // MARK: - State Update Handling
    
    /// Handles updates received from any provider.
    func handleProviderUpdate(provider: NowPlayingProvider, state: ExternalPlayerState?) {
        let id = provider.appName
        guard var record = candidates[id] else {
            // Unregistered provider update; register dynamically
            let rank = Self.rank(for: provider)
            var newRecord = CandidateRecord(
                id: id,
                providerName: provider.appName,
                provider: provider,
                rank: rank,
                state: state,
                lastUpdated: Date(),
                playbackStartedAt: state?.isPlaying == true ? Date() : nil
            )
            if state?.isPlaying == true {
                newRecord.playbackStartedAt = Date()
            }
            candidates[id] = newRecord
            arbitrate()
            return
        }
        
        let wasPlaying = record.isPlaying
        let isNowPlaying = state?.isPlaying == true
        
        record.state = state
        record.lastUpdated = Date()
        
        if isNowPlaying && !wasPlaying {
            // Track when playback started for freshness arbitration
            record.playbackStartedAt = Date()
        }
        
        candidates[id] = record
        arbitrate()
    }
    
    // MARK: - Arbitration Engine
    
    /// Arbitrates among all candidate provider states.
    /// Priority: User Pinned Source > Actively Playing (most recent start > rank) > Most Recent Paused > Teardown
    private func arbitrate() {
        let activeRecords = candidates.values.filter { $0.state != nil }
        var chosenRecord: CandidateRecord? = nil
        
        // 1. Check user-pinned preferred source
        if preferredSource != "auto" {
            if let pinned = activeRecords.first(where: { matchesPreferredSource(record: $0, key: preferredSource) }) {
                let anyPlaying = activeRecords.contains { $0.isPlaying }
                if pinned.isPlaying || !anyPlaying {
                    chosenRecord = pinned
                }
            }
        }
        
        // 2. Pick among actively playing providers
        if chosenRecord == nil {
            let playingRecords = activeRecords.filter { $0.isPlaying }
            if !playingRecords.isEmpty {
                if playingRecords.count == 1 {
                    chosenRecord = playingRecords.first
                } else {
                    // Several are playing: prefer the most recently started, breaking ties by rank
                    chosenRecord = playingRecords.max { a, b in
                        let timeA = a.playbackStartedAt ?? a.lastUpdated
                        let timeB = b.playbackStartedAt ?? b.lastUpdated
                        let diff = timeA.timeIntervalSince(timeB)
                        if abs(diff) > 1.0 {
                            return timeA < timeB // Most recently started wins
                        } else {
                            return a.rank < b.rank // Higher rank wins
                        }
                    }
                }
            }
        }
        
        // 3. If none are actively playing, pick the most recent paused candidate
        if chosenRecord == nil {
            if !activeRecords.isEmpty {
                chosenRecord = activeRecords.max { a, b in
                    let diff = a.lastUpdated.timeIntervalSince(b.lastUpdated)
                    if abs(diff) > 2.0 {
                        return a.lastUpdated < b.lastUpdated
                    } else {
                        return a.rank < b.rank
                    }
                }
            }
        }
        
        // 4. Handle result
        guard let winner = chosenRecord, var baseState = winner.state else {
            // All providers report nil / closed
            scheduleTeardownIfActive()
            return
        }
        
        // Cancel teardown timer since we have a valid state
        teardownTask?.cancel()
        teardownTask = nil
        
        // 5. De-duplicate and merge with other candidate states
        for candidate in activeRecords where candidate.id != winner.id {
            if let otherState = candidate.state, Self.isDuplicate(lhs: baseState, rhs: otherState) {
                baseState = Self.mergeDuplicate(
                    primary: baseState,
                    secondary: otherState,
                    primaryRank: winner.rank,
                    secondaryRank: candidate.rank
                )
            }
        }
        
        // Resolve active provider instance
        currentActiveProvider = winner.provider
        
        // 6. Handle track changes vs micro-debouncing
        let isTrackChange = currentArbitratedState?.trackName != baseState.trackName ||
                            currentArbitratedState?.artistName != baseState.artistName ||
                            currentArbitratedState?.isPlaying != baseState.isPlaying
        
        if isTrackChange {
            // Immediate update on track change or play/pause transition!
            debounceTask?.cancel()
            debounceTask = nil
            emitState(baseState)
        } else {
            // Micro-debounce progress / currentTime updates (50ms) to prevent UI stutter
            debounceTask?.cancel()
            debounceTask = Task { [weak self, baseState] in
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                await self?.emitState(baseState)
            }
        }
    }
    
    // MARK: - 3-Second Teardown / Grace Period
    
    private func scheduleTeardownIfActive() {
        guard currentArbitratedState != nil else { return }
        guard teardownTask == nil else { return }
        
        LumoLogger.coordinator.info("No active playback detected; starting 3.0s grace period before clearing state.")
        teardownTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            guard !Task.isCancelled else { return }
            await self?.finishTeardown()
        }
    }
    
    private func finishTeardown() {
        LumoLogger.coordinator.info("3.0s grace period expired. Clearing Now Playing state.")
        currentArbitratedState = nil
        currentActiveProvider = nil
        teardownTask = nil
        emitState(nil)
    }
    
    // MARK: - De-Duplication & Field Merging
    
    /// Matches two states to determine if they represent the same playing track.
    /// Matching criteria: Title + Artist match, Duration within 2.0s tolerance.
    static func isDuplicate(lhs: ExternalPlayerState, rhs: ExternalPlayerState) -> Bool {
        guard let t1 = lhs.trackName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let t2 = rhs.trackName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !t1.isEmpty, !t2.isEmpty else {
            return false
        }
        
        // Title matching: exact equality or substring containment (e.g. video title vs song title)
        let titleMatches = (t1 == t2) || t1.contains(t2) || t2.contains(t1)
        guard titleMatches else { return false }
        
        // Artist matching if both are populated
        if let a1 = lhs.artistName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let a2 = rhs.artistName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !a1.isEmpty, !a2.isEmpty {
            let artistMatches = (a1 == a2) || a1.contains(a2) || a2.contains(a1)
            if !artistMatches { return false }
        }
        
        // Duration matching within 2 seconds
        if lhs.duration > 0 && rhs.duration > 0 {
            if abs(lhs.duration - rhs.duration) > 2.0 {
                return false
            }
        }
        
        return true
    }
    
    /// Merges the best fields between duplicate states.
    /// E.g. high-resolution artwork from extension + system playback state.
    static func mergeDuplicate(
        primary: ExternalPlayerState,
        secondary: ExternalPlayerState,
        primaryRank: ProviderRank,
        secondaryRank: ProviderRank
    ) -> ExternalPlayerState {
        var merged = primary
        
        // Artwork merging: prefer the larger/higher-res artwork data or non-nil over nil
        let primaryArtCount = merged.artworkData?.count ?? 0
        let secondaryArtCount = secondary.artworkData?.count ?? 0
        if secondaryArtCount > primaryArtCount {
            merged.artworkData = secondary.artworkData
        }
        
        // Source URL / videoId: prefer non-nil
        if merged.sourceURL == nil || merged.sourceURL?.isEmpty == true {
            merged.sourceURL = secondary.sourceURL
        }
        
        // Album name: prefer non-empty
        if (merged.albumName == nil || merged.albumName?.isEmpty == true), let alb = secondary.albumName, !alb.isEmpty {
            merged.albumName = alb
        }
        
        // Artist name: prefer clean non-empty artist name
        if (merged.artistName == nil || merged.artistName?.isEmpty == true), let art = secondary.artistName, !art.isEmpty {
            merged.artistName = art
        }
        
        // High fidelity time precision from extension or system
        if secondaryRank > primaryRank && secondary.isPlaying == primary.isPlaying {
            merged.currentTime = secondary.currentTime
            merged.playbackRate = secondary.playbackRate
        }
        
        return merged
    }
    
    private func matchesPreferredSource(record: CandidateRecord, key: String) -> Bool {
        switch key {
        case "extension":
            return record.rank == .browserExtension || record.providerName.localizedCaseInsensitiveContains("extension")
        case "electron":
            return record.rank == .electronApp || record.providerName.localizedCaseInsensitiveContains("electron")
        case "system":
            return record.rank == .systemNowPlaying || record.providerName.localizedCaseInsensitiveContains("system")
        case "chrome":
            return record.rank == .chromeAppleScript || record.providerName.localizedCaseInsensitiveContains("chrome")
        case "apple_music":
            return record.providerName.localizedCaseInsensitiveContains("music")
        case "spotify":
            return record.providerName.localizedCaseInsensitiveContains("spotify")
        default:
            return false
        }
    }
    
    // MARK: - Stream Consumption
    
    /// AsyncStream yielding unified NowPlayingState updates whenever arbitrated state changes.
    var stateStream: AsyncStream<NowPlayingState?> {
        AsyncStream { continuation in
            let id = UUID()
            self.registerSubscriber(id: id, continuation: continuation)
            
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeSubscriber(id: id)
                }
            }
        }
    }
    
    private func registerSubscriber(id: UUID, continuation: AsyncStream<NowPlayingState?>.Continuation) {
        continuations[id] = continuation
        // Emit current arbitrated state immediately
        continuation.yield(currentArbitratedState)
    }
    
    private func removeSubscriber(id: UUID) {
        continuations.removeValue(forKey: id)
    }
    
    private func emitState(_ state: ExternalPlayerState?) {
        currentArbitratedState = state
        for (_, continuation) in continuations {
            continuation.yield(state)
        }
        
        // Notify NotificationCenter observers for backward compatibility
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .nowPlayingProviderDidUpdate, object: nil)
        }
    }
    
    // MARK: - Playback Transport Commands
    
    func playPause() {
        currentActiveProvider?.playPause()
    }
    
    func nextTrack() {
        currentActiveProvider?.nextTrack()
    }
    
    func previousTrack() {
        currentActiveProvider?.previousTrack()
    }
    
    func seek(to time: TimeInterval) {
        currentActiveProvider?.seek(to: time)
    }
}

// MARK: - Bridge Delegate

/// Thread-safe delegate bridge forwarding provider callbacks into the NowPlayingCoordinator actor.
final class CoordinatorBridgeDelegate: NowPlayingProviderDelegate, @unchecked Sendable {
    private weak var coordinator: NowPlayingCoordinator?
    private let provider: NowPlayingProvider
    
    init(coordinator: NowPlayingCoordinator, provider: NowPlayingProvider) {
        self.coordinator = coordinator
        self.provider = provider
    }
    
    func nowPlayingProvider(_ provider: NowPlayingProvider, didUpdateState state: ExternalPlayerState?) {
        Task { [weak coordinator, provider] in
            await coordinator?.handleProviderUpdate(provider: provider, state: state)
        }
    }
}
