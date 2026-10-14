import Foundation

/// Unified search result from any metadata provider (YouTube Music, iTunes, LRCLIB).
public struct MetadataSearchResult: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var videoId: String?
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var thumbnailURL: String?
    public var highResArtworkURL: String?
    public var matchScore: Double
    public var isSquareArtwork: Bool
    public var source: String
    
    public init(
        id: String = UUID().uuidString,
        videoId: String? = nil,
        title: String,
        artist: String,
        album: String = "",
        duration: TimeInterval = 0,
        thumbnailURL: String? = nil,
        highResArtworkURL: String? = nil,
        matchScore: Double = 0.0,
        isSquareArtwork: Bool = true,
        source: String = "YouTube Music"
    ) {
        self.id = id
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.highResArtworkURL = highResArtworkURL
        self.matchScore = matchScore
        self.isSquareArtwork = isSquareArtwork
        self.source = source
    }
    
    /// Formatted duration string (e.g. "3:42")
    public var formattedDuration: String {
        guard duration > 0 else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Downloaded and processed cover art candidate.
public struct CoverArtCandidate: Sendable {
    public let data: Data
    public let source: String
    public let isHighRes: Bool
    public let isSquare: Bool
    public let isVideoThumbnail: Bool
    
    public init(
        data: Data,
        source: String,
        isHighRes: Bool = true,
        isSquare: Bool = true,
        isVideoThumbnail: Bool = false
    ) {
        self.data = data
        self.source = source
        self.isHighRes = isHighRes
        self.isSquare = isSquare
        self.isVideoThumbnail = isVideoThumbnail
    }
}

/// Resolved lyrics candidate with synchronization status and metadata.
public struct LyricsResultCandidate: Sendable {
    public let lyricsText: String
    public let isSynced: Bool
    public let source: String
    public let durationValid: Bool
    public let lastTimestamp: TimeInterval?
    public let detectedScript: String?
    public let romanizedText: String?
    
    public init(
        lyricsText: String,
        isSynced: Bool,
        source: String,
        durationValid: Bool = true,
        lastTimestamp: TimeInterval? = nil,
        detectedScript: String? = nil,
        romanizedText: String? = nil
    ) {
        self.lyricsText = lyricsText
        self.isSynced = isSynced
        self.source = source
        self.durationValid = durationValid
        self.lastTimestamp = lastTimestamp
        self.detectedScript = detectedScript
        self.romanizedText = romanizedText
    }
}

/// Scope options for automatic batch metadata searching.
public enum AutoFindScope: String, CaseIterable, Identifiable, Sendable {
    case selected = "Selected songs only"
    case missingCover = "Songs missing cover"
    case missingLyrics = "Songs missing lyrics"
    case all = "All songs in library"
    
    public var id: String { rawValue }
}

/// Progress state for the background auto-find job.
public struct AutoFindProgress: Sendable, Equatable {
    public var processed: Int = 0
    public var total: Int = 0
    public var currentTrackTitle: String = ""
    public var appliedCount: Int = 0
    public var needsReviewCount: Int = 0
    public var noMatchCount: Int = 0
    public var isPaused: Bool = false
    public var isCancelled: Bool = false
    public var isFinished: Bool = false
    
    public init(
        processed: Int = 0,
        total: Int = 0,
        currentTrackTitle: String = "",
        appliedCount: Int = 0,
        needsReviewCount: Int = 0,
        noMatchCount: Int = 0,
        isPaused: Bool = false,
        isCancelled: Bool = false,
        isFinished: Bool = false
    ) {
        self.processed = processed
        self.total = total
        self.currentTrackTitle = currentTrackTitle
        self.appliedCount = appliedCount
        self.needsReviewCount = needsReviewCount
        self.noMatchCount = noMatchCount
        self.isPaused = isPaused
        self.isCancelled = isCancelled
        self.isFinished = isFinished
    }
    
    public var fractionCompleted: Double {
        total > 0 ? Double(processed) / Double(total) : 0.0
    }
}
