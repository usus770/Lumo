import Foundation

/// Resolves missing or inaccurate metadata using a pipeline of hints, sidecars, and parsing.
actor MetadataResolver {
    static let shared = MetadataResolver()
    
    private init() {}
    
    /// Resolves the best artist and title for a track, updating the Track object and its confidence.
    func resolve(url: URL, metadata: MetadataParser.ParsedMetadata, track: inout Track, patternContext: FolderPatternContext? = nil) async -> Data? {
        
        // Step 1: Check yt-dlp sidecar data (.info.json)
        let sidecar = SidecarParser.ingest(baseNameURL: url)
        if let info = sidecar.info {
            // Fill gaps from .info.json
            if track.albumTitle.isEmpty, let alb = info.album, !alb.isEmpty {
                track.albumTitle = alb
            }
            if track.year == 0 {
                if let y = info.release_year {
                    track.year = y
                } else if let ud = info.upload_date, let y = Int(ud.prefix(4)) {
                    track.year = y
                }
            }
            
            // Case 1A: Explicit track and artist/creator in .info.json
            let directTrack = info.track
            let directArtist = info.artist ?? info.creator
            
            if let t = directTrack, let a = directArtist, !t.isEmpty, !a.isEmpty {
                let cleanT = TitleCleaner.clean(t).cleanedString
                let cleanA = TitleCleaner.clean(a).cleanedString
                if !cleanT.isEmpty && !cleanA.isEmpty {
                    track.title = cleanT
                    track.artistName = cleanA
                    track.metadataSource = .sidecar
                    track.metadataConfidence = 1.0
                    return await fillGapsOnline(track: &track)
                }
            }
            
            // Case 1B: Standard yt-dlp upload with video title, uploader/channel, or alt_title
            let videoTitle = info.title ?? info.alt_title
            let uploader = info.uploader ?? info.channel
            if let vTitle = videoTitle, !vTitle.isEmpty {
                let cleaned = TitleCleaner.clean(vTitle)
                let candidates = TitleParser.parse(cleanedString: cleaned.cleanedString, uploader: uploader, patternContext: patternContext)
                if let best = candidates.first, best.confidence >= 0.85 {
                    track.title = best.title
                    track.artistName = best.artist
                    if let alb = best.album, track.albumTitle.isEmpty {
                        track.albumTitle = alb
                    }
                    if !best.featuredArtists.isEmpty {
                        track.artistName = best.artist + " (feat. " + best.featuredArtists.joined(separator: ", ") + ")"
                    }
                    track.metadataSource = .sidecar
                    track.metadataConfidence = best.confidence
                    return await fillGapsOnline(track: &track)
                }
            }
        }
        
        // Step 2: Check embedded tags
        let tagArtist = metadata.artist.trimmingCharacters(in: .whitespaces)
        let tagTitle = metadata.title.trimmingCharacters(in: .whitespaces)
        let tagAlbum = metadata.album.trimmingCharacters(in: .whitespaces)
        
        // Junk tag validation: reject embedded tags that are empty, "Unknown", numeric-only ("1234"), equal to the title, equal to the album, or contain noise words
        var hasValidTags = false
        if !tagTitle.isEmpty && !tagArtist.isEmpty {
            let lowerArtist = tagArtist.lowercased()
            let lowerTitle = tagTitle.lowercased()
            let isNumeric = Int(tagArtist) != nil
            
            let noiseWords = ["official", "video", "audio", "lyric", "topic", "vevo", "records", "music", "unknown", "http", ".com", "www."]
            let hasNoise = noiseWords.contains { lowerArtist.contains($0) } || noiseWords.contains { lowerTitle.contains($0) }
            
            if lowerArtist != "unknown" && !isNumeric && !hasNoise &&
               lowerArtist != lowerTitle && lowerArtist != tagAlbum.lowercased() &&
               !TitleCleaner.clean(tagTitle).cleanedString.isEmpty {
                if !lowerTitle.contains("official video") && !lowerTitle.contains("lyric video") && !lowerTitle.contains("official audio") {
                    hasValidTags = true
                }
            }
        }
        
        if hasValidTags {
            track.title = TitleCleaner.clean(tagTitle).cleanedString
            track.artistName = TitleCleaner.clean(tagArtist).cleanedString
            if !tagAlbum.isEmpty && track.albumTitle.isEmpty {
                track.albumTitle = tagAlbum
            }
            if metadata.year > 0 && track.year == 0 {
                track.year = metadata.year
            }
            if !metadata.genre.isEmpty && track.genreName.isEmpty {
                track.genreName = metadata.genre
            }
            track.metadataSource = .tag
            track.metadataConfidence = 1.0
            return await fillGapsOnline(track: &track)
        }
        
        // Step 3: Parse from filename
        let rawStringToParse = url.deletingPathExtension().lastPathComponent
        let cleanedResult = TitleCleaner.clean(rawStringToParse)
        let candidates = TitleParser.parse(cleanedString: cleanedResult.cleanedString, uploader: nil, patternContext: patternContext)
        
        if let best = candidates.first {
            track.title = best.title
            track.artistName = best.artist
            if let alb = best.album, track.albumTitle.isEmpty {
                track.albumTitle = alb
            }
            if !best.featuredArtists.isEmpty {
                track.artistName = best.artist + " (feat. " + best.featuredArtists.joined(separator: ", ") + ")"
            }
            track.metadataSource = .parsed
            track.metadataConfidence = best.confidence
        } else {
            track.title = cleanedResult.cleanedString
            track.artistName = "Unknown"
            track.metadataSource = .parsed
            track.metadataConfidence = 0.1
        }
        
        track.title = stripArtistPrefix(title: track.title, artist: track.artistName)
        
        // Step 4: Online verification with Swap Detector
        var onlineArt: Data? = nil
        async let forwardCheck = OnlineVerifier.shared.verify(artist: track.artistName, title: track.title)
        async let swappedCheck = OnlineVerifier.shared.verify(artist: track.title, title: track.artistName)
        
        let verifiedRes = await forwardCheck
        let swappedRes = await swappedCheck
        
        if let swapped = swappedRes, (verifiedRes == nil || swapped.score > (verifiedRes?.score ?? 0.0) || swapped.matchCount > (verifiedRes?.matchCount ?? 0) || track.artistName.lowercased() == "unknown") {
            // Swap detector won: (title, artist) matched online better than (artist, title)
            track.title = swapped.title
            track.artistName = swapped.artist
            track.metadataSource = .online
            track.metadataConfidence = swapped.score
            if let alb = swapped.album { track.albumTitle = alb }
            if let yr = swapped.year { track.year = yr }
            if let g = swapped.genre { track.genreName = g }
            if let artworkUrl = swapped.artworkUrl,
               let data = try? await URLSession.shared.data(from: artworkUrl).0 {
                onlineArt = data
            }
        } else if let verified = verifiedRes {
            if track.albumTitle.isEmpty || track.albumTitle == "Unknown Album", let alb = verified.album { track.albumTitle = alb }
            if track.year == 0, let yr = verified.year { track.year = yr }
            if track.genreName.isEmpty, let g = verified.genre { track.genreName = g }
            
            if track.metadataConfidence < 0.85 || track.artistName.lowercased() == "unknown" {
                track.title = verified.title
                track.artistName = verified.artist
                track.metadataSource = .online
                track.metadataConfidence = verified.score
            }
            if let artworkUrl = verified.artworkUrl,
               let data = try? await URLSession.shared.data(from: artworkUrl).0 {
                onlineArt = data
            }
        }
        
        track.title = stripArtistPrefix(title: track.title, artist: track.artistName)
        if track.title.lowercased() == track.artistName.lowercased() {
            track.metadataConfidence = 0.3
        }
        
        NSLog("[MetadataResolver] Track '%@': raw -> chosen Title: '%@', Artist: '%@', Album: '%@', Source: %@, Conf: %.2f",
              url.lastPathComponent, track.title, track.artistName, track.albumTitle, track.metadataSource.rawValue, track.metadataConfidence)
        
        return onlineArt
    }
    
    public func stripArtistPrefix(title: String, artist: String) -> String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty && a.lowercased() != "unknown" else { return t }
        
        let escaped = NSRegularExpression.escapedPattern(for: a)
        t = t.replacingOccurrences(of: "(?i)^" + escaped + "\\s*[-–—:]\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: "(?i)\\s*[-–—:]\\s*" + escaped + "$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return t
    }
    
    private func fillGapsOnline(track: inout Track) async -> Data? {
        track.title = stripArtistPrefix(title: track.title, artist: track.artistName)
        if let verified = await OnlineVerifier.shared.verify(artist: track.artistName, title: track.title) {
            if track.albumTitle.isEmpty || track.albumTitle == "Unknown Album", let alb = verified.album { track.albumTitle = alb }
            if track.year == 0, let yr = verified.year { track.year = yr }
            if track.genreName.isEmpty, let g = verified.genre { track.genreName = g }
            
            if let artworkUrl = verified.artworkUrl,
               let data = try? await URLSession.shared.data(from: artworkUrl).0 {
                return data
            }
        } else if let swapped = await OnlineVerifier.shared.verify(artist: track.title, title: track.artistName) {
            track.title = swapped.title
            track.artistName = swapped.artist
            track.metadataSource = .online
            track.metadataConfidence = swapped.score
            if let alb = swapped.album { track.albumTitle = alb }
            if let yr = swapped.year { track.year = yr }
            if let g = swapped.genre { track.genreName = g }
            if let artworkUrl = swapped.artworkUrl,
               let data = try? await URLSession.shared.data(from: artworkUrl).0 {
                return data
            }
        }
        return nil
    }
}
