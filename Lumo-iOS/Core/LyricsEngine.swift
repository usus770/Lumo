import Foundation

public struct iOSLyricsLine: Identifiable, Equatable {
    public let id = UUID()
    public let time: TimeInterval
    public let text: String
    public let romanizedText: String?
}

/// Parses and synchronizes LRC lyrics for Lumo iOS.
public final class iOSLyricsEngine {
    public static func parse(lrcContent: String) -> [iOSLyricsLine] {
        var lines: [iOSLyricsLine] = []
        let rawLines = lrcContent.components(separatedBy: .newlines)
        let timeRegex = try? NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{2})\\.(\\d{2,3})\\]", options: [])
        
        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            guard let regex = timeRegex,
                  let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)) else {
                continue
            }
            
            let minStr = (trimmed as NSString).substring(with: match.range(at: 1))
            let secStr = (trimmed as NSString).substring(with: match.range(at: 2))
            let msStr = (trimmed as NSString).substring(with: match.range(at: 3))
            
            let minutes = Double(minStr) ?? 0
            let seconds = Double(secStr) ?? 0
            let millis = Double(msStr) ?? 0
            let divisor = msStr.count == 3 ? 1000.0 : 100.0
            let time = (minutes * 60.0) + seconds + (millis / divisor)
            
            let textStartIndex = trimmed.index(trimmed.startIndex, offsetBy: match.range.length)
            let lyricText = String(trimmed[textStartIndex...]).trimmingCharacters(in: .whitespaces)
            
            let romanized = romanizeIfNeeded(text: lyricText)
            lines.append(iOSLyricsLine(time: time, text: lyricText, romanizedText: romanized))
        }
        
        return lines.sorted { $0.time < $1.time }
    }
    
    /// Romanizes Devanagari or non-Latin scripts to Latin using CFStringTransform.
    private static func romanizeIfNeeded(text: String) -> String? {
        let hasNonLatin = text.unicodeScalars.contains { $0.value > 0x024F }
        guard hasNonLatin else { return nil }
        
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        let result = String(mutable).trimmingCharacters(in: .whitespaces)
        return result.isEmpty || result == text ? nil : result
    }
}
