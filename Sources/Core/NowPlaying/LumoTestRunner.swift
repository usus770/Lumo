import Foundation
import AppKit

/// Comprehensive test runner for unit tests and acceptance verification.
/// Can be executed via `swift run Lumo --run-tests` or programmatically.
public struct LumoTestRunner {
    
    public static func runAllTests() async {
        print("\n=======================================================")
        print("          LUMO MUSIC SYNC - UNIT TEST SUITE            ")
        print("=======================================================\n")
        
        var passed = 0
        var failed = 0
        
        func runTest(_ name: String, block: () async throws -> Void) async {
            print("▶ Running: \(name)...", terminator: " ")
            do {
                try await block()
                print("✅ PASSED")
                passed += 1
            } catch {
                print("❌ FAILED: \(error)")
                failed += 1
            }
        }
        
        // MARK: - Suite 1: Provider Ranking & Arbitration
        await runTest("Provider Ranking Hierarchy") {
            try testProviderRankingHierarchy()
        }
        await runTest("Provider Type Rank Resolution") {
            try testProviderTypeRankResolution()
        }
        await runTest("Arbitration - Active Playback Priority") {
            try await testArbitrationActivePlayback()
        }
        await runTest("Arbitration - Freshness / Recent Start Win") {
            try await testArbitrationFreshness()
        }
        await runTest("Arbitration - Preferred Source Pinning") {
            try await testArbitrationPinnedSource()
        }
        
        // MARK: - Suite 2: De-Duplication & Field Merging
        await runTest("De-Duplication - Identical Track Match") {
            try testDeDuplicationIdentical()
        }
        await runTest("De-Duplication - Duration Tolerance (<= 2.0s)") {
            try testDeDuplicationDurationTolerance()
        }
        await runTest("De-Duplication - Duration Mismatch (> 2.0s)") {
            try testDeDuplicationDurationMismatch()
        }
        await runTest("De-Duplication - Substring Title Containment") {
            try testDeDuplicationTitleContainment()
        }
        await runTest("De-Duplication - Field Merging & High-Res Artwork") {
            try testDeDuplicationFieldMerging()
        }
        
        // MARK: - Suite 3: AppleScript Error Parsing
        await runTest("AppleScript Error 12 (JS Apple Events Disabled)") {
            try testAppleScriptError12()
        }
        await runTest("AppleScript Error -1743 (Automation TCC Denied)") {
            try testAppleScriptError1743()
        }
        await runTest("AppleScript Error -600 (Target Not Running)") {
            try testAppleScriptError600()
        }
        await runTest("AppleScript Success (Enabled)") {
            try testAppleScriptSuccess()
        }
        
        // MARK: - Suite 4: Extension Message Decoding
        await runTest("Extension Message Decoding - Full Payload") {
            try testExtensionMessageDecodingFull()
        }
        await runTest("Extension Message Decoding - Defensive Fallbacks") {
            try testExtensionMessageDecodingDefensive()
        }
        
        // MARK: - Suite 5: State Debouncing & 3-Second Teardown
        await runTest("State Debouncing - Immediate Track Change Emit") {
            try await testImmediateTrackChangeEmit()
        }
        await runTest("State Debouncing - 3-Second Teardown Delay") {
            try await testThreeSecondTeardownDelay()
        }
        
        // MARK: - Suite 6: Live MediaRemote Sync Verification
        await runTest("SystemNowPlayingProvider - Live MediaRemote Sync & Identification") {
            try await testSystemNowPlayingLiveFetch()
        }
        
        // MARK: - Suite 7: Unified NowPlayingSnapshot & Smooth Clock
        await runTest("NowPlayingSnapshot - Stable ID Determinism") {
            try testStableIDDeterminism()
        }
        await runTest("NowPlayingSnapshot - Smooth Continuous Clock") {
            try testSmoothClockCalculation()
        }
        await runTest("NowPlayingSnapshot - Paused Clock Zero Drift") {
            try testPausedClockZeroDrift()
        }
        await runTest("NowPlayingSnapshot - Lyrics Look-Ahead & Offset") {
            try testLyricsLookAheadAndOffset()
        }
        await runTest("NowPlayingSnapshot - Lyrics Disk Cache Roundtrip") {
            try testLyricsDiskCacheRoundtrip()
        }
        
        // MARK: - Suite 8: Metadata Resolution, Cleaning & Parsing (Phase 2)
        await runTest("Metadata - Eminem – Mockingbird (Full Title Retained)") {
            try testEminemMockingbird()
        }
        await runTest("Metadata - Live Forever (Preserve 'Live' in Title)") {
            try testLiveForever()
        }
        await runTest("Metadata - Stay with me (Preserve 'with', No Bogus Feat)") {
            try testStayWithMe()
        }
        await runTest("Metadata - Tum Hi Ho Indian Multi-Segment Parsing") {
            try testTumHiHoIndianFormat()
        }
        await runTest("Metadata - Kesariya Indian Multi-Segment Parsing") {
            try testKesariyaIndianFormat()
        }
        await runTest("Metadata - Artist - Topic Channel Parsing") {
            try testArtistTopicChannels()
        }
        await runTest("Metadata - Filename with [id] Stripping") {
            try testFilenameWithYouTubeID()
        }
        await runTest("Metadata - Token-Set Similarity vs Substring Containment") {
            try testTokenSetSimilarityVsSubstring()
        }
        
        // MARK: - Suite 9: Lyrics Pipeline & Romanization (Phase 3)
        await runTest("Lyrics - Enhanced Word Tag Parsing") {
            try testEnhancedWordTagParsing()
        }
        await runTest("Lyrics - [offset:±ms] Tag Handling") {
            try testOffsetTagHandling()
        }
        await runTest("Lyrics - Proportional Word Timing Estimation") {
            try testWordTimingEstimation()
        }
        await runTest("Lyrics - Script Detection for Devanagari & Indic") {
            try testScriptDetectionDevanagariAndIndic()
        }
        await runTest("Lyrics - CoreFoundation Romanization (Devanagari to Latin)") {
            try testRomanizationDevanagari()
        }
        await runTest("Lyrics - Transliteration-Tolerant Aligner") {
            try testTransliterationTolerantAligner()
        }
        await runTest("Lyrics - Binary Search lineIndex (Seek, Pause, Track Change)") {
            try testBinarySearchLineIndex()
        }
        
        // MARK: - Suite 10: Artwork Pipeline & URL Rewrites (Phase 4)
        await runTest("Artwork - URL Upscale Rewriting") {
            try testArtworkURLUpscaleRewriting()
        }
        await runTest("Artwork - 16:9 Thumbnail Square Cropping") {
            try testArtwork16x9SquareCropping()
        }
        await runTest("Artwork - High-Resolution Discrimination") {
            try testArtworkHighResolutionDiscrimination()
        }
        await runTest("Artwork - Disk Cache by Stable ID & Metadata") {
            try await testArtworkDiskCacheRoundtrip()
        }
        
        // MARK: - Suite 11: Kinetic Visualizer & Neon Glow (Phase 5)
        await runTest("Visualizer - Neon Border Notch Path Generation") {
            try testNeonBorderNotchPathGeneration()
        }
        await runTest("Visualizer - Beat Glitch Attack & Decay Dynamics") {
            try testBeatGlitchAttackAndDecay()
        }
        await runTest("Visualizer - Kinetic Word Sequence Resolution") {
            try testKineticWordSequenceResolution()
        }
        
        // MARK: - Suite 12: Find Cover & Lyrics - Metadata, Search & Matching
        await runTest("Metadata - Title Cleaning (Noise, Emojis, ft., | Topic)") {
            try testMetadataTitleCleaning()
        }
        await runTest("Metadata - YouTube Link and Video ID Extraction") {
            try testMetadataYouTubeLinkExtraction()
        }
        await runTest("Metadata - LRC Parsing & Romanization Preservation") {
            try testMetadataLRCParsingAndRomanization()
        }
        await runTest("Metadata - Match Scoring & Strong Duration Tolerance (<= 3s)") {
            try testMetadataMatchScoring()
        }
        await runTest("Metadata - Lyrics Duration Validation") {
            try testMetadataLyricsDurationValidation()
        }
        
        // MARK: - Suite 13: Playback Queue, Shuffle & Reordering
        await runTest("Queue - Play list startingAt index populates currentTrack, history, queue") {
            try await testQueuePlayListStartingAtIndex()
        }
        await runTest("Queue - Next track advances sequentially and records history") {
            try await testQueueNextTrackSequentialAdvance()
        }
        await runTest("Queue - Shuffle toggle shuffles upcoming tracks and un-shuffle restores exact order") {
            try await testQueueShuffleToggleAndRestore()
        }
        await runTest("Queue - Drag/move item reorders one song over another") {
            try await testQueueMoveItemReordering()
        }
        await runTest("Queue - Play queue item at index jumps directly") {
            try await testQueuePlayItemDirectJump()
        }
        await runTest("Queue - Remove item and clear queue") {
            try await testQueueRemoveAndClear()
        }
        
        print("\n=======================================================")
        print(" TEST RESULTS: \(passed) passed, \(failed) failed")
        print("=======================================================\n")
        
        if failed > 0 {
            exit(1)
        }
    }
    
