import Foundation

public struct SidecarInfo: Codable {
    public let artist: String?
    public let creator: String?
    public let track: String?
    public let title: String?
    public let alt_title: String?
    public let uploader: String?
    public let channel: String?
    public let duration: Double?
    public let id: String?
    public let webpage_url: String?
    public let album: String?
    public let release_year: Int?
    public let upload_date: String?
    public let thumbnail: String?
}

public class SidecarParser {
    
    public struct IngestionResult {
        public let info: SidecarInfo?
        public let lyrics: [String: [LyricLine]] // Language code to lines
        public let thumbnails: [URL]
    }
    
    public static func ingest(baseNameURL: URL) -> IngestionResult {
        let directory = baseNameURL.deletingLastPathComponent()
        let baseName = baseNameURL.deletingPathExtension().lastPathComponent
        
        var info: SidecarInfo?
        var lyrics: [String: [LyricLine]] = [:]
        var thumbnails: [URL] = []
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return IngestionResult(info: nil, lyrics: [:], thumbnails: [])
        }
        
        for file in files {
            let filename = file.lastPathComponent
            guard filename.hasPrefix(baseName) else { continue }
            
            if filename == "\(baseName).info.json" {
                if let data = try? Data(contentsOf: file),
                   let decoded = try? JSONDecoder().decode(SidecarInfo.self, from: data) {
                    info = decoded
                }
            } else if filename.hasSuffix(".vtt") || filename.hasSuffix(".srt") || filename.hasSuffix(".json3") {
                let lang = extractLanguage(from: filename, baseName: baseName)
                if let parsed = parseSubtitle(file: file) {
                    lyrics[lang] = parsed
                }
            } else if filename.hasSuffix(".jpg") || filename.hasSuffix(".png") || filename.hasSuffix(".webp") {
                if filename == "\(baseName).jpg" || filename == "\(baseName).png" || filename == "\(baseName).webp" {
                    thumbnails.append(file)
                }
            }
        }
        
