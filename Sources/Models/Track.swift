import Foundation

/// Represents a single audio track in the library.
struct Track: Codable, Identifiable, Hashable, Sendable {
    // MARK: - Identity
    
    /// Unique identifier for this track.
    var id: UUID
    
    /// Absolute file path (resolved from security-scoped bookmark).
    var filePath: String
    
    /// File name with extension.
    var fileName: String
    
    /// File extension (lowercase, e.g. "mp3", "flac").
    var fileExtension: String
    
    /// Security-scoped bookmark data for sandbox access.
    var bookmarkData: Data?
    
    // MARK: - Metadata
    
    var title: String
    var artistName: String
    var albumTitle: String
    var albumArtistName: String
    var genreName: String
    var composer: String
    
    /// Track number within the album disc.
    var trackNumber: Int
    
    /// Total tracks on the disc.
    var trackTotal: Int
    
    /// Disc number for multi-disc albums.
    var discNumber: Int
    
    /// Total discs in the album.
    var discTotal: Int
    
    /// Release year.
    var year: Int
    
    /// Duration in seconds.
    var duration: TimeInterval
    
    // MARK: - Audio Properties
    
    /// Sample rate in Hz (e.g. 44100, 96000).
    var sampleRate: Int
    
    /// Bit depth (e.g. 16, 24, 32).
    var bitDepth: Int
    
    /// Bitrate in kbps.
    var bitrate: Int
    
    /// Number of audio channels.
    var channels: Int
    
    /// File size in bytes.
    var fileSize: Int64
    
    // MARK: - Artwork
    
    /// SHA-256 hash of artwork data for deduplication.
    /// Artwork itself is stored separately on disk to avoid bloating the JSON.
    var artworkHash: String?
    
    /// Whether user manually selected artwork (blocks automatic overwrite).
    var isCoverLocked: Bool = false
    
    /// Whether artwork is a cropped 16:9 video thumbnail (can be upgraded later).
    var isCoverVideoThumbnail: Bool = false
    
    // MARK: - User Data
    
    /// Whether the track is favorited.
    var isFavorite: Bool
    
    /// User rating (0-5, 0 = unrated).
    var rating: Int
    
    /// Total play count.
    var playCount: Int
    
    /// Last time this track was played.
    var lastPlayedAt: Date?
    
    /// When the track was added to the library.
    var addedAt: Date
    
    /// When the file was last modified on disk.
    var fileModifiedAt: Date
    
    // MARK: - Normalization
    
    /// ReplayGain track gain in dB (nil if not available).
    var replayGainTrackGain: Float?
    
    /// ReplayGain track peak.
    var replayGainTrackPeak: Float?
    
    /// ReplayGain album gain in dB.
    var replayGainAlbumGain: Float?
    
    /// ReplayGain album peak.
    var replayGainAlbumPeak: Float?
    
    // MARK: - Lyrics
    
    /// Embedded or sidecar lyrics text (plain or synced LRC).
    var lyricsText: String?
    
    /// Whether lyricsText contains synced (.lrc) timestamps.
    var hasSyncedLyrics: Bool = false
    
    /// Lyrics source name (e.g. "LRCLIB (synced)", "YouTube Music").
    var lyricsSource: String? = nil
    
    /// Whether user manually selected lyrics (blocks automatic overwrite).
    var isLyricsLocked: Bool = false
    
    /// Path to sidecar .lrc file, if found.
    var sidecarLyricsPath: String?
    
    // MARK: - Smart Metadata
    
    /// The source of this track's metadata.
    var metadataSource: MetadataSource = .tag
    
    /// The confidence score of the current metadata (0.0 to 1.0).
    var metadataConfidence: Double = 1.0
    
    /// YouTube video ID if known or matched.
    var youtubeVideoId: String? = nil
    
    // MARK: - Quality Analysis
    
    /// Audio quality status assigned by QualityAnalyzer.
    var qualityStatus: AudioQualityStatus?
    
    /// Whether this track needs duration/metadata probing.
    var needsProbe: Bool = false
    
    // MARK: - Relationships (by ID)
    
    var albumId: UUID?
    var artistId: UUID?
    var genreId: UUID?
    var libraryFolderId: UUID?
    
    // MARK: - Init
    
    init(
        filePath: String,
        fileName: String,
        fileExtension: String,
        title: String = "",
        artistName: String = "",
        albumTitle: String = "",
        duration: TimeInterval = 0
    ) {
        self.id = UUID()
        self.filePath = filePath
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.title = title.isEmpty ? fileName : title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.albumArtistName = ""
        self.genreName = ""
        self.composer = ""
        self.trackNumber = 0
        self.trackTotal = 0
        self.discNumber = 1
        self.discTotal = 1
        self.year = 0
        self.duration = duration
        self.sampleRate = 0
        self.bitDepth = 0
        self.bitrate = 0
        self.channels = 2
        self.fileSize = 0
        self.isFavorite = false
        self.rating = 0
        self.playCount = 0
        self.addedAt = Date()
        self.fileModifiedAt = Date()
        self.hasSyncedLyrics = false
        self.lyricsText = nil
        self.lyricsSource = nil
        self.isLyricsLocked = false
        self.isCoverLocked = false
        self.isCoverVideoThumbnail = false
        self.youtubeVideoId = nil
        self.sidecarLyricsPath = nil
        self.bookmarkData = nil
    }
    
