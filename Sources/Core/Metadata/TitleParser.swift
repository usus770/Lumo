import Foundation

public struct ParsedTitleCandidate: Sendable, Equatable {
    public var artist: String
    public var title: String
    public var featuredArtists: [String]
    public var confidence: Double
    public var album: String?
    
    public init(artist: String, title: String, featuredArtists: [String] = [], confidence: Double, album: String? = nil) {
        self.artist = artist
        self.title = title
        self.featuredArtists = featuredArtists
        self.confidence = confidence
        self.album = album
    }
}

public struct FolderPatternContext: Sendable {
    public var channels: Set<String>
    public var artists: Set<String>
    
    public init(channels: Set<String> = [], artists: Set<String> = []) {
        self.channels = channels
        self.artists = artists
    }
}

public enum TitleParser {
    
    private static let knownLabels: Set<String> = [
        "t-series", "tseries", "t-series apna punjab", "t-series regional", "t-series bhakti sagar",
        "zee music company", "zee music", "zeemusic", "zeemusiccompany",
        "sony music india", "sony music", "sonymusic", "sonymusicindiavevo",
        "saregama", "saregama music", "saregamahindi", "saregama punjabi",
        "tips", "tips official", "tips punjabi", "tips music", "tipsofficial",
        "speed records", "times music", "yrf", "yash raj films",
        "white hill music", "geet mp3", "geetmp3", "venus", "eros now",
        "aditya music", "lahari music", "think music", "svf music", "svf",
        "desi music factory", "dm - desi music factory", "jjust music"
    ]
    
    /// Parses a cleaned string and an optional uploader/channel name into ranked candidates.
    public static func parse(cleanedString: String, uploader: String? = nil, patternContext: FolderPatternContext? = nil) -> [ParsedTitleCandidate] {
        var candidates: [ParsedTitleCandidate] = []
        
        // Ensure we work with NFKC
        let str = TitleCleaner.normalizeUnicode(cleanedString)
        let channel = uploader.map { cleanUploader($0) }
        
        let (baseString, featured) = extractFeaturedArtists(from: str)
        
        // 1. Quoted: Artist "Title" or Artist 'Title'
        if let quoted = parseQuoted(baseString) {
            candidates.append(ParsedTitleCandidate(artist: quoted.artist, title: quoted.title, featuredArtists: featured, confidence: 0.95))
        }
        
        // 2. Artist「Title」or Artist『Title』
        if let asian = parseAsianBrackets(baseString) {
            candidates.append(ParsedTitleCandidate(artist: asian.artist, title: asian.title, featuredArtists: featured, confidence: 0.95))
        }
        
        // 3. Multi-segment split on all |, •, · (Indian style Song | Movie | Singer | Label, or Title | Artist)
        if let multiSegments = parseMultiSegment(string: baseString, featured: featured) {
            candidates.append(contentsOf: multiSegments)
        }
        
        // 4. Title by Artist
        if let byMatch = parseBy(baseString) {
            candidates.append(ParsedTitleCandidate(artist: byMatch.artist, title: byMatch.title, featuredArtists: featured, confidence: 0.90))
        }
        
        // 5. Standard separators: Artist - Title, Artist – Title, Artist — Title, Artist : Title
        // 5. Standard separators: Artist - Title, Title - Artist, or Artist - Title - Artist
        if let split = parseStandardSeparator(baseString) {
            var leftIsArtist = false
            var isConfirmed = false
            
            if split.isRepeatedArtist {
                leftIsArtist = true
                isConfirmed = true
            } else if let ch = channel, !ch.isEmpty {
                let cleanL = split.left.lowercased()
                let cleanR = split.right.lowercased()
                let cleanCh = ch.lowercased()
                if cleanCh == cleanL || cleanL.contains(cleanCh) {
                    leftIsArtist = true
                    isConfirmed = true
                } else if cleanCh == cleanR || cleanR.contains(cleanCh) {
                    leftIsArtist = false
                    isConfirmed = true
                }
            }
            
            if !isConfirmed, let ctx = patternContext {
                let cleanRight = split.right.replacingOccurrences(of: "(?i)\\s*\\b(topic|vevo|official)\\b\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                let cleanLeft = split.left.replacingOccurrences(of: "(?i)\\s*\\b(topic|vevo|official)\\b\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                
                if ctx.channels.contains(cleanRight) || ctx.artists.contains(cleanRight) {
                    leftIsArtist = false
                    isConfirmed = true
                } else if ctx.channels.contains(cleanLeft) || ctx.artists.contains(cleanLeft) {
                    leftIsArtist = true
                    isConfirmed = true
                }
            }
            
            if isConfirmed {
                if leftIsArtist {
                    candidates.append(ParsedTitleCandidate(artist: split.left, title: split.right, featuredArtists: featured, confidence: 0.98))
                } else {
                    candidates.append(ParsedTitleCandidate(artist: split.right, title: split.left, featuredArtists: featured, confidence: 0.98))
                }
            } else {
                // Unconfirmed filename: left might be artist or title
                candidates.append(ParsedTitleCandidate(artist: split.left, title: split.right, featuredArtists: featured, confidence: 0.70))
                candidates.append(ParsedTitleCandidate(artist: split.right, title: split.left, featuredArtists: featured, confidence: 0.68))
            }
        }
        
        // 6. No separators, just a string. Use uploader.
        if candidates.isEmpty {
            if let c = channel, !c.isEmpty {
                // Topic channels are high confidence
                let conf = (uploader?.lowercased().contains("topic") == true) ? 0.95 : 0.6
                candidates.append(ParsedTitleCandidate(artist: c, title: baseString, featuredArtists: featured, confidence: conf))
            } else {
                // Absolute fallback, assume it's just the title
                candidates.append(ParsedTitleCandidate(artist: "Unknown", title: baseString, featuredArtists: featured, confidence: 0.1))
            }
        }
        
        return candidates.sorted { $0.confidence > $1.confidence }
    }
    
    private static func cleanUploader(_ uploader: String) -> String {
        var str = uploader
        let noise = [" - topic", "topic", "vevo", "official", "records"]
        for n in noise {
            if let range = str.range(of: "(?i)\\s*\\b\(n)\\b\\s*", options: .regularExpression) {
                str.removeSubrange(range)
            }
        }
        // If the channel was literally "Artist - Topic", the "-" might be left over
        str = str.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—:|")))
        return str
    }
    
    private static func extractFeaturedArtists(from string: String) -> (base: String, featured: [String]) {
        var str = string
        var featured: [String] = []
        
        // Match feat., ft., featuring, x ONLY inside brackets: (...), [...], {...}, 【...】
        let featPattern = "(?i)[\\(\\[\\{\\【]\\s*(?:feat\\.?|ft\\.?|featuring|x)\\s+([^\\)\\]\\}\\】]+?)\\s*[\\)\\]\\}\\】]"
        let regex = try! NSRegularExpression(pattern: featPattern, options: [])
        
        while let match = regex.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) {
            if let r = Range(match.range(at: 1), in: str) {
                let f = String(str[r]).trimmingCharacters(in: .whitespaces)
                featured.append(contentsOf: splitMultipleArtists(f))
            }
            if let fullRange = Range(match.range, in: str) {
                str.removeSubrange(fullRange)
            }
        }
        
        return (str.trimmingCharacters(in: .whitespaces), featured)
    }
    
