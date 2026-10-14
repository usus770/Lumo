import Foundation

public struct CleanedTitleResult: Sendable, Equatable {
    public var cleanedString: String
    public var isLive: Bool
    public var isAltered: Bool // slowed, sped up, nightcore, reverb, bass boosted, cover, remix
}

public enum TitleCleaner {
    
    // Noise patterns to strip when inside brackets or when a standalone segment after a separator
    private static let bracketNoisePatterns: [String] = [
        "official music video", "official lyric video", "official video", "official audio",
        "official visualizer", "official", "lyric video", "lyrics", "with lyrics",
        "music video", "video", "audio", "full video", "full song", "full audio",
        "m/v", "mv", "hd", "hq", "4k", "8k", "remastered", "visualizer",
        "explicit", "clean", "1 hour loop", "topic", "vevo", "audio track"
    ]
    
    private static let alteredPatterns: [String] = [
        "slowed", "reverb", "sped up", "nightcore", "bass boosted", "remix", "cover", "mashup"
    ]
    
    /// Normalizes Unicode using NFKC
    public static func normalizeUnicode(_ string: String) -> String {
        return string.precomposedStringWithCompatibilityMapping
    }
    
    /// Cleans a track title or filename from common YouTube noise
    public static func clean(_ raw: String) -> CleanedTitleResult {
        var str = normalizeUnicode(raw)
        var isLive = false
        var isAltered = false
        
        // Remove file extension if present (for filenames)
        if let extRange = str.range(of: "\\.[a-zA-Z0-9]{2,5}$", options: .regularExpression) {
            str.removeSubrange(extRange)
        }
        
        // Remove yt-dlp video ID: ONLY matches [<11 chars>] or -<11 chars> suffix pattern
        // yt-dlp format: [aBcDeF12345] or -aBcDeF12345 at the very end
        let bracketIDPattern = "\\[([A-Za-z0-9_\\-]{11})\\]\\s*$"
        if let range = str.range(of: bracketIDPattern, options: .regularExpression) {
            str.removeSubrange(range)
        } else {
            // Suffix pattern: hyphen immediately followed by 11-char ID (must contain at least one digit or underscore to avoid real words like 'Mockingbird')
            let hyphenIDPattern = "-([A-Za-z0-9_\\-]{11})\\s*$"
            if let range = str.range(of: hyphenIDPattern, options: .regularExpression) {
                let candidateID = String(str[range]).trimmingCharacters(in: CharacterSet(charactersIn: "- \t"))
                let hasDigitOrSymbol = candidateID.contains(where: { $0.isNumber || $0 == "_" || $0 == "-" })
                if hasDigitOrSymbol && candidateID.count == 11 {
                    str.removeSubrange(range)
                }
            }
        }
        
        // Find things inside brackets: (), [], {}, 【】, 「」, 『』
        let bracketRegex = try! NSRegularExpression(pattern: "[\\(\\[\\{\\【\\「\\『](.*?)[\\)\\]\\}\\】\\」\\』]", options: [])
        let matches = bracketRegex.matches(in: str, range: NSRange(str.startIndex..., in: str))
        
        // Process in reverse order to safely delete
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: str),
                  let innerRange = Range(match.range(at: 1), in: str) else { continue }
            
            let innerText = String(str[innerRange]).lowercased().trimmingCharacters(in: .whitespaces)
            
            // Check flags
            if innerText.contains("live") { isLive = true }
            if alteredPatterns.contains(where: { innerText.contains($0) }) { isAltered = true }
            
            var shouldDelete = false
            
            // Delete if the bracket contents match or are predominantly noise
            if bracketNoisePatterns.contains(innerText) || innerText == "live" || alteredPatterns.contains(innerText) {
                shouldDelete = true
            } else if innerText.hasPrefix("prod. by") || innerText.hasPrefix("prod ") || innerText.hasPrefix("produced by") {
                shouldDelete = true
            } else if isAltered && innerText.contains("+") {
                shouldDelete = true
            } else {
                for noise in bracketNoisePatterns {
                    if innerText == noise || innerText.contains(noise) {
                        shouldDelete = true
                        break
                    }
                }
            }
            
            if shouldDelete {
                str.removeSubrange(matchRange)
            }
        }
        
        // Strip noise segments ONLY if they appear after or between separators (e.g. "| Official Video" or "- Audio")
        // Never strip from the middle of normal text (e.g. "Live Forever", "Stay with me", "Video Games")
        let sepPattern = "(?i)\\s*([|•·/]|\\s-\\s|\\s–\\s|\\s—\\s)\\s*(official\\s+video|official\\s+audio|official\\s+music\\s+video|official|music\\s+video|lyric\\s+video|audio|video|hd|4k|visualizer|remastered)\\s*$"
        while let range = str.range(of: sepPattern, options: .regularExpression) {
            str.removeSubrange(range)
        }
        
        // Clean up repeated spaces, hyphens, and underscores
        str = str.replacingOccurrences(of: "_", with: " ")
        let spacesRegex = try! NSRegularExpression(pattern: "\\s{2,}", options: [])
        str = spacesRegex.stringByReplacingMatches(in: str, range: NSRange(str.startIndex..., in: str), withTemplate: " ")
        
        // Clean up trailing/leading hyphens or separators
        str = str.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—:|/•·")))
        
        return CleanedTitleResult(cleanedString: str, isLive: isLive, isAltered: isAltered)
    }
}
