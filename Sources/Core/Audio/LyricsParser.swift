import Foundation

public struct LyricWord: Identifiable, Equatable, Sendable, Codable {
    public var id: String
    public var text: String
    public let start: TimeInterval
    public let end: TimeInterval
    
    public init(id: String? = nil, text: String, start: TimeInterval, end: TimeInterval) {
        self.id = id ?? "\(Int((start * 1000).rounded()))_\(abs(text.hashValue))"
        self.text = text
        self.start = start
        self.end = end
    }
}

public struct LyricLine: Identifiable, Equatable, Sendable, Codable {
    public var id: String
    public let time: TimeInterval
    public var text: String
    public var words: [LyricWord]
    
    public init(id: String? = nil, time: TimeInterval, text: String, words: [LyricWord] = []) {
        self.id = id ?? "\(Int((time * 1000).rounded()))_\(abs(text.hashValue))"
        self.time = time
        self.text = text
        self.words = words
    }
}

public struct ParsedLyrics: Equatable, Sendable {
    public let lines: [LyricLine]
    public let isSynced: Bool
    
    public init(lines: [LyricLine], isSynced: Bool) {
        self.lines = lines
        self.isSynced = isSynced
    }
    
    public func lineIndex(at time: TimeInterval) -> Int {
        return LyricsParser.lineIndex(in: lines, at: time)
    }
}

/// Parses LRC formatted strings into an array of `LyricLine`.
public enum LyricsParser {
    
    /// Binary search to find the active line index at a given playback time.
    /// Returns -1 if time is before the first line or lines is empty.
    public static func lineIndex(in lines: [LyricLine], at time: TimeInterval) -> Int {
        guard !lines.isEmpty else { return -1 }
        if time < lines[0].time { return -1 }
        
        var low = 0
        var high = lines.count - 1
        var bestIndex = 0
        
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= time {
                bestIndex = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return bestIndex
    }
    
    /// Parses a raw LRC string into a structured format.
    /// Supports:
    /// - [offset:±ms] header tags
    /// - Multiple [mm:ss.xx] line timestamps per line
    /// - Enhanced <mm:ss.xx> word-level timestamps
    /// - Character/syllable-weighted word timing estimation when word tags are absent
    public static func parse(_ rawText: String, duration: TimeInterval? = nil) -> ParsedLyrics {
        var rawLines: [(time: TimeInterval, rawContent: String)] = []
        var isSynced = false
        var lrcOffset: TimeInterval = 0.0
        
        let stringLines = rawText.components(separatedBy: .newlines)
        
        // LRC Tag regex: [mm:ss.xx] or [mm:ss.xxx]
        let timeTagRegex = try! NSRegularExpression(pattern: "\\[(\\d{2,}):(\\d{2})(?:\\.(\\d{2,3}))?\\]", options: [])
        let offsetTagRegex = try! NSRegularExpression(pattern: "\\[offset:\\s*([+-]?\\d+)\\]", options: [.caseInsensitive])
        let wordTagRegex = try! NSRegularExpression(pattern: "<(\\d{2,}):(\\d{2})(?:\\.(\\d{2,3}))?>([^<]*)", options: [])
        
        for line in stringLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Parse [offset:±ms]
            let nsLine = trimmed as NSString
            if let offsetMatch = offsetTagRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsLine.length)),
               let range = Range(offsetMatch.range(at: 1), in: trimmed) {
                if let ms = Double(trimmed[range]) {
                    lrcOffset = ms / 1000.0
                }
                continue
            }
            
            // Ignore other metadata headers like [ar:Artist], [ti:Title]
            if trimmed.hasPrefix("[") && trimmed.contains(":") && !trimmed.contains(where: { $0.isNumber }) {
                continue
            }
            
            let matches = timeTagRegex.matches(in: trimmed, range: NSRange(location: 0, length: nsLine.length))
            
