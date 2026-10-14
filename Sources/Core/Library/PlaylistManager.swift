import Foundation

/// Central manager for playlists: creation, modification, ordering, persistence, and notifications.
@MainActor
final class PlaylistManager {
    static let shared = PlaylistManager()
    
    private init() {}
    
    /// Loads all playlists sorted by name.
    func loadAll() async -> [Playlist] {
        let loaded = await PersistenceStore.shared.loadAll(Playlist.self)
        return loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /// Creates a new playlist with optional initial tracks.
    @discardableResult
    func createPlaylist(name: String, description: String = "", trackIDs: [Track.ID] = []) async -> Playlist {
        var playlist = Playlist(name: name, descriptionText: description)
        var order = 0
        for trackID in trackIDs {
            playlist.entries.append(PlaylistEntry(orderIndex: order, trackId: trackID))
            order += 1
        }
        var all = await PersistenceStore.shared.loadAll(Playlist.self)
        all.append(playlist)
        try? await PersistenceStore.shared.saveAll(all)
        NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        return playlist
    }
    
    /// Adds tracks to an existing playlist, avoiding duplicates.
    func addTracks(trackIDs: Set<Track.ID>, toPlaylist id: Playlist.ID) async {
        guard !trackIDs.isEmpty else { return }
        var all = await PersistenceStore.shared.loadAll(Playlist.self)
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return }
        
        var nextOrder = (all[idx].entries.map(\.orderIndex).max() ?? -1) + 1
        var changed = false
        for trackID in trackIDs {
            if !all[idx].entries.contains(where: { $0.trackId == trackID }) {
                all[idx].entries.append(PlaylistEntry(orderIndex: nextOrder, trackId: trackID))
                nextOrder += 1
                changed = true
            }
        }
        if changed {
            all[idx].modifiedAt = Date()
            try? await PersistenceStore.shared.saveAll(all)
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
    }
    
    /// Removes tracks from a playlist.
    func removeTracks(trackIDs: Set<Track.ID>, fromPlaylist id: Playlist.ID) async {
        guard !trackIDs.isEmpty else { return }
        var all = await PersistenceStore.shared.loadAll(Playlist.self)
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return }
        let initialCount = all[idx].entries.count
        all[idx].entries.removeAll { trackIDs.contains($0.trackId) }
        if all[idx].entries.count != initialCount {
            all[idx].modifiedAt = Date()
            try? await PersistenceStore.shared.saveAll(all)
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
    }
    
    /// Renames a playlist.
    func renamePlaylist(id: Playlist.ID, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var all = await PersistenceStore.shared.loadAll(Playlist.self)
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return }
        all[idx].name = trimmed
        all[idx].modifiedAt = Date()
        try? await PersistenceStore.shared.saveAll(all)
        NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
    }
    
    /// Duplicates an existing playlist.
    @discardableResult
    func duplicatePlaylist(id: Playlist.ID) async -> Playlist? {
        var all = await PersistenceStore.shared.loadAll(Playlist.self)
        guard let original = all.first(where: { $0.id == id }) else { return nil }
        var copy = Playlist(name: "\(original.name) (Copy)", descriptionText: original.descriptionText)
        copy.entries = original.entries.map {
            PlaylistEntry(orderIndex: $0.orderIndex, trackId: $0.trackId)
        }
        all.append(copy)
        try? await PersistenceStore.shared.saveAll(all)
        NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        return copy
    }
    
    /// Deletes a playlist.
    func deletePlaylist(id: Playlist.ID) async {
        try? await PersistenceStore.shared.delete(Playlist.self, id: id)
        NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
    }
    
    /// Cleans up any references to removed tracks from all playlists.
    func removeTrackReferences(trackIDs: Set<Track.ID>) async {
        var all = await PersistenceStore.shared.loadAll(Playlist.self)
        var changed = false
        for i in 0..<all.count {
            let initialCount = all[i].entries.count
            all[i].entries.removeAll { trackIDs.contains($0.trackId) }
            if all[i].entries.count != initialCount {
                all[i].modifiedAt = Date()
                changed = true
            }
        }
        if changed {
            try? await PersistenceStore.shared.saveAll(all)
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let playlistsDidChange = Notification.Name("playlistsDidChange")
}