        return IngestionResult(info: info, lyrics: lyrics, thumbnails: thumbnails)
    }
    
    public static func extractLanguage(from filename: String, baseName: String) -> String {
        let remainder = filename.replacingOccurrences(of: baseName + ".", with: "")
        let parts = remainder.split(separator: ".")
        if parts.count >= 2 {
            return String(parts[0]) // e.g. "en" from "en.vtt"
        }
        return "unknown"
    }
    
    public static func parseSubtitle(file: URL) -> [LyricLine]? {
        guard let content = try? String(contentsOf: file) else { return nil }
        if file.pathExtension == "json3" {
            return parseJSON3(content)
        } else if file.pathExtension == "vtt" {
            return parseVTT(content)
        } else if file.pathExtension == "srt" {
            return parseSRT(content)
        }
        return nil
    }
    
    public static func parseJSON3(_ content: String) -> [LyricLine]? {
        struct JSON3: Decodable {
            struct Event: Decodable {
                let tStartMs: Int?
                let dDurationMs: Int?
                struct Seg: Decodable {
                    let utf8: String?
                    let tOffsetMs: Int?
                }
                let segs: [Seg]?
            }
            let events: [Event]?
        }
        guard let data = content.data(using: .utf8),
              let json3 = try? JSONDecoder().decode(JSON3.self, from: data),
              let events = json3.events else { return nil }
        
        var lines: [LyricLine] = []
        for event in events {
            guard let tStart = event.tStartMs, let segs = event.segs else { continue }
            var words: [LyricWord] = []
            var fullText = ""
            for seg in segs {
                guard let text = seg.utf8, text.trimmingCharacters(in: .whitespacesAndNewlines) != "" else { continue }
                let offset = seg.tOffsetMs ?? 0
                let start = TimeInterval(tStart + offset) / 1000.0
                words.append(LyricWord(text: text, start: start, end: start + 0.3)) // approx end
                fullText += text
            }
            if !words.isEmpty {
                lines.append(LyricLine(time: words.first!.start, text: fullText.trimmingCharacters(in: .whitespaces), words: words))
            }
        }
        return lines.isEmpty ? nil : lines
    }
    
    public static func parseVTT(_ content: String) -> [LyricLine]? {
        let lines = content.components(separatedBy: .newlines)
        var parsedLines: [LyricLine] = []
        
        var currentStartTime: TimeInterval?
        let wordRegex = try? NSRegularExpression(pattern: #"<(\d{2}:\d{2}:\d{2}\.\d{3})>([^<]+)"#)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "WEBVTT" || trimmed.starts(with: "Kind:") || trimmed.starts(with: "Language:") {
                continue
            }
            
            if trimmed.contains("-->") {
                let parts = trimmed.components(separatedBy: "-->")
                if parts.count == 2 {
                    currentStartTime = parseVTTTime(parts[0].trimmingCharacters(in: .whitespaces))
                }
            } else if let startTime = currentStartTime {
                if let regex = wordRegex {
                    let nsString = trimmed as NSString
                    let results = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length))
                    
                    if !results.isEmpty {
                        var textAcc = ""
                        var words: [LyricWord] = []
                        for result in results {
                            let timeStr = nsString.substring(with: result.range(at: 1))
                            let wordText = nsString.substring(with: result.range(at: 2)).trimmingCharacters(in: .whitespaces)
                            let time = parseVTTTime(timeStr) ?? startTime
                            
                            words.append(LyricWord(text: wordText, start: time, end: time + 0.3))
                            textAcc += wordText + " "
                        }
                        parsedLines.append(LyricLine(time: startTime, text: textAcc.trimmingCharacters(in: .whitespaces), words: words))
                    } else {
                        let textClean = trimmed.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        let words = [LyricWord(text: textClean, start: startTime, end: startTime + 0.3)]
                        parsedLines.append(LyricLine(time: startTime, text: textClean, words: words))
                    }
                }
                currentStartTime = nil
            }
        }
        
        // Deduplicate rolling lines
        var deduped: [LyricLine] = []
        for line in parsedLines {
            if let prev = deduped.last, line.text == prev.text {
                continue
            }
            deduped.append(line)
        }
        
        return deduped.isEmpty ? nil : deduped
    }
    
    public static func parseSRT(_ content: String) -> [LyricLine]? {
        let lines = content.components(separatedBy: .newlines)
        var parsedLines: [LyricLine] = []
        var currentStartTime: TimeInterval?
        var currentText = ""
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || Int(trimmed) != nil { continue }
            
            if trimmed.contains("-->") {
                let parts = trimmed.components(separatedBy: "-->")
                if parts.count == 2 {
                    currentStartTime = parseSRTTime(parts[0].trimmingCharacters(in: .whitespaces))
                }
            } else if let startTime = currentStartTime {
                currentText += (currentText.isEmpty ? "" : " ") + trimmed
                // We add the line if next is empty, but for simplicity let's just add per line
                let words = [LyricWord(text: currentText, start: startTime, end: startTime + 0.3)]
                parsedLines.append(LyricLine(time: startTime, text: currentText, words: words))
                currentStartTime = nil
                currentText = ""
            }
        }
        return parsedLines.isEmpty ? nil : parsedLines
    }
    
    private static func parseVTTTime(_ str: String) -> TimeInterval? {
        // 00:00:01.000 or 00:01.000
        let parts = str.split(separator: ".")
        guard parts.count == 2 else { return nil }
        let timeParts = parts[0].split(separator: ":")
        let ms = Double(parts[1]) ?? 0
        var total = 0.0
        if timeParts.count == 3 {
            total = (Double(timeParts[0]) ?? 0) * 3600 + (Double(timeParts[1]) ?? 0) * 60 + (Double(timeParts[2]) ?? 0)
        } else if timeParts.count == 2 {
            total = (Double(timeParts[0]) ?? 0) * 60 + (Double(timeParts[1]) ?? 0)
        }
        return total + (ms / 1000.0)
    }
    
    private static func parseSRTTime(_ str: String) -> TimeInterval? {
        let replaced = str.replacingOccurrences(of: ",", with: ".")
        return parseVTTTime(replaced)
    }
}
