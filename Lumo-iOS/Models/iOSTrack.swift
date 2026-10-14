import Foundation
import AVFoundation
import UIKit

/// Model representing a playable music track in Lumo for iOS.
public struct iOSTrack: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var fileURL: URL?
    public var artworkData: Data?
    public var lyricsText: String?
    public var hasSyncedLyrics: Bool
    
    public init(
        id: UUID = UUID(),
        title: String,
        artist: String = "Unknown Artist",
        album: String = "Unknown Album",
        duration: TimeInterval = 0,
        fileURL: URL? = nil,
        artworkData: Data? = nil,
        lyricsText: String? = nil,
        hasSyncedLyrics: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileURL = fileURL
        self.artworkData = artworkData
        self.lyricsText = lyricsText
        self.hasSyncedLyrics = hasSyncedLyrics
    }
    
    public var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    /// Parses an audio file at the given URL using AVFoundation metadata.
    public static func from(url: URL) async -> iOSTrack {
        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var artworkData: Data? = nil
        var duration: TimeInterval = 0
        
        do {
            let dur = try await asset.load(.duration)
            duration = CMTimeGetSeconds(dur)
            if duration.isNaN || duration.isInfinite { duration = 0 }
            
            let metadata = try await asset.load(.commonMetadata)
            for item in metadata {
                guard let commonKey = item.commonKey else { continue }
                switch commonKey {
                case .commonKeyTitle:
                    if let val = try? await item.load(.stringValue) { title = val }
                case .commonKeyArtist:
                    if let val = try? await item.load(.stringValue) { artist = val }
                case .commonKeyAlbumName:
                    if let val = try? await item.load(.stringValue) { album = val }
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue) { artworkData = data }
                default:
                    break
                }
            }
        } catch {
            print("Failed to load metadata for \(url): \(error)")
        }
        
        return iOSTrack(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            fileURL: url,
            artworkData: artworkData
        )
    }
}