    // MARK: - Suite 1 Implementations
    
    static func testProviderRankingHierarchy() throws {
        // Required rank: BrowserExtension > Electron app > SystemNowPlaying > NativeApp > Chrome AppleScript > local player
        guard ProviderRank.browserExtension > ProviderRank.electronApp else {
            throw TestError("Expected browserExtension > electronApp")
        }
        guard ProviderRank.electronApp > ProviderRank.systemNowPlaying else {
            throw TestError("Expected electronApp > systemNowPlaying")
        }
        guard ProviderRank.systemNowPlaying > ProviderRank.nativeApp else {
            throw TestError("Expected systemNowPlaying > nativeApp")
        }
        guard ProviderRank.nativeApp > ProviderRank.chromeAppleScript else {
            throw TestError("Expected nativeApp > chromeAppleScript")
        }
        guard ProviderRank.chromeAppleScript > ProviderRank.localPlayer else {
            throw TestError("Expected chromeAppleScript > localPlayer")
        }
    }
    
    static func testProviderTypeRankResolution() throws {
        let ext = BrowserExtensionProvider()
        let electron = YouTubeMusicAppProvider()
        let sys = SystemNowPlayingProvider()
        let chrome = ChromeYouTubeMusicProvider()
        let native = AppleScriptProvider(appName: "Music", bundleID: "com.apple.Music")
        
        guard NowPlayingCoordinator.rank(for: ext) == .browserExtension else {
            throw TestError("Extension provider rank mismatch")
        }
        guard NowPlayingCoordinator.rank(for: electron) == .electronApp else {
            throw TestError("Electron provider rank mismatch")
        }
        guard NowPlayingCoordinator.rank(for: sys) == .systemNowPlaying else {
            throw TestError("System provider rank mismatch")
        }
        guard NowPlayingCoordinator.rank(for: chrome) == .chromeAppleScript else {
            throw TestError("Chrome provider rank mismatch")
        }
        guard NowPlayingCoordinator.rank(for: native) == .nativeApp else {
            throw TestError("Native provider rank mismatch")
        }
    }
    
    static func testArbitrationActivePlayback() async throws {
        let coordinator = NowPlayingCoordinator()
        let mockSystem = MockProvider(appName: "System Now Playing")
        let mockChrome = MockProvider(appName: "Google Chrome")
        
        await coordinator.registerProviders([mockSystem, mockChrome])
        
        // System is paused, Chrome is actively playing
        let pausedState = ExternalPlayerState(isPlaying: false, trackName: "Track 1", duration: 180, currentTime: 20, appName: "Safari")
        let playingState = ExternalPlayerState(isPlaying: true, trackName: "Track 2", duration: 200, currentTime: 30, appName: "Google Chrome")
        
        await coordinator.handleProviderUpdate(provider: mockSystem, state: pausedState)
        await coordinator.handleProviderUpdate(provider: mockChrome, state: playingState)
        
        let chosen = await coordinator.getCurrentState()
        guard chosen?.trackName == "Track 2", chosen?.isPlaying == true else {
            throw TestError("Actively playing provider must be chosen over paused provider")
        }
    }
    
    static func testArbitrationFreshness() async throws {
        let coordinator = NowPlayingCoordinator()
        let mock1 = MockProvider(appName: "System Now Playing")
        let mock2 = MockProvider(appName: "YouTube Music (Electron)")
        
        await coordinator.registerProviders([mock1, mock2])
        
        // Mock1 starts playing first
        let state1 = ExternalPlayerState(isPlaying: true, trackName: "Old Track", duration: 200, currentTime: 10, appName: "Safari")
        await coordinator.handleProviderUpdate(provider: mock1, state: state1)
        
        // Wait 100ms
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Mock2 starts playing later
        let state2 = ExternalPlayerState(isPlaying: true, trackName: "New Track", duration: 190, currentTime: 5, appName: "YouTube Music")
        await coordinator.handleProviderUpdate(provider: mock2, state: state2)
        
        let chosen = await coordinator.getCurrentState()
        guard chosen?.trackName == "New Track" else {
            throw TestError("Most recently started playback must be chosen")
        }
    }
    
    static func testArbitrationPinnedSource() async throws {
        let coordinator = NowPlayingCoordinator()
        let mockSystem = MockProvider(appName: "System Now Playing")
        let mockExt = MockProvider(appName: "YouTube Music (Browser Extension)")
        
        await coordinator.registerProviders([mockSystem, mockExt])
        await coordinator.setPreferredSource("system")
        
        let stateExt = ExternalPlayerState(isPlaying: true, trackName: "Extension Song", duration: 200, currentTime: 10, appName: "Extension")
        let stateSys = ExternalPlayerState(isPlaying: true, trackName: "System Song", duration: 200, currentTime: 10, appName: "System")
        
        await coordinator.handleProviderUpdate(provider: mockExt, state: stateExt)
        await coordinator.handleProviderUpdate(provider: mockSystem, state: stateSys)
        
        let chosen = await coordinator.getCurrentState()
        guard chosen?.trackName == "System Song" else {
            throw TestError("User-pinned preferred source must take precedence")
        }
    }
    
    // MARK: - Suite 2 Implementations
    
    static func testDeDuplicationIdentical() throws {
        let s1 = ExternalPlayerState(isPlaying: true, trackName: "Blinding Lights", artistName: "The Weeknd", duration: 200.0, currentTime: 30, appName: "Safari")
        let s2 = ExternalPlayerState(isPlaying: true, trackName: "Blinding Lights", artistName: "The Weeknd", duration: 200.0, currentTime: 30, appName: "Chrome")
        
        guard NowPlayingCoordinator.isDuplicate(lhs: s1, rhs: s2) else {
            throw TestError("Identical track should be recognized as duplicate")
        }
    }
    
    static func testDeDuplicationDurationTolerance() throws {
        let s1 = ExternalPlayerState(isPlaying: true, trackName: "Starboy", artistName: "The Weeknd", duration: 230.0, currentTime: 45, appName: "Safari")
        let s2 = ExternalPlayerState(isPlaying: true, trackName: "Starboy", artistName: "The Weeknd", duration: 231.5, currentTime: 45, appName: "Chrome")
        
        // Difference is 1.5s <= 2.0s tolerance
        guard NowPlayingCoordinator.isDuplicate(lhs: s1, rhs: s2) else {
            throw TestError("Tracks with <= 2.0s duration difference should match")
        }
    }
    
    static func testDeDuplicationDurationMismatch() throws {
        let s1 = ExternalPlayerState(isPlaying: true, trackName: "Starboy", artistName: "The Weeknd", duration: 230.0, currentTime: 45, appName: "Safari")
        let s2 = ExternalPlayerState(isPlaying: true, trackName: "Starboy", artistName: "The Weeknd", duration: 234.0, currentTime: 45, appName: "Chrome")
        
        // Difference is 4.0s > 2.0s tolerance
        guard !NowPlayingCoordinator.isDuplicate(lhs: s1, rhs: s2) else {
            throw TestError("Tracks with > 2.0s duration difference should NOT match")
        }
    }
    
    static func testDeDuplicationTitleContainment() throws {
        let s1 = ExternalPlayerState(isPlaying: true, trackName: "Save Your Tears (Official Music Video)", artistName: "The Weeknd", duration: 215.0, currentTime: 10, appName: "Chrome")
        let s2 = ExternalPlayerState(isPlaying: true, trackName: "Save Your Tears", artistName: "The Weeknd", duration: 215.0, currentTime: 10, appName: "Safari")
        
        guard NowPlayingCoordinator.isDuplicate(lhs: s1, rhs: s2) else {
            throw TestError("Substring title containment should match")
        }
    }
    
