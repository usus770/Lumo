import Foundation

public actor LyricsBatchFetcher {
    public static let shared = LyricsBatchFetcher()
    private init() {}
    
    private var isFetching = false
    
    /// Scans the library for tracks missing synced lyrics and fetches them in the background.
    public func startBackgroundFetch() {
        guard !isFetching else { return }
        isFetching = true
        
        Task.detached(priority: .background) {
            let allTracks = await PersistenceStore.shared.loadAll(Track.self)
            var updatedTracks = allTracks
            var madeChanges = false
            
            for (index, track) in allTracks.enumerated() {
                // If it doesn't have synced lyrics, try fetching from LRCLIB
                if !track.hasSyncedLyrics {
                    let url = URL(fileURLWithPath: track.filePath)
                    if let lrc = await LRCLibClient.getOrFetchLyrics(for: url, artist: track.artistName, title: track.title, album: track.albumTitle, duration: track.duration) {
                        if lrc.isSynced {
                            updatedTracks[index].lyricsText = lrc.lyrics
                            updatedTracks[index].hasSyncedLyrics = true
                            updatedTracks[index].sidecarLyricsPath = url.deletingPathExtension().appendingPathExtension("lrc").path
                            madeChanges = true
                        }
                    }
                }
                
                // Sleep slightly to avoid spamming the LRCLIB API and blocking CPU
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            if madeChanges {
                try? await PersistenceStore.shared.saveAll(updatedTracks)
                await MainActor.run {
                    NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
                }
            }
            
            await self.setFetching(false)
        }
    }
    
    private func setFetching(_ value: Bool) {
        isFetching = value
    }
}
