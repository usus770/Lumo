import Foundation
import AVFoundation

public protocol LyricsProvider: Sendable {
    var name: String { get }
    var isEnabled: Bool { get }
    func fetchLyrics(artist: String, title: String, album: String?, duration: TimeInterval?, url: URL?) async -> LyricsCandidate?
}

public struct LyricsCandidate: Sendable {
    public let lyrics: ParsedLyrics
    public let source: LyricsEngine.LyricsSource
    public let confidence: Double
    public let isSynced: Bool
    public let translation: String?
    
    public init(lyrics: ParsedLyrics, source: LyricsEngine.LyricsSource, confidence: Double, isSynced: Bool, translation: String? = nil) {
        self.lyrics = lyrics
        self.source = source
        self.confidence = confidence
        self.isSynced = isSynced
        self.translation = translation
    }
}

public actor LyricsEngine {
    public static let shared = LyricsEngine()
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 10.0
        config.httpAdditionalHeaders = ["User-Agent": "Lumo/1.0 (https://github.com/lumo)"]
        self.session = URLSession(configuration: config)
    }
    
    public enum LyricsSource: String, Sendable, CaseIterable {
        case lrc = "Sidecar .lrc"
        case embedded = "Embedded"
        case cache = "Local Cache"
        case lrclib = "LRCLIB"
        case netease = "NetEase"
        case captions = "YouTube Captions"
        case whisper = "Groq Whisper"
        case aligned = "Aligned (Lyrics + Whisper)"
    }
    
    public struct ResolvedLyrics: Sendable {
        public let lyrics: ParsedLyrics
        public let source: LyricsSource
        public let autoOffset: TimeInterval
        public let speedRatio: Double
        public let translation: String?
        public let confidence: Double
        
        public init(lyrics: ParsedLyrics, source: LyricsSource, autoOffset: TimeInterval = 0, speedRatio: Double = 1, translation: String? = nil, confidence: Double = 1.0) {
            self.lyrics = lyrics
            self.source = source
            self.autoOffset = autoOffset
            self.speedRatio = speedRatio
            self.translation = translation
            self.confidence = confidence
        }
    }
    
    public func resolveLyrics(url: URL?, artist: String, title: String, album: String?, duration: TimeInterval?) async -> ResolvedLyrics? {
        let cleanTitle = TitleCleaner.clean(title).cleanedString
        let cleanArtist = TitleCleaner.clean(artist.components(separatedBy: " (feat.").first ?? artist).cleanedString
        
        // Guard against invalid/bogus paths for external playback ("" pointing to root/working directory)
        let validFileURL: URL? = (url != nil && !url!.path.isEmpty && url!.path != "/" && FileManager.default.fileExists(atPath: url!.path)) ? url : nil
        
        var candidates: [LyricsCandidate] = []
        
        // 1. Sidecar .lrc / .srt / .vtt (direct check on real file URL)
        if let fileURL = validFileURL {
            if let sidecarCandidate = checkSidecarLyrics(url: fileURL, duration: duration) {
                candidates.append(sidecarCandidate)
            }
        }
        
        // 2. Embedded USLT/SYLT tags
        if let fileURL = validFileURL {
            if let embeddedCandidate = await checkEmbeddedLyrics(url: fileURL, duration: duration) {
                candidates.append(embeddedCandidate)
            }
        }
        
        // 3. Disk cache
        let cacheKey = validFileURL != nil ? NowPlayingSnapshot.stableIDForLocal(filePath: validFileURL!.path) : NowPlayingSnapshot.stableIDForExternal(videoId: nil, artist: cleanArtist, title: cleanTitle, duration: duration ?? 0)
        if let cachedCandidate = checkDiskCache(id: cacheKey, duration: duration) {
            candidates.append(cachedCandidate)
        }
        
        // 4 & 5: Online providers (LRCLIB & NetEase)
        let settings = SettingsStore.shared
        
        async let lrclibResult: LyricsCandidate? = {
            if settings.enableLRCLibLyrics {
                return await fetchFromLRCLIB(artist: cleanArtist, title: cleanTitle, album: album, duration: duration)
            }
            return nil
        }()
        
        async let netEaseResult: LyricsCandidate? = {
            if settings.enableNetEaseLyrics {
                return await fetchFromNetEase(artist: cleanArtist, title: cleanTitle, duration: duration)
            }
            return nil
        }()
        
        if let lrc = await lrclibResult {
            candidates.append(lrc)
        }
        if let ne = await netEaseResult {
            candidates.append(ne)
        }
        
        // 6. YouTube Captions sidecar
        if let fileURL = validFileURL {
            let sidecar = SidecarParser.ingest(baseNameURL: fileURL)
            if let lines = sidecar.lyrics["en"] ?? sidecar.lyrics["auto"] ?? sidecar.lyrics.values.first {
                candidates.append(LyricsCandidate(
                    lyrics: ParsedLyrics(lines: lines, isSynced: true),
                    source: .captions,
                    confidence: 0.90,
                    isSynced: true
                ))
            }
        }
        
        // Check if we already found a synced result
        let hasSynced = candidates.contains { $0.isSynced && $0.confidence >= 0.70 }
        
        // 7. Whisper: ONLY launched if NOTHING synced was found, and real audio URL is available
        if !hasSynced && settings.enableGroqLyrics, let fileURL = validFileURL {
            if let whisperCandidate = await runWhisperPipeline(url: fileURL, duration: duration, existingPlain: candidates.first(where: { !$0.isSynced })) {
                candidates.append(whisperCandidate)
            }
        }
        
        // Take the BEST candidate by confidence (preferring synced lyrics)
        guard let best = candidates.sorted(by: {
            if $0.isSynced != $1.isSynced {
                return $0.isSynced && !$1.isSynced
            }
            return $0.confidence > $1.confidence
        }).first else {
            return nil
        }
        
        return ResolvedLyrics(
            lyrics: best.lyrics,
            source: best.source,
            autoOffset: 0,
            speedRatio: 1,
            translation: best.translation,
            confidence: best.confidence
        )
    }
    
    // MARK: - Sidecar & Embedded
    
    private func checkSidecarLyrics(url: URL, duration: TimeInterval?) -> LyricsCandidate? {
        let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
        if FileManager.default.fileExists(atPath: lrcURL.path),
           let content = try? String(contentsOf: lrcURL, encoding: .utf8),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = LyricsParser.parse(content, duration: duration)
            return LyricsCandidate(lyrics: parsed, source: .lrc, confidence: 1.0, isSynced: parsed.isSynced)
        }
        return nil
    }
    
    private func checkEmbeddedLyrics(url: URL, duration: TimeInterval?) async -> LyricsCandidate? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        
        for item in metadata {
            let ident = item.identifier?.rawValue.lowercased() ?? ""
            let key = item.commonKey?.rawValue.lowercased() ?? ""
            if ident.contains("lyric") || ident.contains("uslt") || ident.contains("sylt") || key.contains("lyric") {
                if let val = try? await item.load(.stringValue), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let parsed = LyricsParser.parse(val, duration: duration)
                    return LyricsCandidate(lyrics: parsed, source: .embedded, confidence: parsed.isSynced ? 0.98 : 0.75, isSynced: parsed.isSynced)
                }
            }
        }
        return nil
    }
    
    private func checkDiskCache(id: String, duration: TimeInterval?) -> LyricsCandidate? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheFile = appSupport.appendingPathComponent("Lumo/LyricsCache/\(id).json")
        guard FileManager.default.fileExists(atPath: cacheFile.path),
              let data = try? Data(contentsOf: cacheFile) else { return nil }
        
        struct CachedLyricsRecord: Codable {
            let id: String
            let lyricsText: String
            let hasSyncedLyrics: Bool
            let source: String?
        }
        
        guard let record = try? JSONDecoder().decode(CachedLyricsRecord.self, from: data) else { return nil }
        let parsed = LyricsParser.parse(record.lyricsText, duration: duration)
        let src = record.source.flatMap { LyricsSource(rawValue: $0) } ?? .cache
        return LyricsCandidate(lyrics: parsed, source: src, confidence: record.hasSyncedLyrics ? 0.95 : 0.70, isSynced: record.hasSyncedLyrics)
    }
    
    // MARK: - LRCLIB Provider with Validation
    
    private struct LRCLibHit: Decodable {
        let id: Int
        let trackName: String
        let artistName: String
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }
    
    private func fetchFromLRCLIB(artist: String, title: String, album: String?, duration: TimeInterval?) async -> LyricsCandidate? {
        let cleanT = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanA = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanT.isEmpty else { return nil }
        
        // Strategy candidates: 1) track_name & artist_name, 2) q search, 3) swapped track_name & artist_name
        var queryUrls: [String] = []
        if let encT = cleanT.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let encA = cleanA.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryUrls.append("https://lrclib.net/api/search?track_name=\(encT)&artist_name=\(encA)")
            queryUrls.append("https://lrclib.net/api/search?q=\(encT)+\(encA)")
            if !cleanA.isEmpty {
                queryUrls.append("https://lrclib.net/api/search?track_name=\(encA)&artist_name=\(encT)")
            }
        }
        
        for urlStr in queryUrls {
            guard let url = URL(string: urlStr) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                let results = try JSONDecoder().decode([LRCLibHit].self, from: data)
                
                for item in results {
                    let titleSim = OnlineVerifier.tokenSetSimilarity(cleanT, item.trackName)
                    guard titleSim >= 0.70 else { continue }
                    
                    let artistSim = cleanA.isEmpty ? 1.0 : max(OnlineVerifier.tokenSetSimilarity(cleanA, item.artistName), OnlineVerifier.tokenSetSimilarity(cleanT, item.artistName))
                    guard artistSim >= 0.50 else { continue }
                    
                    if let targetDur = duration, targetDur > 1.0, let itemDur = item.duration {
                        guard abs(targetDur - itemDur) <= 4.0 else { continue }
                    }
                    
                    let matchQuality = (titleSim * 0.6) + (artistSim * 0.4)
                    
                    if let synced = item.syncedLyrics, !synced.isEmpty {
                        let parsed = LyricsParser.parse(synced, duration: duration)
                        return LyricsCandidate(lyrics: parsed, source: .lrclib, confidence: 0.93 * matchQuality, isSynced: true)
                    } else if let plain = item.plainLyrics, !plain.isEmpty {
                        let parsed = LyricsParser.parse(plain, duration: duration)
                        return LyricsCandidate(lyrics: parsed, source: .lrclib, confidence: 0.75 * matchQuality, isSynced: true)
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
    
    // MARK: - NetEase Provider (Indic / Hindi / Asian coverage)
    
    private func fetchFromNetEase(artist: String, title: String, duration: TimeInterval?) async -> LyricsCandidate? {
        let query = "\(title) \(artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://music.163.com/api/search/get/web?s=\(encoded)&type=1&offset=0&total=true&limit=5") else { return nil }
        
        var req = URLRequest(url: searchURL)
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        
        do {
            let (data, response) = try await session.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let resultObj = json["result"] as? [String: Any],
                  let songs = resultObj["songs"] as? [[String: Any]] else { return nil }
            
            for song in songs {
                guard let songId = song["id"] as? Int,
                      let songName = song["name"] as? String else { continue }
                
                var songArtist = "Unknown"
                if let artists = song["artists"] as? [[String: Any]], let first = artists.first, let aName = first["name"] as? String {
                    songArtist = aName
                }
                
                let titleSim = OnlineVerifier.tokenSetSimilarity(title, songName)
                guard titleSim >= 0.75 else { continue }
                
                let artistSim = OnlineVerifier.tokenSetSimilarity(artist, songArtist)
                guard artistSim >= 0.50 else { continue }
                
                if let targetDur = duration, targetDur > 1.0, let songDurMs = song["duration"] as? Double {
                    let songDurSec = songDurMs / 1000.0
                    guard abs(targetDur - songDurSec) <= 4.0 else { continue }
                }
                
                // Fetch lyrics for this song ID
                guard let lyricURL = URL(string: "https://music.163.com/api/song/lyric?os=pc&id=\(songId)&lv=-1&kv=-1&tv=-1") else { continue }
                var lyricReq = URLRequest(url: lyricURL)
                lyricReq.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
                
                let (lyricData, lyricResp) = try await session.data(for: lyricReq)
                guard (lyricResp as? HTTPURLResponse)?.statusCode == 200 else { continue }
                guard let lyricJson = try? JSONSerialization.jsonObject(with: lyricData) as? [String: Any],
                      let lrcObj = lyricJson["lrc"] as? [String: Any],
                      let lrcText = lrcObj["lyric"] as? String, !lrcText.isEmpty else { continue }
                
                let tlyricObj = lyricJson["tlyric"] as? [String: Any]
                let translationText = tlyricObj?["lyric"] as? String
                
                let parsed = LyricsParser.parse(lrcText, duration: duration)
                if !parsed.lines.isEmpty {
                    let matchQuality = (titleSim * 0.6) + (artistSim * 0.4)
                    return LyricsCandidate(
                        lyrics: parsed,
                        source: .netease,
                        confidence: 0.92 * matchQuality,
                        isSynced: parsed.isSynced,
                        translation: translationText
                    )
                }
            }
        } catch {
            // Ignore error
        }
        return nil
    }
    
    // MARK: - Whisper Pipeline
    
    private func runWhisperPipeline(url: URL, duration: TimeInterval?, existingPlain: LyricsCandidate?) async -> LyricsCandidate? {
        do {
            let dur = duration ?? 180.0
            let audioData = try await AudioChunker.extractWAV(from: url, startTime: 0, duration: min(dur, 240))
            
            // Auto-detect language by default (omits fixed language header)
            let whisperRes = try await GroqWhisperClient.shared.transcribe(audioData: audioData, language: "Auto")
            
            guard let words = whisperRes.words, !words.isEmpty else { return nil }
            
            // Filter bad quality transcription
            let badQuality = whisperRes.segments?.contains(where: {
                $0.no_speech_prob > 0.65 || $0.avg_logprob < -1.1 || $0.compression_ratio > 2.5
            }) ?? false
            guard !badQuality else { return nil }
            
            // If plain lyrics are available, align them
            if let plain = existingPlain {
                let plainText = plain.lyrics.lines.map { $0.text }.joined(separator: "\n")
                let aligned = LyricsAligner.align(referenceText: plainText, whisperWords: words)
                return LyricsCandidate(lyrics: aligned, source: .aligned, confidence: 0.88, isSynced: true)
            }
            
            // Otherwise, group words into lines by pause (> 0.6s) or punctuation
            var lines: [LyricLine] = []
            var currentWords: [LyricWord] = []
            var currentText = ""
            
            for (idx, w) in words.enumerated() {
                let cleanW = w.word.trimmingCharacters(in: .whitespaces)
                guard !cleanW.isEmpty else { continue }
                
                currentWords.append(LyricWord(id: "whisper_\(idx)", text: cleanW, start: w.start, end: w.end))
                currentText += (currentText.isEmpty ? "" : " ") + cleanW
                
                let isLastWord = idx == words.count - 1
                let nextPause = !isLastWord && (words[idx + 1].start - w.end > 0.6)
                let endsWithPunct = cleanW.hasSuffix(".") || cleanW.hasSuffix("?") || cleanW.hasSuffix("!") || cleanW.hasSuffix(",") || cleanW.hasSuffix("।")
                
                if isLastWord || nextPause || (currentWords.count >= 6 && endsWithPunct) || currentWords.count >= 10 {
                    if !currentText.lowercased().contains("thanks for watching") && !currentWords.isEmpty {
                        lines.append(LyricLine(
                            id: "line_\(lines.count)_\(Int((currentWords.first!.start * 1000).rounded()))",
                            time: currentWords.first!.start,
                            text: currentText,
                            words: currentWords
                        ))
                    }
                    currentWords = []
                    currentText = ""
                }
            }
            
            guard !lines.isEmpty else { return nil }
            return LyricsCandidate(lyrics: ParsedLyrics(lines: lines, isSynced: true), source: .whisper, confidence: 0.85, isSynced: true)
        } catch {
            return nil
        }
    }
}
