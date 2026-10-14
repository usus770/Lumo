import Foundation

/// Defines the origin of a track's metadata.
public enum MetadataSource: String, Codable, Sendable, Hashable {
    /// Metadata was read directly from embedded tags (e.g. ID3).
    case tag
    
    /// Metadata was extracted from sidecar files (e.g. yt-dlp .info.json).
    case sidecar
    
    /// Metadata was parsed from the filename or track title string.
    case parsed
    
    /// Metadata was verified and populated from an online API (e.g. iTunes, MusicBrainz).
    case online
    
    /// Metadata was manually set or edited by the user.
    case manual
}