            if !matches.isEmpty {
                isSynced = true
                var lastTagEnd = 0
                var times: [TimeInterval] = []
                
                for match in matches {
                    let minStr = nsLine.substring(with: match.range(at: 1))
                    let secStr = nsLine.substring(with: match.range(at: 2))
                    
                    var msStr = "0"
                    if match.range(at: 3).location != NSNotFound {
                        msStr = nsLine.substring(with: match.range(at: 3))
                    }
                    
                    if let min = Double(minStr), let sec = Double(secStr), let ms = Double(msStr) {
                        let msMultiplier = msStr.count == 3 ? 1000.0 : 100.0
                        let time = (min * 60) + sec + (ms / msMultiplier)
                        times.append(time)
                    }
                    lastTagEnd = max(lastTagEnd, match.range.location + match.range.length)
                }
                
                let textContent = nsLine.substring(from: lastTagEnd).trimmingCharacters(in: .whitespaces)
                for t in times {
                    rawLines.append((time: t, rawContent: textContent))
                }
            } else if !isSynced {
                rawLines.append((time: 0, rawContent: trimmed))
            }
        }
        
        if isSynced {
            rawLines.sort { $0.time < $1.time }
        } else {
            // Unsynced plain lyrics: keep timing at 0 and do NOT fake timing
            isSynced = false
        }
        
        var parsedLines: [LyricLine] = []
        
        for i in 0..<rawLines.count {
            let item = rawLines[i]
            let adjustedTime = max(0, item.time + lrcOffset)
            let text = item.rawContent
            
            // Check for enhanced word tags: <mm:ss.xx>word
            let nsText = text as NSString
            let wordMatches = wordTagRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            
            var words: [LyricWord] = []
            var plainText = ""
            
            if !wordMatches.isEmpty {
                for wIdx in 0..<wordMatches.count {
                    let wMatch = wordMatches[wIdx]
                    let minStr = nsText.substring(with: wMatch.range(at: 1))
                    let secStr = nsText.substring(with: wMatch.range(at: 2))
                    var msStr = "0"
                    if wMatch.range(at: 3).location != NSNotFound {
                        msStr = nsText.substring(with: wMatch.range(at: 3))
                    }
                    let wWord = nsText.substring(with: wMatch.range(at: 4))
                    
                    var wStart = adjustedTime
                    if let min = Double(minStr), let sec = Double(secStr), let ms = Double(msStr) {
                        let mult = msStr.count == 3 ? 1000.0 : 100.0
                        wStart = max(0, (min * 60) + sec + (ms / mult) + lrcOffset)
                    }
                    
                    var wEnd = wStart + 0.35
                    if wIdx + 1 < wordMatches.count {
                        let nextMatch = wordMatches[wIdx + 1]
                        let nextMin = Double(nsText.substring(with: nextMatch.range(at: 1))) ?? 0
                        let nextSec = Double(nsText.substring(with: nextMatch.range(at: 2))) ?? 0
                        wEnd = (nextMin * 60) + nextSec + lrcOffset
                    }
                    
                    let cleanWord = wWord.trimmingCharacters(in: .whitespaces)
                    if !cleanWord.isEmpty {
                        words.append(LyricWord(id: "word_\(i)_\(wIdx)", text: cleanWord, start: wStart, end: max(wStart + 0.1, wEnd)))
                        plainText += (plainText.isEmpty ? "" : " ") + cleanWord
                    }
                }
            }
            
            if words.isEmpty {
                // Strip any residual tags if present
                let cleanLineText = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                plainText = cleanLineText
                
                // Estimate word timing by splitting line duration across words weighted by character/syllable length
                let lineDuration: TimeInterval
                if isSynced {
                    if i + 1 < rawLines.count {
                        let nextTime = max(0, rawLines[i + 1].time + lrcOffset)
                        lineDuration = max(0.8, min(8.0, nextTime - adjustedTime))
                    } else {
                        lineDuration = max(2.0, min(5.0, Double(cleanLineText.count) * 0.08))
                    }
                } else {
                    lineDuration = 3.0
                }
                
                let wordStrings = cleanLineText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if wordStrings.isEmpty {
                    words = [LyricWord(id: "word_\(i)_0", text: cleanLineText, start: adjustedTime, end: adjustedTime + lineDuration)]
                } else {
                    let weights = wordStrings.map { Double(max(1, $0.count)) }
                    let totalWeight = weights.reduce(0, +)
                    var currentStart = adjustedTime
                    
                    for wIdx in 0..<wordStrings.count {
                        let fraction = totalWeight > 0 ? (weights[wIdx] / totalWeight) : (1.0 / Double(wordStrings.count))
                        let wDuration = lineDuration * fraction
                        let wEnd = currentStart + wDuration
                        words.append(LyricWord(
                            id: "word_\(i)_\(wIdx)",
                            text: wordStrings[wIdx],
                            start: currentStart,
                            end: wEnd
                        ))
                        currentStart = wEnd
                    }
                }
            }
            
            let stableLineId = "line_\(i)_\(Int((adjustedTime * 1000).rounded()))"
            parsedLines.append(LyricLine(
                id: stableLineId,
                time: adjustedTime,
                text: plainText,
                words: words
            ))
        }
        
        return ParsedLyrics(lines: parsedLines, isSynced: isSynced)
    }
}
