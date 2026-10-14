import Foundation
import AppKit
import CryptoKit

/// Central coordinator for manual and automatic metadata fetching (covers, lyrics, scoring, and caching).
public actor MetadataFetcherCoordinator {
    public static let shared = MetadataFetcherCoordinator()
    
    private let ytmProvider = YouTubeMusicProvider.shared
    private let lrclibProvider = LRCLibProvider.shared
    private let itunesProvider = ITunesProvider.shared
    private let captionsProvider = YouTubeCaptionsProvider.shared
    
    // Auto-find state management
    private var isAutoFindPaused = false
    private var isAutoFindCancelled = false
    
    private init() {}
    
    // MARK: - Query Cleaning & Video ID Extraction
    
    /// Cleans common YouTube noise and prepares prefilled query while removing emojis and suffixes.
    public static func cleanSearchQuery(title: String, artist: String) -> (cleanedQuery: String, rawTitle: String) {
        let raw = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = raw
        
        // Remove unicode emojis
        text = text.unicodeScalars.filter { scalar in
            !(scalar.value >= 0x1F600 && scalar.value <= 0x1F64F) && // Emoticons
            !(scalar.value >= 0x1F300 && scalar.value <= 0x1F5FF) && // Misc Symbols
            !(scalar.value >= 0x1F680 && scalar.value <= 0x1F6FF) && // Transport
            !(scalar.value >= 0x2600 && scalar.value <= 0x26FF)   && // Misc Symbols
            !(scalar.value >= 0x2700 && scalar.value <= 0x27BF)   && // Dingbats
            !(scalar.value >= 0xFE00 && scalar.value <= 0xFE0F)   && // Variation Selectors
            !(scalar.value >= 0x1F900 && scalar.value <= 0x1F9FF)    // Supplemental Symbols
        }.map { String($0) }.joined()
        
        // Remove feat / ft from title if present
        text = text.replacingOccurrences(of: "(?i)\\b(?:ft\\.?|feat\\.?|featuring)\\s+[^(\\[\\-]+", with: "", options: .regularExpression)
        
        // Remove common YouTube bracket noise
        let bracketNoise = [
            "\\((?:(?:official\\s*)?(?:music\\s*video|lyric\\s*video|video|audio)|lyrics?|hd|4k|visualizer)\\)",
            "\\[(?:(?:official\\s*)?(?:music\\s*video|lyric\\s*video|video|audio)|lyrics?|hd|4k|visualizer|[A-Za-z0-9_-]{11})\\]"
        ]
        for pattern in bracketNoise {
            text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        
        // Remove | Topic, - Topic
        text = text.replacingOccurrences(of: "(?i)[|\\-•·]\\s*topic\\b", with: "", options: .regularExpression)
        
        // Remove trailing channel suffixes & video descriptors
        let suffixPattern = "(?i)\\s*([|•·/]|\\s-\\s)\\s*(official\\s+video|official\\s+audio|official\\s+music\\s+video|audio\\s+track|audio|video|hd|4k|vevo)\\s*$"
        text = text.replacingOccurrences(of: suffixPattern, with: "", options: .regularExpression)
        
        // Strip trailing/leading punctuation
        text = text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—:|/•·")))
        
        var cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanArtist.lowercased() == "unknown" || cleanArtist.lowercased().contains("topic") {
            cleanArtist = ""
        } else {
            cleanArtist = cleanArtist.replacingOccurrences(of: "(?i)\\s*-\\s*topic\\b", with: "", options: .regularExpression)
            cleanArtist = cleanArtist.replacingOccurrences(of: "(?i)\\b(?:ft\\.?|feat\\.?|featuring)\\s+.*$", with: "", options: .regularExpression)
            cleanArtist = cleanArtist.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—:|/•·")))
        }
        
        var combined = text
        if !cleanArtist.isEmpty && !text.lowercased().contains(cleanArtist.lowercased()) {
            combined = "\(cleanArtist) \(text)"
        }
        
        return (combined.isEmpty ? raw : combined, raw)
    }
    
    /// Extracts an 11-character YouTube video ID from any link, embed, or filename pattern.
    public static func extractYouTubeVideoId(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>\"'()[]{}")))
        guard !trimmed.isEmpty else { return nil }
        
        let validIDChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        
        // 1. Direct 11-char ID
        if trimmed.count == 11 && trimmed.rangeOfCharacter(from: validIDChars.inverted) == nil {
            return trimmed
        }
        
        // 2. URL parsing with URLComponents (handles any query parameter order or prefix)
        var urlStringToParse = trimmed
        if !urlStringToParse.hasPrefix("http://") && !urlStringToParse.hasPrefix("https://") {
            if urlStringToParse.contains("youtube.com") || urlStringToParse.contains("youtu.be") {
                urlStringToParse = "https://" + urlStringToParse
            }
        }
        
        if let url = URL(string: urlStringToParse), let comps = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            // Check query item "v"
            if let vItem = comps.queryItems?.first(where: { $0.name == "v" })?.value,
               vItem.count == 11, vItem.rangeOfCharacter(from: validIDChars.inverted) == nil {
                return vItem
            }
            
            // Check path components: youtu.be/<id>, /shorts/<id>, /live/<id>, /embed/<id>, /v/<id>
            let pathSegments = url.pathComponents.filter { $0 != "/" }
            if let host = url.host?.lowercased(), host.contains("youtu.be"), let first = pathSegments.first,
               first.count == 11, first.rangeOfCharacter(from: validIDChars.inverted) == nil {
                return first
            }
            
            if let last = pathSegments.last, last.count == 11, last.rangeOfCharacter(from: validIDChars.inverted) == nil {
                let prev = pathSegments.dropLast().last?.lowercased() ?? ""
                if ["shorts", "live", "embed", "v", "watch"].contains(prev) || (url.host?.lowercased().contains("youtube") ?? false) {
                    return last
                }
            }
        }
        
        // 3. Regex fallback across all standard YouTube URL patterns
        let urlRegex = try? NSRegularExpression(
            pattern: "(?:[?&]v=|youtu\\.be/|/shorts/|/embed/|/live/|/v/)([A-Za-z0-9_-]{11})(?:[?&#/\\s]|$)",
            options: [.caseInsensitive]
        )
        if let match = urlRegex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[range])
        }
        
        // 4. Filename bracket: [11-chars] or -11-chars before extension
        let fileRegex = try? NSRegularExpression(
            pattern: "(?:\\[([A-Za-z0-9_-]{11})\\]|-([A-Za-z0-9_-]{11}))\\.[a-zA-Z0-9]+$",
            options: []
        )
        if let match = fileRegex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            if match.range(at: 1).location != NSNotFound, let r1 = Range(match.range(at: 1), in: trimmed) {
                return String(trimmed[r1])
            }
            if match.range(at: 2).location != NSNotFound, let r2 = Range(match.range(at: 2), in: trimmed) {
                return String(trimmed[r2])
            }
        }
        
        return nil
    }
    
    // MARK: - Match Scoring
    
    /// Computes match score (0.0 to 1.0) comparing a search candidate against a local track.
    public static func computeMatchScore(candidate: MetadataSearchResult, localTitle: String, localArtist: String, localDuration: TimeInterval) -> Double {
        let (cleanedLocal, _) = cleanSearchQuery(title: localTitle, artist: localArtist)
        var cleanTitleOnly = cleanedLocal
        if !localArtist.isEmpty && cleanTitleOnly.lowercased().hasPrefix(localArtist.lowercased()) {
            cleanTitleOnly = String(cleanTitleOnly.dropFirst(localArtist.count)).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—: ")))
        }
        
        var titleScore = max(
            OnlineVerifier.tokenSetSimilarity(localTitle, candidate.title),
            OnlineVerifier.tokenSetSimilarity(cleanTitleOnly, candidate.title),
            OnlineVerifier.tokenSetSimilarity(cleanedLocal, candidate.title)
        )
        let cTokens = Set(OnlineVerifier.normalizeTokens(candidate.title))
        let lTokens = Set(OnlineVerifier.normalizeTokens(cleanTitleOnly.isEmpty ? localTitle : cleanTitleOnly))
        if !cTokens.isEmpty && (cTokens.isSubset(of: lTokens) || lTokens.isSubset(of: cTokens)) {
            titleScore = max(titleScore, 0.95)
        }
        
        let artistScore: Double
        if localArtist.trimmingCharacters(in: .whitespaces).isEmpty || localArtist.lowercased() == "unknown" {
            artistScore = 0.80
        } else {
            var aScore = OnlineVerifier.tokenSetSimilarity(localArtist, candidate.artist)
            let qTokens = Set(OnlineVerifier.normalizeTokens(localArtist))
            let rTokens = Set(OnlineVerifier.normalizeTokens(candidate.artist))
            if !qTokens.isEmpty && qTokens.isSubset(of: rTokens) {
                aScore = max(aScore, 0.90)
            }
            artistScore = aScore
        }
        
        var durationScore = 0.5
        if localDuration > 5.0 && candidate.duration > 5.0 {
            let delta = abs(localDuration - candidate.duration)
            if delta <= 3.0 {
                durationScore = 1.0 // Strong duration match
            } else if delta <= 8.0 {
                durationScore = 0.85
            } else if delta <= 15.0 {
                durationScore = 0.60
            } else if delta <= 30.0 {
                durationScore = 0.30
            } else {
                durationScore = 0.0
            }
        }
        
        if localDuration > 5.0 && candidate.duration > 5.0 {
            return (0.45 * titleScore) + (0.35 * artistScore) + (0.20 * durationScore)
        } else {
            return (0.60 * titleScore) + (0.40 * artistScore)
        }
    }
    
    // MARK: - Search Orchestration
    
    func search(query: String, localTrack: Track) async -> [MetadataSearchResult] {
        var results: [MetadataSearchResult] = []
        
        // 1. If query is or contains a YouTube link/ID, perform direct lookup first
        if let videoId = Self.extractYouTubeVideoId(from: query) {
            if let directHit = try? await ytmProvider.lookupVideoId(videoId) {
                var scoredHit = directHit
                scoredHit.matchScore = 1.0
                scoredHit.source = "YouTube Music (Exact Link)"
                results.append(scoredHit)
            }
        }
        
        // 2. Query YouTube Music (songs first)
        let ytmHits = (try? await ytmProvider.search(query: query)) ?? []
        for hit in ytmHits {
            if results.contains(where: { $0.videoId == hit.videoId }) { continue }
            var scored = hit
            scored.matchScore = Self.computeMatchScore(
                candidate: hit,
                localTitle: localTrack.displayTitle,
                localArtist: localTrack.displayArtist,
                localDuration: localTrack.duration
            )
            results.append(scored)
        }
        
        // 3. Fallback to iTunes if YouTube Music gave fewer than 3 results
        if results.count < 3 {
            let itunesHits = (try? await itunesProvider.search(query: query)) ?? []
            for hit in itunesHits {
                var scored = hit
                scored.matchScore = Self.computeMatchScore(
                    candidate: hit,
                    localTitle: localTrack.displayTitle,
                    localArtist: localTrack.displayArtist,
                    localDuration: localTrack.duration
                )
                results.append(scored)
            }
        }
        
        // Sort results by match score descending
        return results.sorted { $0.matchScore > $1.matchScore }
    }
    
    // MARK: - Preview Fetching (Cover + Lyrics)
    
    public struct CandidatePreview: Sendable {
        public let candidate: MetadataSearchResult
        public let coverCandidate: CoverArtCandidate?
        public let lyricsCandidate: LyricsResultCandidate?
    }
    
    func fetchPreview(for candidate: MetadataSearchResult, localTrack: Track) async -> CandidatePreview {
        // Fetch Cover Art: try YouTube Music first, fallback to iTunes
        async let coverFetch: CoverArtCandidate? = {
            if let cover = try? await ytmProvider.fetchCoverArt(for: candidate) {
                return cover
            }
            if let itunesHit = try? await itunesProvider.search(query: "\(candidate.artist) \(candidate.title)").first,
               let itunesCover = try? await itunesProvider.fetchCoverArt(for: itunesHit) {
                return itunesCover
            }
            return nil
        }()
        
        // Fetch Lyrics in order of priority:
        // 1. LRCLIB using match candidate (synced preferred, then plain)
        // 2. LRCLIB using local track title & artist (if candidate is a noisy video title)
        // 3. YouTube Music lyrics (direct video or official song track)
        // 4. Captions via yt-dlp if available
        async let lyricsFetch: LyricsResultCandidate? = {
            let targetDur = candidate.duration > 0 ? candidate.duration : localTrack.duration
            
            // Priority 1: Check LRCLIB using candidate metadata
            if let lrclib = await lrclibProvider.fetchLyrics(
                title: candidate.title,
                artist: candidate.artist,
                album: candidate.album,
                duration: targetDur
            ) {
                return lrclib
            }
            
            // Priority 2: Fall back to LRCLIB using localTrack parsed metadata if different
            let localTitle = localTrack.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let localArtist = localTrack.displayArtist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !localTitle.isEmpty && (localTitle != candidate.title || localArtist != candidate.artist) {
                if let lrclibLocal = await lrclibProvider.fetchLyrics(
                    title: localTitle,
                    artist: localArtist,
                    album: localTrack.albumTitle,
                    duration: targetDur
                ) {
                    return lrclibLocal
                }
            }
            
            // Priority 3: Check YouTube Music lyrics
            if let ytmLyrics = try? await ytmProvider.fetchLyrics(for: candidate, duration: targetDur) {
                return ytmLyrics
            }
            
            // Priority 4: Video captions via yt-dlp
            if let vid = candidate.videoId,
               let captions = await captionsProvider.fetchCaptions(videoId: vid) {
                return captions
            }
            
            return nil
        }()
        
        let cover = await coverFetch
        let lyrics = await lyricsFetch
        
        return CandidatePreview(
            candidate: candidate,
            coverCandidate: cover,
            lyricsCandidate: lyrics
        )
    }
    
    // MARK: - Applying Matches to Library
    
    public func applyMatch(
        trackId: UUID,
        candidate: MetadataSearchResult,
        coverCandidate: CoverArtCandidate?,
        lyricsCandidate: LyricsResultCandidate?,
        applyCover: Bool,
        applyLyrics: Bool
    ) async {
        var allTracks = await PersistenceStore.shared.loadAll(Track.self)
        guard let idx = allTracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        var track = allTracks[idx]
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let artworkDir = appSupport.appendingPathComponent("Lumo/Artwork", isDirectory: true)
        let artworkCacheDir = appSupport.appendingPathComponent("Lumo/ArtworkCache", isDirectory: true)
        let lyricsCacheDir = appSupport.appendingPathComponent("Lumo/LyricsCache", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: artworkDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: artworkCacheDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: lyricsCacheDir, withIntermediateDirectories: true)
        
        let stableId = NowPlayingSnapshot.stableIDForLocal(filePath: track.filePath)
        
        // 1. Process Cover Art
        if applyCover, let cover = coverCandidate {
            let processed = ArtworkPipeline.squareCropIfNeeded(data: cover.data)
            let hash = SHA256.hash(data: processed).compactMap { String(format: "%02x", $0) }.joined()
            
            // Save original image to disk
            let hashFile = artworkDir.appendingPathComponent("\(hash).jpg")
            try? processed.write(to: hashFile, options: .atomic)
            
            let idFile = artworkCacheDir.appendingPathComponent("\(stableId).jpg")
            try? processed.write(to: idFile, options: .atomic)
            
            // Downsample copies for list (32px) and visualizer (1024px)
            Self.createDownsampledCopies(data: processed, hash: hash, cacheDir: artworkCacheDir)
            
            track.artworkHash = hash
            track.isCoverLocked = true
            track.isCoverVideoThumbnail = cover.isVideoThumbnail
            
            // Update NowPlayingSnapshot in-memory immediately if this is the active track
            await MainActor.run {
                if NowPlayingSnapshot.shared.id == stableId || NowPlayingSnapshot.shared.title == track.displayTitle {
                    NowPlayingSnapshot.shared.artworkData = processed
                }
            }
            
            // Optional: Tag audio file if setting enabled
            let settings = await PersistenceStore.shared.loadAll(AppSettings.self).first ?? AppSettings.defaults
            if settings.writeCoverAndTagsToFile {
                Self.writeTagsToFile(filePath: track.filePath, artworkData: processed, title: candidate.title, artist: candidate.artist)
            }
        }
        
        // 2. Process Lyrics
        if applyLyrics, let lyrics = lyricsCandidate {
            track.lyricsText = lyrics.lyricsText
            track.hasSyncedLyrics = lyrics.isSynced
            track.lyricsSource = lyrics.source
            track.isLyricsLocked = true
            
            // Write to disk cache
            let cached = [
                "id": stableId,
                "lyricsText": lyrics.lyricsText,
                "hasSyncedLyrics": "\(lyrics.isSynced)",
                "source": lyrics.source,
                "cachedAt": "\(Date().timeIntervalSince1970)"
            ]
            let lyricsFile = lyricsCacheDir.appendingPathComponent("\(stableId).json")
            if let data = try? JSONSerialization.data(withJSONObject: cached) {
                try? data.write(to: lyricsFile, options: .atomic)
            }
            
            // Update NowPlayingSnapshot in-memory immediately
            await MainActor.run {
                if NowPlayingSnapshot.shared.id == stableId || NowPlayingSnapshot.shared.title == track.displayTitle {
                    NowPlayingSnapshot.shared.lyricsText = lyrics.lyricsText
                    NowPlayingSnapshot.shared.hasSyncedLyrics = lyrics.isSynced
                    NowPlayingSnapshot.shared.lyricsSource = lyrics.source
                }
            }
        }
        
        // Update track metadata
        track.metadataSource = .manual
        track.metadataConfidence = 1.0
        if let vid = candidate.videoId, !vid.isEmpty {
            track.youtubeVideoId = vid
        }
        allTracks[idx] = track
        try? await PersistenceStore.shared.saveAll(allTracks)
        
        await MainActor.run {
            NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
        }
    }
    
    // MARK: - Reset to Automatic
    
    public func resetToAutomatic(trackId: UUID) async {
        var allTracks = await PersistenceStore.shared.loadAll(Track.self)
        guard let idx = allTracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        allTracks[idx].isCoverLocked = false
        allTracks[idx].isLyricsLocked = false
        try? await PersistenceStore.shared.saveAll(allTracks)
        
        await MainActor.run {
            NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
        }
    }
    
    // MARK: - Auto-Find Engine
    
    public func pauseAutoFind() {
        isAutoFindPaused = true
    }
    
    public func resumeAutoFind() {
        isAutoFindPaused = false
    }
    
    public func cancelAutoFind() {
        isAutoFindCancelled = true
        isAutoFindPaused = false
    }
    
    public func autoFindMissing(
        scope: AutoFindScope,
        selectedIds: Set<UUID> = [],
        progressHandler: @escaping @Sendable (AutoFindProgress) -> Void
    ) async {
        isAutoFindPaused = false
        isAutoFindCancelled = false
        
        var allTracks = await PersistenceStore.shared.loadAll(Track.self)
        let targets: [Track]
        
        switch scope {
        case .selected:
            targets = allTracks.filter { selectedIds.contains($0.id) }
        case .missingCover:
            targets = allTracks.filter { $0.artworkHash == nil || $0.artworkHash?.isEmpty == true }
        case .missingLyrics:
            targets = allTracks.filter { $0.lyricsText == nil || $0.lyricsText?.isEmpty == true }
        case .all:
            targets = allTracks
        }
        
        var progress = AutoFindProgress(total: targets.count)
        progressHandler(progress)
        
        for track in targets {
            if isAutoFindCancelled {
                progress.isCancelled = true
                progressHandler(progress)
                return
            }
            
            while isAutoFindPaused {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if isAutoFindCancelled {
                    progress.isCancelled = true
                    progressHandler(progress)
                    return
                }
            }
            
            progress.currentTrackTitle = track.displayTitle
            progressHandler(progress)
            
            // Respect manual lock: never overwrite user-locked choices
            let shouldCheckCover = !track.isCoverLocked && (track.artworkHash == nil || track.artworkHash?.isEmpty == true || track.isCoverVideoThumbnail)
            let shouldCheckLyrics = !track.isLyricsLocked && (track.lyricsText == nil || track.lyricsText?.isEmpty == true)
            
            if !shouldCheckCover && !shouldCheckLyrics {
                progress.processed += 1
                progressHandler(progress)
                continue
            }
            
            // Search query strategy: Video ID first if known, else cleaned title + artist
            var query = ""
            if let vid = track.youtubeVideoId ?? Self.extractYouTubeVideoId(from: track.fileName) {
                query = vid
            } else {
                let cleaned = Self.cleanSearchQuery(title: track.displayTitle, artist: track.displayArtist)
                query = cleaned.cleanedQuery
            }
            
            let searchResults = await search(query: query, localTrack: track)
            
            if let bestMatch = searchResults.first {
                if bestMatch.matchScore >= 0.85 {
                    // High confidence: Auto-apply
                    let preview = await fetchPreview(for: bestMatch, localTrack: track)
                    await applyMatch(
                        trackId: track.id,
                        candidate: bestMatch,
                        coverCandidate: shouldCheckCover ? preview.coverCandidate : nil,
                        lyricsCandidate: shouldCheckLyrics ? preview.lyricsCandidate : nil,
                        applyCover: shouldCheckCover && preview.coverCandidate != nil,
                        applyLyrics: shouldCheckLyrics && preview.lyricsCandidate != nil
                    )
                    progress.appliedCount += 1
                } else if bestMatch.matchScore >= 0.60 {
                    // Moderate confidence: Send to Needs Review with best candidate saved
                    if let tIdx = allTracks.firstIndex(where: { $0.id == track.id }) {
                        allTracks[tIdx].metadataConfidence = bestMatch.matchScore
                        try? await PersistenceStore.shared.saveAll(allTracks)
                    }
                    progress.needsReviewCount += 1
                } else {
                    progress.noMatchCount += 1
                }
            } else {
                progress.noMatchCount += 1
            }
            
            progress.processed += 1
            progressHandler(progress)
            
            // Polite delay (500ms) between songs to avoid spamming
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        progress.isFinished = true
        progressHandler(progress)
        
        await MainActor.run {
            NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
        }
    }
    
    // MARK: - Internal Helpers
    
    private static func createDownsampledCopies(data: Data, hash: String, cacheDir: URL) {
        guard let image = NSImage(data: data) else { return }
        
        // 32px for list
        if let listData = resizeImage(image, targetSize: NSSize(width: 32, height: 32)) {
            let listFile = cacheDir.appendingPathComponent("\(hash)_32.jpg")
            try? listData.write(to: listFile, options: .atomic)
        }
        
        // 1024px for visualizer
        if let vizData = resizeImage(image, targetSize: NSSize(width: 1024, height: 1024)) {
            let vizFile = cacheDir.appendingPathComponent("\(hash)_1024.jpg")
            try? vizData.write(to: vizFile, options: .atomic)
        }
    }
    
    private static func resizeImage(_ image: NSImage, targetSize: NSSize) -> Data? {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        
        guard let tiff = newImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
    
    private static func writeTagsToFile(filePath: String, artworkData: Data, title: String, artist: String) {
        // Safe backup before write
        let originalURL = URL(fileURLWithPath: filePath)
        let backupURL = originalURL.appendingPathExtension("bak")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.copyItem(at: originalURL, to: backupURL)
        }
        
        // Write metadata if ffmpeg is available
        let ffmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        guard let ffmpeg = ffmpegPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        
        let tempOut = originalURL.deletingPathExtension().appendingPathExtension("tmp." + originalURL.pathExtension)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-i", originalURL.path,
            "-metadata", "title=\(title)",
            "-metadata", "artist=\(artist)",
            "-codec", "copy",
            "-y", tempOut.path
        ]
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            _ = try? FileManager.default.replaceItemAt(originalURL, withItemAt: tempOut)
        }
    }
}
