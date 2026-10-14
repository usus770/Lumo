import Foundation
import SwiftUI
import AppKit
import CommonCrypto

/// Unified now-playing model representing both local files and external playback.
/// Provides a stable identity, smooth continuous clock, lyrics caching, and transport controls.
@Observable
public final class NowPlayingSnapshot: Identifiable, @unchecked Sendable {
    public static let shared = NowPlayingSnapshot()
    
    // MARK: - Core Properties
    
    /// Stable, deterministic identifier: file path hash for local, videoId / normalized metadata hash for external.
    public var id: String = ""
    public var title: String = ""
    public var artist: String = ""
    public var album: String = ""
    public var duration: TimeInterval = 0
    public var artworkData: Data? = nil
    public var sourceID: String = ""
    public var isPlaying: Bool = false
    public var positionAnchor: (time: TimeInterval, hostTime: TimeInterval) = (0, 0)
    public var playbackRate: Double = 1.0
    
    // MARK: - Source Metadata
    
    public var isExternal: Bool = false
    public var filePath: String = ""
    public var sourceURL: String? = nil
    public var videoId: String? = nil
    public var appName: String = "Lumo"
    public var appIcon: NSImage? = nil
    
    // MARK: - Artwork & Lyrics State
    
    public var isFetchingArtwork: Bool = false
    public var lyricsText: String? = nil
    public var hasSyncedLyrics: Bool = false
    public var isFetchingLyrics: Bool = false
    public var lyricsSource: String? = nil
    
    /// Global default look-ahead (-150 ms) so lines light up on time rather than late
    public var globalLyricsOffset: TimeInterval = -0.15
    
    /// Per-track user offset in seconds (persisted)
    public var userLyricsOffset: TimeInterval = 0.0
    
    public var totalLyricsOffset: TimeInterval {
        globalLyricsOffset + userLyricsOffset
    }
    
    // MARK: - Private State
    
