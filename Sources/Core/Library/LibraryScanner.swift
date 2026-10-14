import Foundation
import CryptoKit

/// Background actor responsible for recursively scanning directories,
/// parsing metadata, and persisting results to the store.
actor LibraryScanner {
    static let shared = LibraryScanner()
    
    private var isScanning = false
    
    private init() {}
    
    /// Scans a directory URL and adds found audio files to the library.
    func scan(folderURL: URL) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        
        // Verify we can access the URL
        let hasAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Find or create LibraryFolder
        var folderData: Data?
        do {
            folderData = try folderURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            print("Failed to create bookmark data for \(folderURL.path): \(error)")
        }
        
        let store = PersistenceStore.shared
        var libraryFolders = await store.loadAll(LibraryFolder.self)
        let folderId: UUID
        
        if let existing = libraryFolders.first(where: { $0.path == folderURL.path }) {
            folderId = existing.id
        } else {
            let newFolder = LibraryFolder(path: folderURL.path, bookmarkData: folderData ?? Data())
            libraryFolders.append(newFolder)
            try? await store.saveAll(libraryFolders)
            folderId = newFolder.id
        }
        
        // Enumerate files
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey]
        
        var filesToProcess: [URL] = []
        if let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            // Collect all URLs synchronously to avoid async enumeration warnings
            while let fileURL = enumerator.nextObject() as? URL {
                let ext = fileURL.pathExtension.lowercased()
                if AppConstants.Library.allFormats.contains(ext) {
                    filesToProcess.append(fileURL)
                }
            }
        }
        
        // Pre-processing step: Folder-level Pattern Detector
        var rightPartFrequencies: [String: Int] = [:]
        var leftPartFrequencies: [String: Int] = [:]
        
        for fileURL in filesToProcess {
            let name = fileURL.deletingPathExtension().lastPathComponent
            if let range = name.range(of: "\\s+[-–—:]\\s+", options: .regularExpression) {
                let left = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let right = String(name[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                
                let cleanRight = right.replacingOccurrences(of: "(?i)\\s*\\b(topic|vevo|official)\\b\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                if !cleanRight.isEmpty { rightPartFrequencies[cleanRight, default: 0] += 1 }
                
                let cleanLeft = left.replacingOccurrences(of: "(?i)\\s*\\b(topic|vevo|official)\\b\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                if !cleanLeft.isEmpty { leftPartFrequencies[cleanLeft, default: 0] += 1 }
            }
        }
        
        let patternContext = FolderPatternContext(
            channels: Set(rightPartFrequencies.filter { $0.value >= 3 }.keys),
            artists: Set(leftPartFrequencies.filter { $0.value >= 3 }.keys)
        )
        
        // Process files in parallel batches
        var parsedTracks: [Track] = []
        
        await withTaskGroup(of: Track?.self) { group in
            let maxConcurrentTasks = 4
            var index = 0
            
            while index < min(maxConcurrentTasks, filesToProcess.count) {
                let fileURL = filesToProcess[index]
                group.addTask {
                    return await self.processFile(url: fileURL, folderId: folderId, patternContext: patternContext)
                }
                index += 1
            }
            
            for await track in group {
                if let track {
                    parsedTracks.append(track)
                }
                
                if index < filesToProcess.count {
                    let fileURL = filesToProcess[index]
                    group.addTask {
                        return await self.processFile(url: fileURL, folderId: folderId, patternContext: patternContext)
                    }
                    index += 1
                }
            }
        }
        
        // Update library relationships and save
        await mergeTracksIntoLibrary(parsedTracks)
        
        // Update folder stats
        libraryFolders = await store.loadAll(LibraryFolder.self)
        if let idx = libraryFolders.firstIndex(where: { $0.id == folderId }) {
            libraryFolders[idx].lastScannedAt = Date()
            libraryFolders[idx].trackCount = parsedTracks.count
            libraryFolders[idx].trackIds = parsedTracks.map { $0.id }
            try? await store.saveAll(libraryFolders)
        }
        
        // Post notification that library changed
        NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
    }
    
    private func processFile(url: URL, folderId: UUID, patternContext: FolderPatternContext) async -> Track? {
        let fileManager = FileManager.default
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        
        let fileSize = attrs[.size] as? Int64 ?? 0
        let modDate = attrs[.modificationDate] as? Date ?? Date()
        
        // Create base track
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        
        var track = Track(
            filePath: url.path,
            fileName: fileName,
            fileExtension: ext
        )
        track.fileSize = fileSize
        track.fileModifiedAt = modDate
        track.libraryFolderId = folderId
        
        // If we can create a file-specific bookmark, do so
        if let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            track.bookmarkData = bookmarkData
        }
        
        // Extract metadata
        let metadata = await MetadataParser.parse(url: url)
        
        if !metadata.album.isEmpty { track.albumTitle = metadata.album }
        if !metadata.genre.isEmpty { track.genreName = metadata.genre }
        if !metadata.composer.isEmpty { track.composer = metadata.composer }
        if metadata.year > 0 { track.year = metadata.year }
        track.trackNumber = metadata.trackNumber
        track.trackTotal = metadata.trackTotal
        track.discNumber = metadata.discNumber
        track.discTotal = metadata.discTotal
        track.duration = metadata.duration
        track.sampleRate = metadata.sampleRate
        track.channels = metadata.channels
        
        if track.duration <= 0.05 {
            if let ffprobe = MetadataParser.findFFprobe() {
                track.duration = await probeDuration(path: url.path, ffprobe: ffprobe)
            }
        }
        track.needsProbe = (track.duration <= 0.05)
        
        // Resolve smart metadata and fetch online artwork if available (fills gaps)
        let onlineArtwork = await MetadataResolver.shared.resolve(url: url, metadata: metadata, track: &track, patternContext: patternContext)
        track.lyricsText = metadata.lyricsText
        track.hasSyncedLyrics = metadata.hasSyncedLyrics
        track.sidecarLyricsPath = metadata.sidecarLyricsPath
        
        if track.lyricsText == nil || track.lyricsText!.isEmpty {
            if let lrc = await LRCLibClient.getOrFetchLyrics(for: url, artist: track.artistName, title: track.title, album: track.albumTitle, duration: track.duration) {
                track.lyricsText = lrc.lyrics
                track.hasSyncedLyrics = lrc.isSynced
                track.sidecarLyricsPath = lrc.isSynced ? url.deletingPathExtension().appendingPathExtension("lrc").path : url.deletingPathExtension().appendingPathExtension("txt").path
            }
        }
        
        // Process artwork: resolve using ArtworkResolver
        let finalArtworkData = await ArtworkResolver.shared.resolveArtwork(
            url: url,
            metadata: metadata,
            artist: track.artistName,
            title: track.title,
            album: track.albumTitle
        )
        if let artworkData = finalArtworkData ?? onlineArtwork {
            let hash = SHA256.hash(data: artworkData).compactMap { String(format: "%02x", $0) }.joined()
            track.artworkHash = hash
            await saveArtwork(data: artworkData, hash: hash)
        }
        
        return track
    }
    
    private func probeDuration(path: String, ffprobe: String) async -> Double {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: ffprobe)
                task.arguments = ["-v", "quiet", "-print_format", "json", "-show_format", path]
                let pipe = Pipe()
                task.standardOutput = pipe
                do {
                    try task.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    task.waitUntilExit()
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let format = json["format"] as? [String: Any],
                       let dStr = format["duration"] as? String,
                       let dur = Double(dStr) {
                        continuation.resume(returning: dur)
                        return
                    }
                } catch {}
                continuation.resume(returning: 0.0)
            }
        }
    }
    
    private func saveArtwork(data: Data, hash: String) async {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let artworkDir = appSupport.appendingPathComponent("Lumo/Artwork", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: artworkDir, withIntermediateDirectories: true)
        let fileURL = artworkDir.appendingPathComponent("\(hash).jpg")
        
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? data.write(to: fileURL)
        }
    }
    
    /// Merges parsed tracks into the library, updating Albums and Artists
    private func mergeTracksIntoLibrary(_ tracks: [Track]) async {
        let store = PersistenceStore.shared
        let fm = FileManager.default
        
        var allTracks = await store.loadAll(Track.self)
        var allAlbums = await store.loadAll(Album.self)
        var allArtists = await store.loadAll(Artist.self)
        
        // Remove dead paths
        allTracks.removeAll { !fm.fileExists(atPath: $0.filePath) }
        
        for var track in tracks {
            guard fm.fileExists(atPath: track.filePath) else { continue }
            let canonical = URL(fileURLWithPath: track.filePath).resolvingSymlinksInPath().path
            track.filePath = canonical
            
            // Find or create Artist
            let artistName = track.artistName.isEmpty ? "Unknown Artist" : track.artistName
            let artistId: UUID
            if let existing = allArtists.first(where: { $0.name == artistName }) {
                artistId = existing.id
            } else {
                let newArtist = Artist(name: artistName)
                allArtists.append(newArtist)
                artistId = newArtist.id
            }
            track.artistId = artistId
            
            // Find or create Album
            let albumTitle = track.albumTitle.isEmpty ? "Unknown Album" : track.albumTitle
            let albumArtist = track.albumArtistName.isEmpty ? artistName : track.albumArtistName
            let albumId: UUID
            if let existing = allAlbums.first(where: { $0.title == albumTitle && $0.albumArtist == albumArtist }) {
                albumId = existing.id
            } else {
                var newAlbum = Album(title: albumTitle, albumArtist: albumArtist, year: track.year)
                newAlbum.artistId = artistId
                if let hash = track.artworkHash {
                    newAlbum.artworkHash = hash
                }
                allAlbums.append(newAlbum)
                albumId = newAlbum.id
            }
            track.albumId = albumId
            
            // Upsert Track by canonical path
            if let idx = allTracks.firstIndex(where: { URL(fileURLWithPath: $0.filePath).resolvingSymlinksInPath().path == canonical }) {
                // Preserve user data
                track.id = allTracks[idx].id
                track.playCount = max(allTracks[idx].playCount, track.playCount)
                track.isFavorite = allTracks[idx].isFavorite || track.isFavorite
                track.rating = max(allTracks[idx].rating, track.rating)
                if track.duration <= 0.05 && allTracks[idx].duration > 0.05 {
                    track.duration = allTracks[idx].duration
                }
                if track.artworkHash == nil && allTracks[idx].artworkHash != nil {
                    track.artworkHash = allTracks[idx].artworkHash
                }
                allTracks[idx] = track
            } else {
                allTracks.append(track)
            }
            
            // Link Track to Artist/Album
            if let aIdx = allArtists.firstIndex(where: { $0.id == artistId }) {
                if !allArtists[aIdx].trackIds.contains(track.id) {
                    allArtists[aIdx].trackIds.append(track.id)
                }
                if !allArtists[aIdx].albumIds.contains(albumId) {
                    allArtists[aIdx].albumIds.append(albumId)
                }
            }
            if let alIdx = allAlbums.firstIndex(where: { $0.id == albumId }) {
                if !allAlbums[alIdx].trackIds.contains(track.id) {
                    allAlbums[alIdx].trackIds.append(track.id)
                }
            }
        }
        
        try? await store.saveAll(allTracks)
        try? await store.saveAll(allAlbums)
        try? await store.saveAll(allArtists)
    }
    
    /// One-time migration: merges duplicates, removes dead tracks, fixes 0:00 durations, and re-resolves metadata.
    public func migrateAndDeduplicateLibrary() async {
        let store = PersistenceStore.shared
        let fm = FileManager.default
        var allTracks = await store.loadAll(Track.self)
        var allAlbums = await store.loadAll(Album.self)
        var allArtists = await store.loadAll(Artist.self)
        
        guard !allTracks.isEmpty else { return }
        
        let home = NSHomeDirectory()
        let knownRoots = [
            home + "/Documents/music",
            home + "/Music",
            FileManager.default.currentDirectoryPath
        ]
        
        // 1. Remap moved files (e.g. from old Lumo/music/ path to Documents/music/)
        for i in 0..<allTracks.count {
            let path = allTracks[i].filePath
            if !fm.fileExists(atPath: path) {
                let filename = URL(fileURLWithPath: path).lastPathComponent
                for root in knownRoots {
                    let candidate = root + "/" + filename
                    if fm.fileExists(atPath: candidate) {
                        allTracks[i].filePath = candidate
                        break
                    }
                }
            }
        }
        
        // Remove tracks whose files do not exist on disk
        allTracks = allTracks.filter { fm.fileExists(atPath: $0.filePath) }
        
        // 2. Group by canonical file path and merge duplicates
        var mergedByPath: [String: Track] = [:]
        for t in allTracks {
            let canonical = URL(fileURLWithPath: t.filePath).resolvingSymlinksInPath().path
            if let existing = mergedByPath[canonical] {
                var winner = existing
                if t.duration > winner.duration {
                    winner.duration = t.duration
                }
                if (winner.artworkHash == nil || winner.artworkHash!.isEmpty) && t.artworkHash != nil {
                    winner.artworkHash = t.artworkHash
                }
                if (winner.albumTitle.isEmpty || winner.albumTitle == "Unknown Album") && !t.albumTitle.isEmpty && t.albumTitle != "Unknown Album" {
                    winner.albumTitle = t.albumTitle
                }
                if (winner.artistName.isEmpty || winner.artistName == "Unknown Artist") && !t.artistName.isEmpty && t.artistName != "Unknown Artist" {
                    winner.artistName = t.artistName
                }
                if (winner.lyricsText == nil || winner.lyricsText!.isEmpty) && t.lyricsText != nil {
                    winner.lyricsText = t.lyricsText
                    winner.hasSyncedLyrics = t.hasSyncedLyrics
                    winner.sidecarLyricsPath = t.sidecarLyricsPath
                }
                winner.isFavorite = winner.isFavorite || t.isFavorite
                winner.playCount = max(winner.playCount, t.playCount)
                winner.rating = max(winner.rating, t.rating)
                if t.metadataConfidence > winner.metadataConfidence {
                    winner.metadataConfidence = t.metadataConfidence
                    winner.metadataSource = t.metadataSource
                }
                mergedByPath[canonical] = winner
            } else {
                mergedByPath[canonical] = t
            }
        }
        
        var finalTracks = Array(mergedByPath.values)
        
        // 3. Probe any 0:00 duration tracks with ffprobe
        if let ffprobe = MetadataParser.findFFprobe() {
            for i in 0..<finalTracks.count {
                if finalTracks[i].duration <= 0.05 {
                    let dur = await probeDuration(path: finalTracks[i].filePath, ffprobe: ffprobe)
                    if dur > 1.0 {
                        finalTracks[i].duration = dur
                        finalTracks[i].needsProbe = false
                    } else {
                        finalTracks[i].needsProbe = true
                    }
                }
            }
        }
        
        // 4. Re-resolve metadata to fix swapped title/artist and fill unknown albums
        for i in 0..<finalTracks.count {
            var t = finalTracks[i]
            let url = URL(fileURLWithPath: t.filePath)
            let metadata = await MetadataParser.parse(url: url)
            if t.duration <= 0.05 && metadata.duration > 1.0 {
                t.duration = metadata.duration
            }
            let art = await MetadataResolver.shared.resolve(url: url, metadata: metadata, track: &t)
            if t.artworkHash == nil || t.artworkHash!.isEmpty {
                var resolvedArt = art
                if resolvedArt == nil {
                    resolvedArt = await ArtworkResolver.shared.resolveArtwork(
                        url: url,
                        metadata: metadata,
                        artist: t.artistName,
                        title: t.title,
                        album: t.albumTitle
                    )
                }
                if let artData = resolvedArt {
                    let hash = SHA256.hash(data: artData).compactMap { String(format: "%02x", $0) }.joined()
                    t.artworkHash = hash
                    await saveArtwork(data: artData, hash: hash)
                }
            }
            finalTracks[i] = t
        }
        
        // 5. Rebuild Album and Artist relationships
        allAlbums.removeAll()
        allArtists.removeAll()
        
        for i in 0..<finalTracks.count {
            var track = finalTracks[i]
            let artistName = track.artistName.isEmpty ? "Unknown Artist" : track.artistName
            let artistId: UUID
            if let existing = allArtists.first(where: { $0.name == artistName }) {
                artistId = existing.id
            } else {
                let newArtist = Artist(name: artistName)
                allArtists.append(newArtist)
                artistId = newArtist.id
            }
            track.artistId = artistId
            
            let albumTitle = track.albumTitle.isEmpty ? "Unknown Album" : track.albumTitle
            let albumArtist = track.albumArtistName.isEmpty ? artistName : track.albumArtistName
            let albumId: UUID
            if let existing = allAlbums.first(where: { $0.title == albumTitle && $0.albumArtist == albumArtist }) {
                albumId = existing.id
            } else {
                var newAlbum = Album(title: albumTitle, albumArtist: albumArtist, year: track.year)
                newAlbum.artistId = artistId
                if let hash = track.artworkHash {
                    newAlbum.artworkHash = hash
                }
                allAlbums.append(newAlbum)
                albumId = newAlbum.id
            }
            track.albumId = albumId
            
            if let aIdx = allArtists.firstIndex(where: { $0.id == artistId }) {
                if !allArtists[aIdx].trackIds.contains(track.id) {
                    allArtists[aIdx].trackIds.append(track.id)
                }
                if !allArtists[aIdx].albumIds.contains(albumId) {
                    allArtists[aIdx].albumIds.append(albumId)
                }
            }
            if let alIdx = allAlbums.firstIndex(where: { $0.id == albumId }) {
                if !allAlbums[alIdx].trackIds.contains(track.id) {
                    allAlbums[alIdx].trackIds.append(track.id)
                }
            }
            finalTracks[i] = track
        }
        
        try? await store.saveAll(finalTracks)
        try? await store.saveAll(allAlbums)
        try? await store.saveAll(allArtists)
        
        NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
    }
}

extension Notification.Name {
    static let libraryDidUpdate = Notification.Name("libraryDidUpdate")
}