    private static func splitMultipleArtists(_ string: String) -> [String] {
        let parts = string.components(separatedBy: CharacterSet(charactersIn: ",&"))
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    
    public static func isKnownLabel(_ segment: String) -> Bool {
        let lower = segment.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if knownLabels.contains(lower) { return true }
        let stripped = lower.filter { $0.isLetter || $0.isNumber }
        if knownLabels.contains(where: { $0.filter { $0.isLetter || $0.isNumber } == stripped }) {
            return true
        }
        if lower.contains("music company") || lower.contains("records") || lower.contains("t-series") || lower.contains("zee music") || lower.contains("sony music") {
            return true
        }
        return false
    }
    
    private static func isNoiseSegment(_ segment: String) -> Bool {
        let lower = segment.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let noise = ["official video", "official audio", "official music video", "full video", "full song", "full audio", "video", "audio", "lyric video", "hd", "4k", "teaser", "trailer", "visualizer", "remastered"]
        return noise.contains(lower)
    }
    
    private static func parseMultiSegment(string: String, featured: [String]) -> [ParsedTitleCandidate]? {
        let rawSegments = string.components(separatedBy: CharacterSet(charactersIn: "|•·"))
        guard rawSegments.count > 1 else { return nil }
        
        var validSegments: [String] = []
        for raw in rawSegments {
            let cleaned = TitleCleaner.clean(raw).cleanedString.trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty && !isKnownLabel(cleaned) && !isNoiseSegment(cleaned) {
                validSegments.append(cleaned)
            }
        }
        
        guard validSegments.count >= 2 else { return nil }
        
        var candidates: [ParsedTitleCandidate] = []
        let seg0 = validSegments[0]
        
        if validSegments.count >= 3 {
            // Indian pattern: Song | Movie/Album | Singer(s)
            let seg1 = validSegments[1] // Movie / Album
            let seg2 = validSegments[2] // Singer(s)
            candidates.append(ParsedTitleCandidate(artist: seg2, title: seg0, featuredArtists: featured, confidence: 0.95, album: seg1))
            
            if validSegments.count >= 4 {
                let seg3 = validSegments[3] // Additional collaborator/singer
                candidates.append(ParsedTitleCandidate(artist: "\(seg2), \(seg3)", title: seg0, featuredArtists: featured, confidence: 0.93, album: seg1))
            }
            // Fallback: in case seg1 was artist and seg2 was album
            candidates.append(ParsedTitleCandidate(artist: seg1, title: seg0, featuredArtists: featured, confidence: 0.70, album: seg2))
        } else if validSegments.count == 2 {
            let seg1 = validSegments[1]
            // Usually Title | Artist
            candidates.append(ParsedTitleCandidate(artist: seg1, title: seg0, featuredArtists: featured, confidence: 0.85))
            // Sometimes Artist | Title
            candidates.append(ParsedTitleCandidate(artist: seg0, title: seg1, featuredArtists: featured, confidence: 0.45))
        }
        
        return candidates.isEmpty ? nil : candidates
    }
    
    private static func parseStandardSeparator(_ string: String) -> (left: String, right: String, isRepeatedArtist: Bool)? {
        let pattern = "\\s+[-–—:]\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = string as NSString
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
        
        if matches.count >= 2 {
            var parts: [String] = []
            var lastEnd = 0
            for match in matches {
                let part = nsString.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd)).trimmingCharacters(in: .whitespaces)
                if !part.isEmpty { parts.append(part) }
                lastEnd = match.range.location + match.range.length
            }
            let tail = nsString.substring(from: lastEnd).trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { parts.append(tail) }
            
            if parts.count >= 3 {
                let first = parts[0]
                let last = parts[parts.count - 1]
                if first.lowercased() == last.lowercased() ||
                   OnlineVerifier.tokenSetSimilarity(first, last) >= 0.85 {
                    // Pattern: Artist - Title - Artist
                    let mid = parts[1..<(parts.count - 1)].joined(separator: " - ")
                    return (left: first, right: mid, isRepeatedArtist: true)
                }
            }
        }
        