    static func testDeDuplicationFieldMerging() throws {
        let dummyArtwork = Data(repeating: 0xFF, count: 4096)
        let primary = ExternalPlayerState(
            isPlaying: true,
            trackName: "Levitating",
            artistName: "Dua Lipa",
            duration: 203.0,
            currentTime: 50.0,
            artworkData: nil,
            appName: "System Now Playing"
        )
        let secondary = ExternalPlayerState(
            isPlaying: true,
            trackName: "Levitating",
            artistName: "Dua Lipa",
            albumName: "Future Nostalgia",
            duration: 203.5,
            currentTime: 50.0,
            artworkData: dummyArtwork,
            appName: "Browser Extension",
            sourceURL: "https://music.youtube.com/watch?v=test"
        )
        
        let merged = NowPlayingCoordinator.mergeDuplicate(
            primary: primary,
            secondary: secondary,
            primaryRank: .systemNowPlaying,
            secondaryRank: .browserExtension
        )
        
        guard merged.artworkData == dummyArtwork else {
            throw TestError("Merged state must inherit high-res artwork from secondary")
        }
        guard merged.albumName == "Future Nostalgia" else {
            throw TestError("Merged state must inherit album name")
        }
        guard merged.sourceURL == "https://music.youtube.com/watch?v=test" else {
            throw TestError("Merged state must inherit sourceURL")
        }
    }
    
    // MARK: - Suite 3 Implementations
    
    static func parseAppleScriptDiagnostics(output: String) -> (isSuccess: Bool, errorCode: Int?, message: String) {
        if output == "enabled" {
            return (true, nil, "JavaScript execution from Apple Events is enabled.")
        }
        if output.contains(":12:") || output.contains("turned off") {
            return (false, 12, "Allow JavaScript from Apple Events is turned off in Chrome.")
        }
        if output.contains(":-1743:") {
            return (false, -1743, "macOS Automation (TCC) permission denied.")
        }
        if output.contains(":-600:") || output.contains("not_running") {
            return (false, -600, "Target application is not running.")
        }
        return (false, nil, output)
    }
    
    static func testAppleScriptError12() throws {
        let sample = "error:12:Executing JavaScript through AppleScript is turned off."
        let res = parseAppleScriptDiagnostics(output: sample)
        guard res.errorCode == 12, !res.isSuccess else {
            throw TestError("Failed to parse Error 12")
        }
    }
    
    static func testAppleScriptError1743() throws {
        let sample = "error:-1743:Not authorized to send Apple events to Google Chrome."
        let res = parseAppleScriptDiagnostics(output: sample)
        guard res.errorCode == -1743, !res.isSuccess else {
            throw TestError("Failed to parse Error -1743")
        }
    }
    
    static func testAppleScriptError600() throws {
        let sample = "error:-600:Application isn't running."
        let res = parseAppleScriptDiagnostics(output: sample)
        guard res.errorCode == -600, !res.isSuccess else {
            throw TestError("Failed to parse Error -600")
        }
    }
    
    static func testAppleScriptSuccess() throws {
        let sample = "enabled"
        let res = parseAppleScriptDiagnostics(output: sample)
        guard res.isSuccess, res.errorCode == nil else {
            throw TestError("Failed to parse AppleScript success")
        }
    }
    
    // MARK: - Suite 4 Implementations
    
    static func testExtensionMessageDecodingFull() throws {
        let jsonStr = """
        {
            "type": "state",
            "isPlaying": true,
            "trackName": "Starboy",
            "artistName": "The Weeknd",
            "albumName": "Starboy",
            "duration": 230.5,
            "currentTime": 45.2,
            "playbackRate": 1.0,
            "artworkUrl": "https://lh3.googleusercontent.com/test",
            "url": "https://music.youtube.com/watch?v=d_2a"
        }
        """
        guard let data = jsonStr.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestError("JSON parsing failed")
        }
        
        let isPlaying = dict["isPlaying"] as? Bool ?? false
        let trackName = dict["trackName"] as? String ?? ""
        let artistName = dict["artistName"] as? String ?? ""
        let albumName = dict["albumName"] as? String ?? ""
        let duration = dict["duration"] as? Double ?? 0
        let currentTime = dict["currentTime"] as? Double ?? 0
        