    private var lyricsFetchTask: Task<Void, Never>?
    private var artworkFetchTask: Task<Void, Never>?
    private let cacheDirectory: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.cacheDirectory = appSupport.appendingPathComponent("Lumo/LyricsCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Smooth Clock Calculation
    
    /// Calculates current playback position continuously from the anchor:
    /// position(now) = anchor.time + (hostTimeNow - anchor.hostTime) * rate
    public func position(at hostTime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        guard isPlaying else { return positionAnchor.time }
        let elapsed = max(0, hostTime - positionAnchor.hostTime)
        let pos = positionAnchor.time + (elapsed * playbackRate)
        if duration > 0 {
            return min(max(0, pos), duration)
        }
        return max(0, pos)
    }
    
    /// Calculates the effective time for lyrics display including look-ahead and per-track offset:
    /// lyricsTime = position - totalLyricsOffset (where negative offset means earlier highlighting)
    public func lyricsTime(at hostTime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        let pos = position(at: hostTime)
        return max(0, pos - totalLyricsOffset)
    }
    
    // MARK: - Stable ID Derivation
    
    public static func stableIDForLocal(filePath: String) -> String {
        guard !filePath.isEmpty else { return "" }
        let data = Data(filePath.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        let hex = hash.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "local_\(hex)"
    }
    
    public static func stableIDForExternal(videoId: String?, artist: String?, title: String?, duration: TimeInterval) -> String {
        if let vid = videoId, !vid.isEmpty {
            return "yt_\(vid)"
        }
        let normArtist = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let roundedDur = Int(duration.rounded())
        let key = "\(normArtist)|\(normTitle)|\(roundedDur)"
        let data = Data(key.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        let hex = hash.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "ext_\(hex)"
    }
    
    // MARK: - Updates
    
    func updateLocal(
        track: TrackInfo?,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval,
        rate: Double = 1.0
    ) {
        Task { @MainActor in
            guard let track = track else {
                // If local playback cleared, keep or switch to external if available
                if !self.isExternal {
                    self.clear()
                }
                return
            }
            
            let newId = Self.stableIDForLocal(filePath: track.filePath)
            let hostNow = ProcessInfo.processInfo.systemUptime
            
            self.isExternal = false
            self.filePath = track.filePath
            self.sourceURL = nil
            self.videoId = nil
            self.appName = "Lumo"
            self.appIcon = nil
            self.sourceID = "local"
            
            self.title = track.title
            self.artist = track.artist
            self.album = track.album
            self.duration = duration > 0 ? duration : track.duration
            self.artworkData = track.artworkData
            self.isPlaying = isPlaying
            self.playbackRate = rate
            self.positionAnchor = (time: currentTime, hostTime: hostNow)
            
            if newId != self.id {
                self.id = newId
                self.lyricsText = nil
                self.hasSyncedLyrics = false
                self.lyricsSource = nil
                self.isFetchingLyrics = false
                self.loadUserLyricsOffset(for: newId)
                self.triggerArtworkFetch(
                    id: newId,
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: self.duration,
                    filePath: track.filePath,
                    videoId: nil,
                    initialArtwork: track.artworkData,
                    extensionArtworkURL: nil
                )
                self.triggerLyricsFetch(
                    id: newId,
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: self.duration,
                    filePath: track.filePath,
                    videoId: nil,
                    initialLyrics: track.lyricsText,
                    initialSynced: track.hasSyncedLyrics
                )
            } else if (self.lyricsText == nil || self.lyricsText?.isEmpty == true), let text = track.lyricsText, !text.isEmpty {
                self.lyricsText = text
                self.hasSyncedLyrics = track.hasSyncedLyrics
                self.lyricsSource = "Embedded"
            }
        }
    }
    
    func updateLocalTime(currentTime: TimeInterval) {
        Task { @MainActor in
            guard !self.isExternal else { return }
            let hostNow = ProcessInfo.processInfo.systemUptime
            self.positionAnchor = (time: currentTime, hostTime: hostNow)
        }
    }
    
    func updateLocalPlayback(isPlaying: Bool, currentTime: TimeInterval) {
        Task { @MainActor in
            guard !self.isExternal else { return }
            let hostNow = ProcessInfo.processInfo.systemUptime
            self.isPlaying = isPlaying
            self.positionAnchor = (time: currentTime, hostTime: hostNow)
        }
    }
    
    func updateExternal(state: ExternalPlayerState?) {
        Task { @MainActor in
            guard let state = state else {
                if self.isExternal {
                    self.clear()
                }
                return
            }
            
            // Rule: Show external media unless Lumo's own player is actively playing
            if PlaybackState.shared.isPlaying && !self.isExternal {
                return
            }
            
            let hostNow = ProcessInfo.processInfo.systemUptime
            let wallNow = Date().timeIntervalSince1970
            let latency = max(0, min(1.5, wallNow - state.timestamp))
            let compensatedTime = state.currentTime + (state.isPlaying ? latency * state.playbackRate : 0.0)
            
            var effectiveVideoId = state.videoId
            if (effectiveVideoId == nil || effectiveVideoId?.isEmpty == true), let sourceURL = state.sourceURL {
                if let url = URL(string: sourceURL),
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let v = components.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                    effectiveVideoId = v
                }
            }
            
            let newId = Self.stableIDForExternal(
                videoId: effectiveVideoId,
                artist: state.artistName,
                title: state.trackName,
                duration: state.duration
            )
            
            self.isExternal = true
            self.filePath = ""
            self.sourceURL = state.sourceURL
            self.videoId = effectiveVideoId
            self.appName = state.appName
            self.sourceID = state.sourceBundleIdentifier ?? state.appName
            
            // Resolve app icon
            if let bundleID = state.sourceBundleIdentifier, !bundleID.isEmpty {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    self.appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
                }
            } else {
                self.appIcon = nil
            }
            
            self.title = state.trackName ?? "Unknown"
            self.artist = state.artistName ?? state.appName
            self.album = state.albumName ?? ""
            self.duration = state.duration
            if let art = state.artworkData {
                self.artworkData = art
            }
            self.isPlaying = state.isPlaying
            self.playbackRate = state.playbackRate
            self.positionAnchor = (time: compensatedTime, hostTime: hostNow)
            
            if newId != self.id {
                self.id = newId
                self.lyricsText = nil
                self.hasSyncedLyrics = false
                self.lyricsSource = nil
                self.isFetchingLyrics = false
                self.loadUserLyricsOffset(for: newId)
                self.triggerArtworkFetch(
                    id: newId,
                    title: self.title,
                    artist: self.artist,
                    album: self.album,
                    duration: self.duration,
                    filePath: "",
                    videoId: effectiveVideoId,
                    initialArtwork: state.artworkData,
                    extensionArtworkURL: state.sourceURL
                )
                self.triggerLyricsFetch(
                    id: newId,
                    title: self.title,
                    artist: self.artist,
                    album: self.album,
                    duration: self.duration,
                    filePath: "",
                    videoId: effectiveVideoId,
                    initialLyrics: nil,
                    initialSynced: false
                )
            } else if self.artworkData == nil, let art = state.artworkData {
                self.triggerArtworkFetch(
                    id: self.id,
                    title: self.title,
                    artist: self.artist,
                    album: self.album,
                    duration: self.duration,
                    filePath: "",
                    videoId: effectiveVideoId,
                    initialArtwork: art,
                    extensionArtworkURL: state.sourceURL
                )
            }
        }
    }
    
    @MainActor
    public func clear() {
        self.lyricsFetchTask?.cancel()
        self.lyricsFetchTask = nil
        self.artworkFetchTask?.cancel()
        self.artworkFetchTask = nil
        self.isFetchingArtwork = false
        self.id = ""
        self.title = ""
        self.artist = ""
        self.album = ""
        self.duration = 0
        self.artworkData = nil
        self.sourceID = ""
        self.isPlaying = false
        self.positionAnchor = (0, 0)
        self.playbackRate = 1.0
        self.isExternal = false
        self.filePath = ""
        self.sourceURL = nil
        self.videoId = nil
        self.appName = "Lumo"
        self.appIcon = nil
        self.lyricsText = nil
        self.hasSyncedLyrics = false
        self.isFetchingLyrics = false
        self.lyricsSource = nil
        self.userLyricsOffset = 0.0
    }
    
    // MARK: - Offset Management
    
    public func setUserLyricsOffset(_ offset: TimeInterval) {
        self.userLyricsOffset = offset
        if !id.isEmpty {
            UserDefaults.standard.set(offset, forKey: "lumo_lyrics_offset_\(id)")
        }
    }
    
    private func loadUserLyricsOffset(for trackId: String) {
        if !trackId.isEmpty {
            self.userLyricsOffset = UserDefaults.standard.double(forKey: "lumo_lyrics_offset_\(trackId)")
        } else {
            self.userLyricsOffset = 0.0
        }
    }
    
    // MARK: - Transport Controls
    
    public func togglePlayPause() {
        if isExternal {
            UniversalNowPlayingManager.shared.playPause()
        } else {
            PlaybackState.shared.togglePlayPause()
        }
    }
    
    public func nextTrack() {
        if isExternal {
            UniversalNowPlayingManager.shared.nextTrack()
        } else {
            PlaybackState.shared.nextTrack()
        }
    }
    
    public func previousTrack() {
        if isExternal {
            UniversalNowPlayingManager.shared.previousTrack()
        } else {
            PlaybackState.shared.previousTrack()
        }
    }
    
    public func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        positionAnchor = (time: clamped, hostTime: ProcessInfo.processInfo.systemUptime)
        if isExternal {
            UniversalNowPlayingManager.shared.seek(to: clamped)
        } else {
            PlaybackState.shared.seek(to: clamped)
        }
    }
    
