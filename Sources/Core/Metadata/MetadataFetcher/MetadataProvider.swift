import Foundation

/// Common protocol for online metadata and media providers.
public protocol MetadataProvider: Sendable {
    var name: String { get }
    
    /// Searches for matching tracks given a query string.
    func search(query: String) async throws -> [MetadataSearchResult]
    
    /// Fetches exact track details given a YouTube video ID.
    func lookupVideoId(_ videoId: String) async throws -> MetadataSearchResult?
    
    /// Downloads cover art for a search result or candidate URL.
    func fetchCoverArt(for result: MetadataSearchResult) async throws -> CoverArtCandidate?
    
    /// Fetches lyrics (synced or plain) for a search result.
    func fetchLyrics(for result: MetadataSearchResult, duration: TimeInterval?) async throws -> LyricsResultCandidate?
}