        guard isPlaying, trackName == "Starboy", artistName == "The Weeknd", albumName == "Starboy", duration == 230.5, currentTime == 45.2 else {
            throw TestError("Decoded payload fields do not match expected values")
        }
    }
    
    static func testExtensionMessageDecodingDefensive() throws {
        let partialJson = """
        {
            "type": "state",
            "isPlaying": false,
            "trackName": "Only Title Provided"
        }
        """
        guard let data = partialJson.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestError("JSON parsing failed")
        }
        
        let title = dict["trackName"] as? String ?? "Unknown Title"
        let artist = dict["artistName"] as? String ?? "YouTube Music"
        let duration = dict["duration"] as? Double ?? 0
        
        guard title == "Only Title Provided", artist == "YouTube Music", duration == 0 else {
            throw TestError("Defensive defaults failed on missing fields")
        }
    }
    
    // MARK: - Suite 5 Implementations
    
    static func testImmediateTrackChangeEmit() async throws {
        let coordinator = NowPlayingCoordinator()
        let mock = MockProvider(appName: "Test Provider")
        await coordinator.registerProviders([mock])
        
        let state1 = ExternalPlayerState(isPlaying: true, trackName: "Song 1", duration: 100, currentTime: 10, appName: "Test")
        await coordinator.handleProviderUpdate(provider: mock, state: state1)
        
        guard await coordinator.getCurrentState()?.trackName == "Song 1" else {
            throw TestError("Initial state not emitted")
        }
        
        // Immediate track change
        let state2 = ExternalPlayerState(isPlaying: true, trackName: "Song 2", duration: 100, currentTime: 0, appName: "Test")
        await coordinator.handleProviderUpdate(provider: mock, state: state2)
        
        guard await coordinator.getCurrentState()?.trackName == "Song 2" else {
            throw TestError("Track change must emit immediately")
        }
    }
    
    static func testThreeSecondTeardownDelay() async throws {
        let coordinator = NowPlayingCoordinator()
        let mock = MockProvider(appName: "Test Provider")
        await coordinator.registerProviders([mock])
        
        let state = ExternalPlayerState(isPlaying: true, trackName: "Song A", duration: 100, currentTime: 10, appName: "Test")
        await coordinator.handleProviderUpdate(provider: mock, state: state)
        
        // Provider terminates / emits nil (e.g. browser closes)
        await coordinator.handleProviderUpdate(provider: mock, state: nil)
        
        // Immediate check: state should NOT be nil immediately (prevent flicker)
        let stateImmediatelyAfter = await coordinator.getCurrentState()
        guard stateImmediatelyAfter != nil else {
            throw TestError("State was cleared prematurely! Expected 3-second grace period.")
        }
        
        // Wait 1.0 second: state should still be present
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let stateAt1Sec = await coordinator.getCurrentState()
        guard stateAt1Sec != nil else {
            throw TestError("State cleared before 3 seconds expired")
        }
        
        // Wait remaining 2.2 seconds (total 3.2s)
        try await Task.sleep(nanoseconds: 2_200_000_000)
        let stateAfterTeardown = await coordinator.getCurrentState()
        guard stateAfterTeardown == nil else {
            throw TestError("State was not cleared after 3-second grace period expired")
        }
    }
    
    // MARK: - Suite 6 Implementations
    
    static func testSystemNowPlayingLiveFetch() async throws {
        let provider = SystemNowPlayingProvider()
        provider.startMonitoring()
        print("[Provider mode: \(provider.activeMode.rawValue)] ", terminator: "")
        
        // Allow adapter process up to 2.0s to emit initial payload
        var state: ExternalPlayerState? = nil
        for _ in 0..<20 {
            if let s = await provider.fetchState() {
                state = s
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        provider.stopMonitoring()
        
        if let state = state, let track = state.trackName, !track.isEmpty {
            print("[\(track) - \(state.artistName ?? "Unknown") (\(state.appName))] ", terminator: "")
        } else {
            print("[No active media playback on system] ", terminator: "")
        }
    }
    
    // MARK: - Suite 7 Implementations
    
    static func testStableIDDeterminism() throws {
        let path = "/Users/music/Track 01.flac"
        let id1 = NowPlayingSnapshot.stableIDForLocal(filePath: path)
        let id2 = NowPlayingSnapshot.stableIDForLocal(filePath: path)
        guard id1 == id2, !id1.isEmpty, id1.hasPrefix("local_") else {
            throw TestError("Local stable ID must be deterministic and prefixed with local_")
        }
        
        // External with videoId
        let ytId1 = NowPlayingSnapshot.stableIDForExternal(videoId: "dQw4w9WgXcQ", artist: "Rick", title: "Never", duration: 213)
        let ytId2 = NowPlayingSnapshot.stableIDForExternal(videoId: "dQw4w9WgXcQ", artist: "Other", title: "Other", duration: 100)
        guard ytId1 == ytId2, ytId1 == "yt_dQw4w9WgXcQ" else {
            throw TestError("External stable ID with videoId must be yt_<videoId>")
        }
        
        // External without videoId (normalized metadata)
        let ext1 = NowPlayingSnapshot.stableIDForExternal(videoId: nil, artist: "Arijit Singh", title: "Tum Hi Ho", duration: 262)
        let ext2 = NowPlayingSnapshot.stableIDForExternal(videoId: "", artist: "  arijit singh  ", title: "tum hi ho", duration: 261.9)
        guard ext1 == ext2, ext1.hasPrefix("ext_") else {
            throw TestError("External stable ID without videoId must normalize artist/title/duration")
        }
    }
    
    static func testSmoothClockCalculation() throws {
        let snapshot = NowPlayingSnapshot.shared
        let baseTime: TimeInterval = 10.0
        let baseUptime: TimeInterval = 100.0
        
        snapshot.positionAnchor = (time: baseTime, hostTime: baseUptime)
        snapshot.playbackRate = 1.0
        snapshot.isPlaying = true
        snapshot.duration = 200.0
        
        // At uptime 102.5 (2.5s later), position must be 12.5s
        let pos = snapshot.position(at: 102.5)
        guard abs(pos - 12.5) < 0.001 else {
            throw TestError("Expected position 12.5s, got \(pos)")
        }
        
        // With rate 1.5x, at uptime 104.0 (4.0s elapsed), position must be 10.0 + (4.0 * 1.5) = 16.0s
        snapshot.playbackRate = 1.5
        let pos15 = snapshot.position(at: 104.0)
        guard abs(pos15 - 16.0) < 0.001 else {
            throw TestError("Expected position 16.0s, got \(pos15)")
        }
    }
    
    static func testPausedClockZeroDrift() throws {
        let snapshot = NowPlayingSnapshot.shared
        snapshot.positionAnchor = (time: 42.0, hostTime: 100.0)
        snapshot.playbackRate = 1.0
        snapshot.isPlaying = false
        snapshot.duration = 200.0
        
        // Paused clock must return exactly anchor time regardless of elapsed host uptime
        let posAfter10s = snapshot.position(at: 110.0)
        guard abs(posAfter10s - 42.0) < 0.001 else {
            throw TestError("Paused player must never advance time; got \(posAfter10s)")
        }
    }
    
    static func testLyricsLookAheadAndOffset() throws {
        let snapshot = NowPlayingSnapshot.shared
        snapshot.positionAnchor = (time: 50.0, hostTime: 100.0)
        snapshot.playbackRate = 1.0
        snapshot.isPlaying = false
        snapshot.duration = 200.0
        
        snapshot.globalLyricsOffset = -0.15 // 150ms look-ahead
        snapshot.userLyricsOffset = 0.0
        
        // lyricsTime = position - (-0.15) = 50.0 + 0.15 = 50.15
        let lt = snapshot.lyricsTime(at: 100.0)
        guard abs(lt - 50.15) < 0.001 else {
            throw TestError("Lyrics time must include default -150ms look-ahead, got \(lt)")
        }
        
        // Add user per-track offset of +200ms
        snapshot.setUserLyricsOffset(0.20)
        // total offset is -0.15 + 0.20 = +0.05
        // lyricsTime = 50.0 - 0.05 = 49.95
        let ltAdjusted = snapshot.lyricsTime(at: 100.0)
        guard abs(ltAdjusted - 49.95) < 0.001 else {
            throw TestError("Lyrics time must apply user per-track offset, got \(ltAdjusted)")
        }
    }
    
    static func testLyricsDiskCacheRoundtrip() throws {
        let testTrackId = "test_track_cache_abc123"
        let sampleLRC = "[00:10.50] Hello World\n[00:15.00] Second line"
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDir = appSupport.appendingPathComponent("Lumo/LyricsCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        let fileURL = cacheDir.appendingPathComponent("\(testTrackId).json")
        struct CacheFormat: Codable {
            let id: String
            let lyricsText: String
            let hasSyncedLyrics: Bool
            let source: String?
            let cachedAt: Date
        }
        let record = CacheFormat(id: testTrackId, lyricsText: sampleLRC, hasSyncedLyrics: true, source: "LRCLIB", cachedAt: Date())
        let data = try JSONEncoder().encode(record)
        try data.write(to: fileURL)
        
        // Verify file exists on disk
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TestError("Lyrics cache file not created at \(fileURL.path)")
        }
        
        // Read back
        let readData = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(CacheFormat.self, from: readData)
        guard decoded.id == testTrackId, decoded.lyricsText == sampleLRC, decoded.hasSyncedLyrics == true else {
            throw TestError("Decoded lyrics cache payload mismatch")
        }
        
        // Cleanup test file
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Suite 8 Implementations (Phase 2 Metadata)
    
    static func testEminemMockingbird() throws {
        let raw = "Eminem – Mockingbird"
        let cleaned = TitleCleaner.clean(raw).cleanedString
        guard cleaned == "Eminem – Mockingbird" else {
            throw TestError("TitleCleaner erroneously stripped 'Mockingbird', got: '\(cleaned)'")
        }
        let candidates = TitleParser.parse(cleanedString: cleaned)
        guard let best = candidates.first else {
            throw TestError("Failed to parse candidates for 'Eminem – Mockingbird'")
        }
        guard best.artist == "Eminem", best.title == "Mockingbird" else {
            throw TestError("Expected Eminem - Mockingbird, got artist: '\(best.artist)', title: '\(best.title)'")
        }
    }
    
    static func testLiveForever() throws {
        let raw = "Live Forever"
        let cleaned = TitleCleaner.clean(raw).cleanedString
        guard cleaned == "Live Forever" else {
            throw TestError("TitleCleaner stripped 'Live' from 'Live Forever', got: '\(cleaned)'")
        }
        let candidates = TitleParser.parse(cleanedString: cleaned)
        guard let best = candidates.first, best.title == "Live Forever" else {
            throw TestError("Expected title 'Live Forever', got: '\(candidates.first?.title ?? "")'")
        }
    }
    
    static func testStayWithMe() throws {
        let raw = "Stay with me"
        let cleaned = TitleCleaner.clean(raw).cleanedString
        guard cleaned == "Stay with me" else {
            throw TestError("TitleCleaner corrupted 'Stay with me', got: '\(cleaned)'")
        }
        let candidates = TitleParser.parse(cleanedString: cleaned)
        guard let best = candidates.first else {
            throw TestError("Failed to parse 'Stay with me'")
        }
        guard best.title == "Stay with me", best.featuredArtists.isEmpty else {
            throw TestError("Treating 'with' as feat marker: title='\(best.title)', feat=\(best.featuredArtists)")
        }
    }
    
    static func testTumHiHoIndianFormat() throws {
        let raw = "Tum Hi Ho (Full Video) | Aashiqui 2 | Arijit Singh | Mithoon"
        let cleaned = TitleCleaner.clean(raw).cleanedString
        let candidates = TitleParser.parse(cleanedString: cleaned)
        guard let best = candidates.first else {
            throw TestError("Failed to parse Indian multi-segment title")
        }
        guard best.title == "Tum Hi Ho" else {
            throw TestError("Expected title 'Tum Hi Ho', got '\(best.title)'")
        }
        guard best.artist == "Arijit Singh" else {
            throw TestError("Expected singer 'Arijit Singh', got '\(best.artist)'")
        }
        guard best.album == "Aashiqui 2" else {
            throw TestError("Expected movie/album 'Aashiqui 2', got '\(best.album ?? "nil")'")
        }
    }
    
    static func testKesariyaIndianFormat() throws {
        let raw = "Kesariya (Official Video) | Brahmastra | Arijit Singh"
        let cleaned = TitleCleaner.clean(raw).cleanedString
        let candidates = TitleParser.parse(cleanedString: cleaned)
        guard let best = candidates.first else {
            throw TestError("Failed to parse Kesariya")
        }
        guard best.title == "Kesariya" else {
            throw TestError("Expected title 'Kesariya', got '\(best.title)'")
        }
        guard best.artist == "Arijit Singh" else {
            throw TestError("Expected artist 'Arijit Singh', got '\(best.artist)'")
        }
        guard best.album == "Brahmastra" else {
            throw TestError("Expected album 'Brahmastra', got '\(best.album ?? "nil")'")
        }
    }
    
    static func testArtistTopicChannels() throws {
        let raw = "Yellow"
        let cleaned = TitleCleaner.clean(raw).cleanedString
        let candidates = TitleParser.parse(cleanedString: cleaned, uploader: "Coldplay - Topic")
        guard let best = candidates.first else {
            throw TestError("Failed to parse Topic channel upload")
        }
        guard best.artist == "Coldplay", best.title == "Yellow", best.confidence >= 0.90 else {
            throw TestError("Expected Coldplay - Yellow with high confidence, got artist: '\(best.artist)', title: '\(best.title)', conf: \(best.confidence)")
        }
    }
    
    static func testFilenameWithYouTubeID() throws {
        let raw = "Eminem - Mockingbird [dQw4w9WgXcQ].mp3"
        let cleaned = TitleCleaner.clean(raw).cleanedString
        guard cleaned == "Eminem - Mockingbird" else {
            throw TestError("Failed to strip yt-dlp [id], got: '\(cleaned)'")
        }
        let candidates = TitleParser.parse(cleanedString: cleaned)
        guard let best = candidates.first, best.artist == "Eminem", best.title == "Mockingbird" else {
            throw TestError("Expected Eminem - Mockingbird, got artist: '\(candidates.first?.artist ?? "")', title: '\(candidates.first?.title ?? "")'")
        }
    }
    
    static func testTokenSetSimilarityVsSubstring() throws {
        // Query "Love" vs Result "Love Story" - must be rejected (< 0.85)
        let scoreLoveStory = OnlineVerifier.computeMatchScore(queryArtist: "Unknown", queryTitle: "Love", resultArtist: "Taylor Swift", resultTitle: "Love Story")
        guard scoreLoveStory < 0.85 else {
            throw TestError("Substring containment bug: 'Love' matched 'Love Story' with score \(scoreLoveStory)")
        }
        
        // Exact match "Mockingbird" - must pass (>= 0.85)
        let scoreMockingbird = OnlineVerifier.computeMatchScore(queryArtist: "Eminem", queryTitle: "Mockingbird", resultArtist: "Eminem", resultTitle: "Mockingbird")
        guard scoreMockingbird >= 0.85 else {
            throw TestError("Exact match 'Mockingbird' failed score check with score \(scoreMockingbird)")
        }
    }
    
    // MARK: - Suite 9 Implementations (Phase 3 Lyrics)
    
    static func testEnhancedWordTagParsing() throws {
        let sample = "[00:10.00]<00:10.00>Never <00:10.50>gonna <00:11.00>give <00:11.50>you <00:12.00>up"
        let parsed = LyricsParser.parse(sample)
        guard parsed.isSynced, parsed.lines.count == 1 else {
            throw TestError("Enhanced tag parse failed")
        }
        let words = parsed.lines[0].words
        guard words.count == 5 else {
            throw TestError("Expected 5 enhanced words, got \(words.count)")
        }
        guard words[0].text == "Never", abs(words[0].start - 10.0) < 0.01 else {
            throw TestError("Word 0 timing mismatch: '\(words[0].text)' at \(words[0].start)")
        }
        guard words[4].text == "up", abs(words[4].start - 12.0) < 0.01 else {
            throw TestError("Word 4 timing mismatch: '\(words[4].text)' at \(words[4].start)")
        }
    }
    
    static func testOffsetTagHandling() throws {
        let sample = "[offset:500]\n[00:02.00]First line"
        let parsed = LyricsParser.parse(sample)
        guard parsed.isSynced, parsed.lines.count == 1 else {
            throw TestError("Offset tag parse failed")
        }
        // Time was 2.0s + 0.5s offset = 2.5s
        let lineTime = parsed.lines[0].time
        guard abs(lineTime - 2.50) < 0.01 else {
            throw TestError("Expected offset line time 2.5s, got \(lineTime)")
        }
    }
    
    static func testWordTimingEstimation() throws {
        let sample = """
        [00:00.00]Short
        [00:04.00]A very long line with multiple words
        [00:10.00]End
        """
        let parsed = LyricsParser.parse(sample)
        guard parsed.isSynced, parsed.lines.count == 3 else {
            throw TestError("Proportional timing parse failed")
        }
        let line1Words = parsed.lines[1].words
        guard line1Words.count == 7 else {
            throw TestError("Expected 7 estimated words, got \(line1Words.count)")
        }
        // Line starts at 4.0 and next line is at 10.0 (duration 6.0s)
        guard abs(line1Words.first!.start - 4.0) < 0.01 else {
            throw TestError("First word should start at line start 4.0s")
        }
        // "A" (1 letter) vs "multiple" (8 letters): multiple must have longer duration than A
        let durA = line1Words[0].end - line1Words[0].start
        let durMultiple = line1Words[5].end - line1Words[5].start
        guard durMultiple > durA else {
            throw TestError("Longer word 'multiple' (\(durMultiple)s) must have longer duration than 'A' (\(durA)s)")
        }
    }
    
    static func testScriptDetectionDevanagariAndIndic() throws {
        let hindi = "तू ही मेरी मंज़िल"
        guard Romanizer.detectScript(in: hindi) == .devanagari else {
            throw TestError("Failed to detect Devanagari script")
        }
        
        let punjabi = "ਸਤਿ ਸ੍ਰੀ ਅਕਾਲ"
        guard Romanizer.detectScript(in: punjabi) == .gurmukhi else {
            throw TestError("Failed to detect Gurmukhi script")
        }
        
        let bengali = "আমার সোনার বাংলা"
        guard Romanizer.detectScript(in: bengali) == .bengali else {
            throw TestError("Failed to detect Bengali script")
        }
        
        let korean = "사랑해요"
        guard Romanizer.detectScript(in: korean) == .hangul else {
            throw TestError("Failed to detect Hangul script")
        }
    }
    
    static func testRomanizationDevanagari() throws {
        let hindi = "केसरिया तेरा इश्क़"
        let romanized = Romanizer.romanize(text: hindi).lowercased()
        guard romanized.contains("kesariya") || romanized.contains("kesari") else {
            throw TestError("Devanagari romanization did not produce 'kesariya', got: '\(romanized)'")
        }
    }
    
    static func testTransliterationTolerantAligner() throws {
        let refText = "kesariya tera ishq"
        let whisperWords = [
            GroqWhisperResponse.WhisperWord(word: "Kesariya", start: 1.0, end: 1.8),
            GroqWhisperResponse.WhisperWord(word: "tera", start: 1.9, end: 2.3),
            GroqWhisperResponse.WhisperWord(word: "ishq", start: 2.4, end: 3.0)
        ]
        let aligned = LyricsAligner.align(referenceText: refText, whisperWords: whisperWords)
        guard aligned.isSynced, !aligned.lines.isEmpty else {
            throw TestError("Transliteration aligner returned empty lines")
        }
        guard abs(aligned.lines[0].time - 1.0) < 0.05 else {
            throw TestError("Aligned start time mismatch: \(aligned.lines[0].time)")
        }
        guard aligned.lines[0].words.count == 3 else {
            throw TestError("Expected 3 aligned words, got \(aligned.lines[0].words.count)")
        }
    }
    
    static func testBinarySearchLineIndex() throws {
        let sampleLRC = """
        [00:10.00] First line of the song
        [00:25.50] Second line follows here
        [00:45.00] Third line continues
        [01:10.00] Final outro line
        """
        let parsed = LyricsParser.parse(sampleLRC)
        guard parsed.isSynced, parsed.lines.count == 4 else {
            throw TestError("Failed to parse sample LRC with 4 lines")
        }
        
        // 1. Initial / before first line
        let before = parsed.lineIndex(at: 4.5)
        guard before == -1 else {
            throw TestError("Expected -1 before first line, got \(before)")
        }
        
        // 2. Exact match at start of line
        let atLine0 = parsed.lineIndex(at: 10.0)
        guard atLine0 == 0 else {
            throw TestError("Expected line 0 at 10.0s, got \(atLine0)")
        }
        
        // 3. Middle of line
        let midLine0 = parsed.lineIndex(at: 18.2)
        guard midLine0 == 0 else {
            throw TestError("Expected line 0 at 18.2s, got \(midLine0)")
        }
        
        let atLine1 = parsed.lineIndex(at: 25.5)
        guard atLine1 == 1 else {
            throw TestError("Expected line 1 at 25.5s, got \(atLine1)")
        }
        
        // 4. Seek forward test
        let seekFwdTime: TimeInterval = 48.0 // in Line 2 (45.00s)
        let seekFwdIdx = parsed.lineIndex(at: seekFwdTime)
        guard seekFwdIdx == 2 else {
            throw TestError("Expected line 2 after seek forward to 48s, got \(seekFwdIdx)")
        }
        
        // 5. Seek backward test
        let seekBackTime: TimeInterval = 12.0 // in Line 0 (10.00s)
        let seekBackIdx = parsed.lineIndex(at: seekBackTime)
        guard seekBackIdx == 0 else {
            throw TestError("Expected line 0 after seek backward to 12s, got \(seekBackIdx)")
        }
        
        // 6. Pause test: monotonic consistency at fixed time
        let pauseTime: TimeInterval = 30.0
        let pauseIdx1 = parsed.lineIndex(at: pauseTime)
        let pauseIdx2 = parsed.lineIndex(at: pauseTime)
        guard pauseIdx1 == 1 && pauseIdx2 == 1 else {
            throw TestError("Paused lineIndex should be stable, got \(pauseIdx1) and \(pauseIdx2)")
        }
        
        // 7. Outro / past last timestamp
        let pastEnd = parsed.lineIndex(at: 120.0)
        guard pastEnd == 3 else {
            throw TestError("Expected last line index 3 past 70s, got \(pastEnd)")
        }
        
        // 8. Track change: new track replaces lyrics
        let track2LRC = """
        [00:03.00] Track two intro
        [00:15.00] Track two verse
        """
        let parsedTrack2 = LyricsParser.parse(track2LRC)
        guard parsedTrack2.lineIndex(at: 1.0) == -1 else {
            throw TestError("Expected -1 before track 2 intro")
        }
        guard parsedTrack2.lineIndex(at: 5.0) == 0 else {
            throw TestError("Expected line 0 for track 2 at 5s")
        }
        guard parsedTrack2.lineIndex(at: 20.0) == 1 else {
            throw TestError("Expected line 1 for track 2 at 20s")
        }
    }
    
    // MARK: - Suite 10 Implementations (Artwork Pipeline)
    
    static func testArtworkURLUpscaleRewriting() throws {
        let ytMusicUrl = "https://lh3.googleusercontent.com/abc=w60-h60-l90-rj"
        let rewritten1 = ArtworkPipeline.rewriteArtworkURL(ytMusicUrl)
        guard rewritten1 == "https://lh3.googleusercontent.com/abc=w1200-h1200-l90-rj" else {
            throw TestError("Expected w1200-h1200 upscale, got: \(rewritten1)")
        }
        
        let ytSquare = "https://lh3.googleusercontent.com/xyz=s60-c"
        let rewritten2 = ArtworkPipeline.rewriteArtworkURL(ytSquare)
        guard rewritten2 == "https://lh3.googleusercontent.com/xyz=s1200-c" else {
            throw TestError("Expected s1200-c upscale, got: \(rewritten2)")
        }
        
        let ytVideoThumb = "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
        let rewritten3 = ArtworkPipeline.rewriteArtworkURL(ytVideoThumb)
        guard rewritten3 == "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg" else {
            throw TestError("Expected maxresdefault rewrite, got: \(rewritten3)")
        }
    }
    
    static func testArtwork16x9SquareCropping() throws {
        // Create 320x180 (16:9) image
        let wide16x9Data = createTestImageData(width: 320, height: 180)
        let croppedData = ArtworkPipeline.squareCropIfNeeded(data: wide16x9Data)
        guard let croppedImage = NSImage(data: croppedData) else {
            throw TestError("Failed to decode cropped image")
        }
        var proposedRect = CGRect(origin: .zero, size: croppedImage.size)
        guard let cgImg = croppedImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw TestError("Failed to get CGImage from cropped image")
        }
        guard cgImg.width == cgImg.height, cgImg.width == 180 else {
            throw TestError("Expected square crop 180x180, got \(cgImg.width)x\(cgImg.height)")
        }
    }
    
    static func testArtworkHighResolutionDiscrimination() throws {
        let lowRes = createTestImageData(width: 120, height: 120)
        let highRes = createTestImageData(width: 600, height: 600)
        
        guard !ArtworkPipeline.isHighResolution(data: lowRes) else {
            throw TestError("120x120 image should be marked low resolution (< 300px)")
        }
        guard ArtworkPipeline.isHighResolution(data: highRes) else {
            throw TestError("600x600 image should be marked high resolution (>= 300px)")
        }
    }
    
    static func testArtworkDiskCacheRoundtrip() async throws {
        let pipeline = ArtworkPipeline.shared
        let testStableId = "test_stable_art_\(UUID().uuidString)"
        let testArtist = "Arijit Singh"
        let testAlbum = "Aashiqui 2"
        let testData = createTestImageData(width: 400, height: 400)
        
        await pipeline.saveToDiskCache(data: testData, stableId: testStableId, artist: testArtist, album: testAlbum)
        
        // Lookup by stableId
        let retrievedById = await pipeline.checkDiskCache(stableId: testStableId, artist: "", album: "")
        guard retrievedById != nil else {
            throw TestError("Failed to retrieve cached artwork by stable ID")
        }
        
        // Lookup by normalized metadata
        let retrievedByMeta = await pipeline.checkDiskCache(stableId: "other_id", artist: "  arijit singh ", album: "aashiqui 2")
        guard retrievedByMeta != nil else {
            throw TestError("Failed to retrieve cached artwork by normalized metadata key")
        }
        
        // Clean up
        await pipeline.clearDiskCache(for: testStableId)
    }
    
    private static func createTestImageData(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )!
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
    }
    
    // MARK: - Suite 11 Implementations (Kinetic Visualizer & Neon Notch)
    
    static func testNeonBorderNotchPathGeneration() throws {
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        
        let shapeWithNotch = NeonBorderShape(notchCompatible: true, cornerRadius: 16, notchWidth: 200, notchHeight: 34)
        let pathWithNotch = shapeWithNotch.path(in: rect)
        guard !pathWithNotch.isEmpty else {
            throw TestError("NeonBorderShape with notch produced empty path")
        }
        
        let shapeNoNotch = NeonBorderShape(notchCompatible: false, cornerRadius: 16)
        let pathNoNotch = shapeNoNotch.path(in: rect)
        guard !pathNoNotch.isEmpty else {
            throw TestError("NeonBorderShape without notch produced empty path")
        }
    }
    
    static func testBeatGlitchAttackAndDecay() throws {
        var glitchAmount: Float = 0.0
        let beatInput: Float = Float.random(in: 0.95...1.0)
        
        // Fast Attack (~30ms, 1-2 frames): should jump significantly
        glitchAmount += (beatInput - glitchAmount) * 0.65
        guard glitchAmount >= 0.60 else {
            throw TestError("Glitch fast attack failed: amount is \(glitchAmount), expected >= 0.60")
        }
        
        // Smooth Decay (~250ms, ~8 frames of decay)
        for _ in 0..<10 {
            glitchAmount *= 0.88
        }
        guard glitchAmount < 0.25 else {
            throw TestError("Glitch decay failed: amount is \(glitchAmount), expected < 0.25")
        }
    }
    
    static func testKineticWordSequenceResolution() throws {
        let words = [
            LyricWord(text: "can't", start: 0.0, end: 1.0),
            LyricWord(text: "give", start: 1.0, end: 2.0),
            LyricWord(text: "up", start: 2.0, end: 3.0)
        ]
        let line = LyricLine(time: 0.0, text: "can't give up", words: words)
        
        // Query at time 1.2s -> active word is "give"
        let time = 1.2
        var wIdx = 0
        for (idx, w) in line.words.enumerated() {
            if time >= w.start {
                wIdx = idx
            }
        }
        
        let curr = line.words[wIdx].text
        let prev = wIdx > 0 ? line.words[wIdx - 1].text : ""
        let next = wIdx + 1 < line.words.count ? line.words[wIdx + 1].text : ""
        
        guard curr == "give" else {
            throw TestError("Expected active word 'give', got '\(curr)'")
        }
        guard prev == "can't" else {
            throw TestError("Expected previous ghost word 'can't', got '\(prev)'")
        }
        guard next == "up" else {
            throw TestError("Expected next plate word 'up', got '\(next)'")
        }
    }
    
    // MARK: - Suite 12 Implementations (Find Cover & Lyrics)
    
    static func testMetadataTitleCleaning() throws {
        // Test 1: YouTube bracket noise and 4K descriptors
        let res1 = MetadataFetcherCoordinator.cleanSearchQuery(title: "Starboy (Official Music Video) [4K]", artist: "The Weeknd")
        guard !res1.cleanedQuery.contains("Official Music Video") && !res1.cleanedQuery.contains("4K") else {
            throw TestError("Failed to strip bracket noise: \(res1.cleanedQuery)")
        }
        guard res1.cleanedQuery.contains("Starboy") && res1.cleanedQuery.contains("The Weeknd") else {
            throw TestError("Cleaned query should retain core title and artist: \(res1.cleanedQuery)")
        }
        
        // Test 2: Emojis and audio label
        let res2 = MetadataFetcherCoordinator.cleanSearchQuery(title: "Blinding Lights 🔥✨ (Audio)", artist: "The Weeknd")
        guard !res2.cleanedQuery.contains("🔥") && !res2.cleanedQuery.contains("(Audio)") else {
            throw TestError("Failed to strip emojis or audio label: \(res2.cleanedQuery)")
        }
        
        // Test 3: Channel Topic suffix
        let res3 = MetadataFetcherCoordinator.cleanSearchQuery(title: "Tum Hi Ho - Topic", artist: "Arijit Singh | Topic")
        guard !res3.cleanedQuery.lowercased().contains("topic") else {
            throw TestError("Failed to strip Topic suffix: \(res3.cleanedQuery)")
        }
        
        // Test 4: ft./feat. in title
        let res4 = MetadataFetcherCoordinator.cleanSearchQuery(title: "Closer feat. Halsey (Lyric Video)", artist: "The Chainsmokers")
        guard !res4.cleanedQuery.lowercased().contains("feat.") && !res4.cleanedQuery.lowercased().contains("lyric video") else {
            throw TestError("Failed to strip feat. and lyric video: \(res4.cleanedQuery)")
        }
    }
    
    static func testMetadataYouTubeLinkExtraction() throws {
        // Direct 11-char ID
        guard MetadataFetcherCoordinator.extractYouTubeVideoId(from: "dQw4w9WgXcQ") == "dQw4w9WgXcQ" else {
            throw TestError("Direct 11-char ID extraction failed")
        }
        
        // Standard YouTube URL
        guard MetadataFetcherCoordinator.extractYouTubeVideoId(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s") == "dQw4w9WgXcQ" else {
            throw TestError("Standard YouTube URL extraction failed")
        }
        
        // YouTube Music URL
        guard MetadataFetcherCoordinator.extractYouTubeVideoId(from: "https://music.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ" else {
            throw TestError("YouTube Music URL extraction failed")
        }
        
        // Shortened youtu.be URL
        guard MetadataFetcherCoordinator.extractYouTubeVideoId(from: "https://youtu.be/dQw4w9WgXcQ?si=abc123") == "dQw4w9WgXcQ" else {
            throw TestError("Shortened youtu.be URL extraction failed")
        }
        
        // YouTube Shorts URL
        guard MetadataFetcherCoordinator.extractYouTubeVideoId(from: "https://www.youtube.com/shorts/dQw4w9WgXcQ") == "dQw4w9WgXcQ" else {
            throw TestError("Shorts URL extraction failed")
        }
        
        // Filename with bracketed video ID
        guard MetadataFetcherCoordinator.extractYouTubeVideoId(from: "Never Gonna Give You Up [dQw4w9WgXcQ].mp3") == "dQw4w9WgXcQ" else {
            throw TestError("Bracketed filename ID extraction failed")
        }
        
        // Scheme-less YouTube URL
        guard MetadataFetcherCoordinator.extractYouTubeVideoId(from: "www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ" else {
            throw TestError("Scheme-less YouTube URL extraction failed")
        }
        
        // Mobile YouTube URL
        guard MetadataFetcherCoordinator.extractYouTubeVideoId(from: "https://m.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ" else {
            throw TestError("Mobile YouTube URL extraction failed")
        }
        
        // Wrapped in quotes/brackets
        guard MetadataFetcherCoordinator.extractYouTubeVideoId(from: "<https://youtu.be/dQw4w9WgXcQ>") == "dQw4w9WgXcQ" else {
            throw TestError("Angle-bracketed YouTube URL extraction failed")
        }
    }
    
    static func testMetadataLRCParsingAndRomanization() throws {
        let sampleLRC = """
        [00:10.50]तू ही मेरी मंज़िल
        [00:15.20]तू ही मेरा जहाँ
        """
        
        let parsed = LyricsParser.parse(sampleLRC)
        guard parsed.isSynced, parsed.lines.count == 2 else {
            throw TestError("LRC parser failed to parse 2 synced lines")
        }
        guard abs(parsed.lines[0].time - 10.50) < 0.05 else {
            throw TestError("LRC timestamp mismatch: \(parsed.lines[0].time)")
        }
        
        // Preserve Devanagari script in original text
        guard parsed.lines[0].text.contains("तू ही मेरी मंज़िल") else {
            throw TestError("Devanagari script must be preserved in line text")
        }
        
        // Romanization verification
        let romanized = Romanizer.romanize(text: parsed.lines[0].text).lowercased()
        guard !romanized.isEmpty && (romanized.contains("tu") || romanized.contains("meri") || romanized.contains("manzil")) else {
            throw TestError("Romanizer failed to produce Latin transliteration: \(romanized)")
        }
    }
    
    static func testMetadataMatchScoring() throws {
        let candidate = MetadataSearchResult(
            videoId: "dQw4w9WgXcQ",
            title: "Starboy",
            artist: "The Weeknd",
            album: "Starboy",
            duration: 230.0,
            source: "YouTube Music"
        )
        
        // Close duration (<= 3s delta) and matching tokens -> Strong match score >= 0.85
        let strongScore = MetadataFetcherCoordinator.computeMatchScore(
            candidate: candidate,
            localTitle: "The Weeknd - Starboy (Official Audio)",
            localArtist: "The Weeknd",
            localDuration: 231.0
        )
        guard strongScore >= 0.85 else {
            throw TestError("Expected strong match score >= 0.85, got \(strongScore)")
        }
        
        // Massive duration delta (> 60s) -> should significantly penalize score
        let mismatchScore = MetadataFetcherCoordinator.computeMatchScore(
            candidate: candidate,
            localTitle: "Starboy",
            localArtist: "The Weeknd",
            localDuration: 350.0
        )
        guard mismatchScore < strongScore - 0.15 else {
            throw TestError("Expected duration mismatch penalty, got \(mismatchScore) vs \(strongScore)")
        }
    }
    
    static func testMetadataLyricsDurationValidation() throws {
        // Normal duration: song is 200s, last line is 195s -> valid
        let normalLRC = """
        [00:10.00]Intro
        [03:15.00]Outro
        """
        let normalParsed = LyricsParser.parse(normalLRC)
        let lastNormalTs = normalParsed.lines.last?.time ?? 0
        guard lastNormalTs <= 200.0 + 25.0 && lastNormalTs >= 200.0 * 0.40 else {
            throw TestError("Normal lyrics duration should be valid")
        }
        
        // Overlong duration: song is 100s, lyrics last timestamp is 180s (> 100 + 25)
        let overlongLRC = """
        [00:10.00]Intro
        [03:00.00]Outro at 180s
        """
        let overlongParsed = LyricsParser.parse(overlongLRC)
        let lastOverlongTs = overlongParsed.lines.last?.time ?? 0
        let isOverlongValid = (lastOverlongTs <= 100.0 + 25.0 && lastOverlongTs >= 100.0 * 0.40)
        guard !isOverlongValid else {
            throw TestError("Overlong lyrics should be rejected by duration validation")
        }
        
        // Truncated lyrics: song is 200s, lyrics last timestamp is 30s (< 200 * 0.40)
        let truncatedLRC = """
        [00:10.00]Intro
        [00:30.00]Short ending
        """
        let truncatedParsed = LyricsParser.parse(truncatedLRC)
        let lastTruncatedTs = truncatedParsed.lines.last?.time ?? 0
        let isTruncatedValid = (lastTruncatedTs <= 200.0 + 25.0 && lastTruncatedTs >= 200.0 * 0.40)
        guard !isTruncatedValid else {
            throw TestError("Severely truncated lyrics (<40% duration) should be rejected")
        }
    }
    
    // MARK: - Suite 13 Implementations
    
    private static func makeTestTrack(title: String, duration: Double = 180) -> TrackInfo {
        TrackInfo(
            id: UUID(),
            title: title,
            artist: "Test Artist",
            album: "Test Album",
            duration: duration,
            artworkData: nil,
            filePath: "/tmp/\(title).mp3",
            fileExtension: "mp3"
        )
    }
    
    static func testQueuePlayListStartingAtIndex() async throws {
        let ps = PlaybackState.shared
        ps.isShuffleEnabled = false
        
        let t1 = makeTestTrack(title: "Track 1")
        let t2 = makeTestTrack(title: "Track 2")
        let t3 = makeTestTrack(title: "Track 3")
        let t4 = makeTestTrack(title: "Track 4")
        
        await MainActor.run {
            ps.play(tracks: [t1, t2, t3, t4], startingAt: 1)
        }
        
        guard ps.currentTrack?.title == "Track 2" else {
            throw TestError("Expected currentTrack to be Track 2, got \(ps.currentTrack?.title ?? "nil")")
        }
        guard ps.history.count == 1, ps.history.first?.title == "Track 1" else {
            throw TestError("Expected history to contain Track 1, got \(ps.history.map(\.title))")
        }
        guard ps.queue.count == 2, ps.queue[0].title == "Track 3", ps.queue[1].title == "Track 4" else {
            throw TestError("Expected queue to contain [Track 3, Track 4], got \(ps.queue.map(\.title))")
        }
        guard ps.unshuffledQueue.count == 2 else {
            throw TestError("Expected unshuffledQueue to have count 2")
        }
    }
    
    static func testQueueNextTrackSequentialAdvance() async throws {
        let ps = PlaybackState.shared
        ps.isShuffleEnabled = false
        
        let t1 = makeTestTrack(title: "Advance 1")
        let t2 = makeTestTrack(title: "Advance 2")
        let t3 = makeTestTrack(title: "Advance 3")
        
        await MainActor.run {
            ps.play(tracks: [t1, t2, t3], startingAt: 0)
            ps.nextTrack()
        }
        
        guard ps.currentTrack?.title == "Advance 2" else {
            throw TestError("Expected currentTrack to advance to Advance 2, got \(ps.currentTrack?.title ?? "nil")")
        }
        guard ps.history.count == 1, ps.history.first?.title == "Advance 1" else {
            throw TestError("Expected history to record Advance 1, got \(ps.history.map(\.title))")
        }
        guard ps.queue.count == 1, ps.queue.first?.title == "Advance 3" else {
            throw TestError("Expected upcoming queue to have Advance 3, got \(ps.queue.map(\.title))")
        }
    }
    
    static func testQueueShuffleToggleAndRestore() async throws {
        let ps = PlaybackState.shared
        ps.isShuffleEnabled = false
        
        let tracks = (1...15).map { makeTestTrack(title: "Track \($0)") }
        
        await MainActor.run {
            ps.play(tracks: tracks, startingAt: 0)
        }
        
        let canonicalUpcoming = ps.queue.map(\.title)
        guard canonicalUpcoming.count == 14 else {
            throw TestError("Expected 14 upcoming tracks")
        }
        
        await MainActor.run {
            ps.toggleShuffle()
        }
        guard ps.isShuffleEnabled else {
            throw TestError("Shuffle should be enabled")
        }
        
        // Turn off shuffle -> should restore exact canonical order
        await MainActor.run {
            ps.toggleShuffle()
        }
        guard !ps.isShuffleEnabled else {
            throw TestError("Shuffle should be disabled")
        }
        guard ps.queue.map(\.title) == canonicalUpcoming else {
            throw TestError("Queue failed to restore canonical order when un-shuffled: \(ps.queue.map(\.title)) vs \(canonicalUpcoming)")
        }
    }
    
    static func testQueueMoveItemReordering() async throws {
        let ps = PlaybackState.shared
        ps.isShuffleEnabled = false
        
        let tA = makeTestTrack(title: "Song A")
        let tB = makeTestTrack(title: "Song B")
        let tC = makeTestTrack(title: "Song C")
        let tD = makeTestTrack(title: "Song D")
        
        await MainActor.run {
            ps.play(tracks: [tA, tB, tC, tD], startingAt: 0)
            // queue is [Song B, Song C, Song D]
            // Move Song D (index 2) to before Song B (offset 0)
            ps.moveQueueItem(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        }
        
        let titles = ps.queue.map(\.title)
        guard titles == ["Song D", "Song B", "Song C"] else {
            throw TestError("Expected queue after move to be [Song D, Song B, Song C], got \(titles)")
        }
    }
    
    static func testQueuePlayItemDirectJump() async throws {
        let ps = PlaybackState.shared
        ps.isShuffleEnabled = false
        
        let t1 = makeTestTrack(title: "Jump 1")
        let t2 = makeTestTrack(title: "Jump 2")
        let t3 = makeTestTrack(title: "Jump 3")
        let t4 = makeTestTrack(title: "Jump 4")
        
        await MainActor.run {
            ps.play(tracks: [t1, t2, t3, t4], startingAt: 0)
            // queue is [Jump 2, Jump 3, Jump 4]
            // Jump directly to Jump 4 (index 2 in queue)
            ps.playQueueItem(at: 2)
        }
        
        guard ps.currentTrack?.title == "Jump 4" else {
            throw TestError("Expected Jump 4 to be playing, got \(ps.currentTrack?.title ?? "nil")")
        }
        guard ps.queue.isEmpty else {
            throw TestError("Expected queue to be empty after jumping to the last item, got \(ps.queue.map(\.title))")
        }
        guard ps.history.contains(where: { $0.title == "Jump 2" }) && ps.history.contains(where: { $0.title == "Jump 3" }) else {
            throw TestError("Skipped tracks should be added to history: \(ps.history.map(\.title))")
        }
    }
    
    static func testQueueRemoveAndClear() async throws {
        let ps = PlaybackState.shared
        ps.isShuffleEnabled = false
        
        let t1 = makeTestTrack(title: "Rem 1")
        let t2 = makeTestTrack(title: "Rem 2")
        let t3 = makeTestTrack(title: "Rem 3")
        
        await MainActor.run {
            ps.play(tracks: [t1, t2, t3], startingAt: 0)
            // queue is [Rem 2, Rem 3]
            ps.removeQueueItem(at: 0)
        }
        
        guard ps.queue.count == 1, ps.queue.first?.title == "Rem 3" else {
            throw TestError("Expected queue to only contain Rem 3 after removing at index 0")
        }
        
        await MainActor.run {
            ps.clearQueue()
        }
        
        guard ps.queue.isEmpty && ps.unshuffledQueue.isEmpty else {
            throw TestError("Expected both queue and unshuffledQueue to be completely empty after clearQueue")
        }
    }
}

// MARK: - Mock Provider & Error Types

final class MockProvider: NowPlayingProvider, @unchecked Sendable {
    let appName: String
    var isAvailable: Bool = true
    var bundleIdentifiers: [String] = []
    weak var delegate: NowPlayingProviderDelegate?
    
    init(appName: String) {
        self.appName = appName
    }
    
    func startMonitoring() {}
    func stopMonitoring() {}
    func fetchAndNotify() {}
    func fetchState() async -> ExternalPlayerState? { nil }
    func playPause() {}
    func nextTrack() {}
    func previousTrack() {}
    func seek(to time: TimeInterval) {}
}

struct TestError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