    // MARK: - Decodable
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.filePath = try container.decodeIfPresent(String.self, forKey: .filePath) ?? ""
        self.fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        self.fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension) ?? ""
        self.bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.artistName = try container.decodeIfPresent(String.self, forKey: .artistName) ?? ""
        self.albumTitle = try container.decodeIfPresent(String.self, forKey: .albumTitle) ?? ""
        self.albumArtistName = try container.decodeIfPresent(String.self, forKey: .albumArtistName) ?? ""
        self.genreName = try container.decodeIfPresent(String.self, forKey: .genreName) ?? ""
        self.composer = try container.decodeIfPresent(String.self, forKey: .composer) ?? ""
        self.trackNumber = try container.decodeIfPresent(Int.self, forKey: .trackNumber) ?? 0
        self.trackTotal = try container.decodeIfPresent(Int.self, forKey: .trackTotal) ?? 0
        self.discNumber = try container.decodeIfPresent(Int.self, forKey: .discNumber) ?? 1
        self.discTotal = try container.decodeIfPresent(Int.self, forKey: .discTotal) ?? 1
        self.year = try container.decodeIfPresent(Int.self, forKey: .year) ?? 0
        self.duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        self.sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 0
        self.bitDepth = try container.decodeIfPresent(Int.self, forKey: .bitDepth) ?? 0
        self.bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate) ?? 0
        self.channels = try container.decodeIfPresent(Int.self, forKey: .channels) ?? 2
        self.fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        self.artworkHash = try container.decodeIfPresent(String.self, forKey: .artworkHash)
        self.isCoverLocked = try container.decodeIfPresent(Bool.self, forKey: .isCoverLocked) ?? false
        self.isCoverVideoThumbnail = try container.decodeIfPresent(Bool.self, forKey: .isCoverVideoThumbnail) ?? false
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.rating = try container.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        self.playCount = try container.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        self.lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        self.addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        self.fileModifiedAt = try container.decodeIfPresent(Date.self, forKey: .fileModifiedAt) ?? Date()
        self.replayGainTrackGain = try container.decodeIfPresent(Float.self, forKey: .replayGainTrackGain)
        self.replayGainTrackPeak = try container.decodeIfPresent(Float.self, forKey: .replayGainTrackPeak)
        self.replayGainAlbumGain = try container.decodeIfPresent(Float.self, forKey: .replayGainAlbumGain)
        self.replayGainAlbumPeak = try container.decodeIfPresent(Float.self, forKey: .replayGainAlbumPeak)
        self.lyricsText = try container.decodeIfPresent(String.self, forKey: .lyricsText)
        self.hasSyncedLyrics = try container.decodeIfPresent(Bool.self, forKey: .hasSyncedLyrics) ?? false
        self.lyricsSource = try container.decodeIfPresent(String.self, forKey: .lyricsSource)
        self.isLyricsLocked = try container.decodeIfPresent(Bool.self, forKey: .isLyricsLocked) ?? false
        self.sidecarLyricsPath = try container.decodeIfPresent(String.self, forKey: .sidecarLyricsPath)
        self.metadataSource = try container.decodeIfPresent(MetadataSource.self, forKey: .metadataSource) ?? .tag
        self.metadataConfidence = try container.decodeIfPresent(Double.self, forKey: .metadataConfidence) ?? 1.0
        self.youtubeVideoId = try container.decodeIfPresent(String.self, forKey: .youtubeVideoId)
        self.qualityStatus = try container.decodeIfPresent(AudioQualityStatus.self, forKey: .qualityStatus)
        self.needsProbe = try container.decodeIfPresent(Bool.self, forKey: .needsProbe) ?? false
        self.albumId = try container.decodeIfPresent(UUID.self, forKey: .albumId)
        self.artistId = try container.decodeIfPresent(UUID.self, forKey: .artistId)
        self.genreId = try container.decodeIfPresent(UUID.self, forKey: .genreId)
        self.libraryFolderId = try container.decodeIfPresent(UUID.self, forKey: .libraryFolderId)
    }
}

// MARK: - Computed

extension Track {
    /// Display title, falling back to file name.
    var displayTitle: String {
        title.isEmpty ? fileName : title
    }
    
    /// Display artist, with fallback.
    var displayArtist: String {
        artistName.isEmpty ? "Unknown Artist" : artistName
    }
    
    /// Display album, with fallback.
    var displayAlbum: String {
        albumTitle.isEmpty ? "Unknown Album" : albumTitle
    }
    
    /// Whether this file uses a natively supported format.
    var isNativeFormat: Bool {
        AppConstants.Library.nativeFormats.contains(fileExtension.lowercased())
    }
    
    /// Formatted duration string (e.g., "3:42").
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