        if let range = string.range(of: pattern, options: .regularExpression) {
            let left = String(string[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(string[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (left: left, right: right, isRepeatedArtist: false)
        }
        if let range = string.range(of: "[–—:]", options: .regularExpression) {
            let left = String(string[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(string[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (left: left, right: right, isRepeatedArtist: false)
        }
        return nil
    }
    
    private static func parseQuoted(_ string: String) -> (artist: String, title: String)? {
        let pattern = "^(.*?)\\s*[\"'](.*?)[\"']\\s*$"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        if let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
           let artistRange = Range(match.range(at: 1), in: string),
           let titleRange = Range(match.range(at: 2), in: string) {
            let charSet = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—:|"))
            let a = String(string[artistRange]).trimmingCharacters(in: charSet)
            let t = String(string[titleRange]).trimmingCharacters(in: charSet)
            if !a.isEmpty && !t.isEmpty {
                return (a, t)
            }
        }
        return nil
    }
    
    private static func parseAsianBrackets(_ string: String) -> (artist: String, title: String)? {
        let pattern = "^(.*?)\\s*[「『](.*?)[」』]\\s*$"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        if let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
           let artistRange = Range(match.range(at: 1), in: string),
           let titleRange = Range(match.range(at: 2), in: string) {
            let a = String(string[artistRange]).trimmingCharacters(in: .whitespaces)
            let t = String(string[titleRange]).trimmingCharacters(in: .whitespaces)
            if !a.isEmpty && !t.isEmpty {
                return (a, t)
            }
        }
        return nil
    }
    
    private static func parseBy(_ string: String) -> (title: String, artist: String)? {
        let pattern = "^(.*?)\\s+by\\s+(.*?)$"
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        if let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
           let titleRange = Range(match.range(at: 1), in: string),
           let artistRange = Range(match.range(at: 2), in: string) {
            let t = String(string[titleRange]).trimmingCharacters(in: .whitespaces)
            let a = String(string[artistRange]).trimmingCharacters(in: .whitespaces)
            if !a.isEmpty && !t.isEmpty {
                return (t, a)
            }
        }
        return nil
    }
}
