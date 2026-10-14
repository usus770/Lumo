import Foundation

/// Fallback provider for video automatic captions using yt-dlp when available.
/// Runs with zero shell string interpolation (arguments passed as an array) and a 15s process timeout.
public actor YouTubeCaptionsProvider: Sendable {
    public static let shared = YouTubeCaptionsProvider()
    
    private let candidatePaths = [
        "/opt/homebrew/bin/yt-dlp",
        "/usr/local/bin/yt-dlp",
        "/usr/bin/yt-dlp"
    ]
    
    private func resolveBinary() -> String? {
        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    public func fetchCaptions(videoId: String) async -> LyricsResultCandidate? {
        // Sanitize videoId: must strictly match YouTube 11-character identifier
        let validChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard videoId.count == 11, videoId.rangeOfCharacter(from: validChars.inverted) == nil else {
            return nil
        }
        
        guard let binaryPath = resolveBinary() else {
            return nil
        }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("lumo_captions_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "--skip-download",
            "--write-auto-sub",
            "--sub-lang", "en,hi",
            "--sub-format", "vtt",
            "-o", "\(tempDir.path)/caption.%(ext)s",
            "https://www.youtube.com/watch?v=\(videoId)"
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            
            // 15 second timeout enforcement
            let startTime = Date()
            while process.isRunning {
                if Date().timeIntervalSince(startTime) > 15.0 {
                    process.terminate()
                    return nil
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            
            guard process.terminationStatus == 0 else { return nil }
            
            // Check for created .vtt file
            let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            guard let vttFile = contents.first(where: { $0.hasSuffix(".vtt") }) else { return nil }
            let vttPath = tempDir.appendingPathComponent(vttFile)
            let vttContent = try String(contentsOf: vttPath, encoding: .utf8)
            
            let plainText = Self.cleanVTT(vttContent)
            guard !plainText.isEmpty else { return nil }
            
            return LyricsResultCandidate(
                lyricsText: plainText,
                isSynced: false,
                source: "auto-captions, low quality",
                durationValid: true,
                lastTimestamp: nil,
                detectedScript: nil,
                romanizedText: nil
            )
        } catch {
            return nil
        }
    }
    
    private static func cleanVTT(_ vtt: String) -> String {
        var lines: [String] = []
        let rawLines = vtt.components(separatedBy: .newlines)
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("WEBVTT") || trimmed.contains("-->") || trimmed.allSatisfy({ $0.isNumber }) {
                continue
            }
            // Strip HTML/VTT formatting tags like <c> </c>
            let cleanLine = trimmed.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            if !cleanLine.isEmpty && !lines.contains(cleanLine) {
                lines.append(cleanLine)
            }
        }
        return lines.joined(separator: "\n")
    }
}