    // MARK: - Lyrics Caching & Fetching
    
    private struct CachedLyrics: Codable {
        let id: String
        let lyricsText: String
        let hasSyncedLyrics: Bool
        let source: String?
        let cachedAt: Date
    }
    
    private func safeFilename(for trackId: String) -> String {
        let invalid = CharacterSet.alphanumerics.inverted
        let sanitized = trackId.components(separatedBy: invalid).joined(separator: "_")
        return sanitized.isEmpty ? "unknown" : sanitized
    }
    
    private func readDiskCache(for trackId: String) -> CachedLyrics? {
        let fileURL = cacheDirectory.appendingPathComponent("\(safeFilename(for: trackId)).json")
        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder().decode(CachedLyrics.self, from: data) else {
            return nil
        }
        return cached
    }
    
    private func writeDiskCache(trackId: String, text: String, isSynced: Bool, source: String?) {
        let fileURL = cacheDirectory.appendingPathComponent("\(safeFilename(for: trackId)).json")
        let cached = CachedLyrics(
            id: trackId,
            lyricsText: text,
            hasSyncedLyrics: isSynced,
            source: source,
            cachedAt: Date()
        )
        if let data = try? JSONEncoder().encode(cached) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
    
    public func refetchLyrics(forceRemote: Bool = true) {
        lyricsFetchTask?.cancel()
        if forceRemote {
            let fileURL = cacheDirectory.appendingPathComponent("\(safeFilename(for: id)).json")
            try? FileManager.default.removeItem(at: fileURL)
            self.lyricsText = nil
            self.hasSyncedLyrics = false
            self.lyricsSource = nil
        }
        triggerLyricsFetch(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            filePath: filePath,
            videoId: videoId,
            initialLyrics: forceRemote ? nil : lyricsText,
            initialSynced: forceRemote ? false : hasSyncedLyrics
        )
    }
    
    public func refetchArtwork() {
        artworkFetchTask?.cancel()
        let targetId = self.id
        Task {
            await ArtworkPipeline.shared.clearDiskCache(for: targetId)
        }
        self.artworkData = nil
        self.isFetchingArtwork = true
        triggerArtworkFetch(
            id: targetId,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            filePath: filePath,
            videoId: videoId,
            initialArtwork: nil,
            extensionArtworkURL: sourceURL
        )
    }
    
    public func setManualArtwork(data: Data) {
        artworkFetchTask?.cancel()
        let cropped = ArtworkPipeline.squareCropIfNeeded(data: data)
        self.artworkData = cropped
        self.isFetchingArtwork = false
        let targetId = self.id
        let targetArtist = self.artist
        let targetAlbum = self.album
        Task {
            await ArtworkPipeline.shared.setManualArtwork(data: cropped, stableId: targetId, artist: targetArtist, album: targetAlbum)
        }
    }
    
    public func setManualArtworkURL(_ url: URL) {
        artworkFetchTask?.cancel()
        self.isFetchingArtwork = true
        let targetId = self.id
        let targetArtist = self.artist
        let targetAlbum = self.album
        Task {
            if let data = await ArtworkPipeline.shared.setManualArtworkFromURL(url, stableId: targetId, artist: targetArtist, album: targetAlbum) {
                await MainActor.run {
                    guard self.id == targetId else { return }
                    self.artworkData = data
                    self.isFetchingArtwork = false
                }
            } else {
                await MainActor.run {
                    guard self.id == targetId else { return }
                    self.isFetchingArtwork = false
                }
            }
        }
    }
    
    private func triggerArtworkFetch(
        id: String,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        filePath: String,
        videoId: String?,
        initialArtwork: Data?,
        extensionArtworkURL: String?
    ) {
        artworkFetchTask?.cancel()
        
        if let art = initialArtwork, ArtworkPipeline.isHighResolution(data: art) {
            self.artworkData = ArtworkPipeline.squareCropIfNeeded(data: art)
            self.isFetchingArtwork = false
            return
        }
        
        if let art = initialArtwork {
            self.artworkData = ArtworkPipeline.squareCropIfNeeded(data: art)
        } else {
            self.artworkData = nil
        }
        
        self.isFetchingArtwork = (self.artworkData == nil)
        
        artworkFetchTask = Task { [weak self] in
            guard let self = self else { return }
            let fileURL = filePath.isEmpty ? nil : URL(fileURLWithPath: filePath)
            let result = await ArtworkPipeline.shared.resolveArtwork(
                fileURL: fileURL,
                artist: artist,
                title: title,
                album: album,
                duration: duration,
                extensionArtworkURL: extensionArtworkURL,
                stableId: id
            )
            
            await MainActor.run {
                guard self.id == id else { return }
                self.isFetchingArtwork = false
                if let art = result {
                    self.artworkData = art
                }
            }
        }
    }
    
    private func triggerLyricsFetch(
        id: String,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        filePath: String,
        videoId: String?,
        initialLyrics: String?,
        initialSynced: Bool
    ) {
        lyricsFetchTask?.cancel()
        
        // 1. Initial embedded lyrics
        if let text = initialLyrics, !text.isEmpty {
            self.lyricsText = text
            self.hasSyncedLyrics = initialSynced
            self.lyricsSource = "Embedded"
            self.isFetchingLyrics = false
            writeDiskCache(trackId: id, text: text, isSynced: initialSynced, source: "Embedded")
            return
        }
        
        // 2. Disk Cache
        if let cached = readDiskCache(for: id) {
            self.lyricsText = cached.lyricsText
            self.hasSyncedLyrics = cached.hasSyncedLyrics
            self.lyricsSource = cached.source
            self.isFetchingLyrics = false
            return
        }
        
        // 3. Remote / Engine Fetch
        self.isFetchingLyrics = true
        self.lyricsText = nil
        self.hasSyncedLyrics = false
        self.lyricsSource = nil
        
        lyricsFetchTask = Task { [weak self] in
            guard let self = self else { return }
            
            let fileURL = filePath.isEmpty ? nil : URL(fileURLWithPath: filePath)
            let result = await LyricsEngine.shared.resolveLyrics(
                url: fileURL,
                artist: artist,
                title: title,
                album: album.isEmpty ? nil : album,
                duration: duration > 0 ? duration : nil
            )
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                guard self.id == id else { return }
                
                if let result = result {
                    let rawText: String
                    if result.lyrics.lines.isEmpty {
                        rawText = ""
                    } else if result.lyrics.isSynced {
                        rawText = result.lyrics.lines.map { line in
                            let m = Int(line.time) / 60
                            let s = Int(line.time) % 60
                            let ms = Int((line.time.truncatingRemainder(dividingBy: 1)) * 100)
                            return String(format: "[%02d:%02d.%02d] %@", m, s, ms, line.text)
                        }.joined(separator: "\n")
                    } else {
                        rawText = result.lyrics.lines.map { $0.text }.joined(separator: "\n")
                    }
                    
                    self.lyricsText = rawText
                    self.hasSyncedLyrics = result.lyrics.isSynced
                    self.lyricsSource = result.source.rawValue
                    self.isFetchingLyrics = false
                    
                    self.writeDiskCache(
                        trackId: id,
                        text: rawText,
                        isSynced: result.lyrics.isSynced,
                        source: result.source.rawValue
                    )
                } else {
                    self.lyricsText = nil
                    self.hasSyncedLyrics = false
                    self.lyricsSource = nil
                    self.isFetchingLyrics = false
                }
            }
        }
    }
}
