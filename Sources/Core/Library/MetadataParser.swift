import AVFoundation
import CoreGraphics

/// Extracts metadata from audio files using AVFoundation.
enum MetadataParser {
    
    struct ParsedMetadata {
        var title: String = ""
        var artist: String = ""
        var album: String = ""
        var genre: String = ""
        var composer: String = ""
        var year: Int = 0
        var trackNumber: Int = 0
        var trackTotal: Int = 0
        var discNumber: Int = 1
        var discTotal: Int = 1
        var duration: TimeInterval = 0
        var artworkData: Data? = nil
        
        // Basic audio properties
        var sampleRate: Int = 0
        var channels: Int = 2
        
        // Lyrics
        var lyricsText: String?
        var hasSyncedLyrics: Bool = false
        var sidecarLyricsPath: String?
    }
    
    enum ContainerType {
        case mp4, webm, flac, id3, ogg, unknown
    }
    
    private static func detectContainerType(url: URL) -> ContainerType {
        guard let file = FileHandle(forReadingAtPath: url.path) else { return .unknown }
        defer { try? file.close() }
        let data = file.readData(ofLength: 12)
        if data.count >= 4 {
            if data.prefix(4) == Data([0x1A, 0x45, 0xDF, 0xA3]) { return .webm }
            if data.prefix(4) == Data("fLaC".utf8) { return .flac }
            if data.prefix(3) == Data("ID3".utf8) { return .id3 }
            if data.prefix(4) == Data("OggS".utf8) { return .ogg }
            
            if data.count >= 8 {
                let boxType = String(data: data[4..<8], encoding: .ascii)
                if boxType == "ftyp" { return .mp4 }
            }
        }
        return .unknown
    }
    
    /// Asynchronously parses metadata for a given file URL.
    static func parse(url: URL) async -> ParsedMetadata {
        var metadata = ParsedMetadata()
        let asset = AVURLAsset(url: url)
        
        let container = detectContainerType(url: url)
        
        // 1. Duration (AVAsset) - but skip WebM because it crashes AVFoundation
        if container != .webm {
            if let duration = try? await asset.load(.duration) {
                let seconds = duration.seconds
                if !seconds.isNaN && seconds > 1.0 {
                    metadata.duration = seconds
                }
            }
        }
        
        // 2. Fall back to AVAudioFile
        if metadata.duration <= 1.0 && container != .webm {
            if let file = try? AVAudioFile(forReading: url) {
                let length = file.length
                let sampleRate = file.processingFormat.sampleRate
                if sampleRate > 0 {
                    metadata.duration = Double(length) / sampleRate
                }
            }
        }
        
        // 3. Scan MP4 boxes for fragmented durations (sidx, moof/traf/trun, mvex/mehd)
        if metadata.duration <= 1.0 && container == .mp4 {
            metadata.duration = await parseMP4Fragments(url: url)
        }
        
        // 4. .info.json sidecar duration
        if metadata.duration <= 1.0 {
            let jsonURL = url.deletingPathExtension().appendingPathExtension("info.json")
            if FileManager.default.fileExists(atPath: jsonURL.path),
               let data = try? Data(contentsOf: jsonURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let durationStr = json["duration"] as? String, let d = TimeInterval(durationStr) {
                    metadata.duration = d
                } else if let d = json["duration"] as? Double {
                    metadata.duration = d
                }
            }
        }
        
        // 5. Fallback to FFprobe for non-native formats (e.g. WebM/Opus)
        if metadata.duration <= 1.0 {
            if let ffprobePath = findFFprobe() {
                await parseWithFFprobe(url: url, ffprobePath: ffprobePath, metadata: &metadata)
            }
        }
        
        // 6. Last resort: decode the file once in the background and count frames
        if metadata.duration <= 1.0 && container != .webm {
            metadata.duration = await decodeDuration(url: url)
        }
        
        // Format Info
        if container != .webm {
            do {
                if let track = try await asset.loadTracks(withMediaType: .audio).first,
                   let formatDescriptions = try await track.load(.formatDescriptions) as [CMAudioFormatDescription]?,
                   let format = formatDescriptions.first,
                   let streamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
                    
                    metadata.sampleRate = Int(streamBasicDescription.pointee.mSampleRate)
                    metadata.channels = Int(streamBasicDescription.pointee.mChannelsPerFrame)
                }
            } catch {
                print("Failed to read format info for \(url.lastPathComponent): \(error)")
            }
            
            // Common Metadata
            do {
                let formats = try await asset.load(.availableMetadataFormats)
                for format in formats {
                    if let items = try? await asset.loadMetadata(for: format) {
                        for item in items {
                            guard let commonKey = item.commonKey else { continue }
                            switch commonKey {
                            case .commonKeyTitle: if let v = try? await item.load(.stringValue) { metadata.title = v }
                            case .commonKeyArtist: if let v = try? await item.load(.stringValue) { metadata.artist = v }
                            case .commonKeyAlbumName: if let v = try? await item.load(.stringValue) { metadata.album = v }
                            case .commonKeyType: if let v = try? await item.load(.stringValue) { metadata.genre = v }
                            case .commonKeyArtwork: if let d = try? await item.load(.dataValue) { metadata.artworkData = d }
                            case .commonKeyCreationDate:
                                if let v = try? await item.load(.stringValue), let y = Int(v.prefix(4)) { metadata.year = y }
                            default: break
                            }
                        }
                    }
                }
            } catch {
                print("Failed to read common metadata for \(url.lastPathComponent): \(error)")
            }
            
            // Advanced Metadata
            do {
                let allMetadata = try await asset.load(.metadata)
                for item in allMetadata {
                    if let keySpace = item.keySpace {
                        let keyString = item.key?.description ?? ""
                        if keySpace == .id3 {
                            if keyString == "TRCK", let v = try? await item.load(.stringValue) { parseFraction(v, into: &metadata.trackNumber, total: &metadata.trackTotal) }
                            else if keyString == "TPOS", let v = try? await item.load(.stringValue) { parseFraction(v, into: &metadata.discNumber, total: &metadata.discTotal) }
                            else if keyString == "TYER", let v = try? await item.load(.stringValue), let y = Int(v) { metadata.year = y }
                        } else if keySpace == .iTunes {
                            if keyString == "trkn", let d = try? await item.load(.dataValue), d.count >= 8 { let a = [UInt8](d); metadata.trackNumber = Int(a[3]); metadata.trackTotal = Int(a[5]) }
                            else if keyString == "disk", let d = try? await item.load(.dataValue), d.count >= 6 { let a = [UInt8](d); metadata.discNumber = Int(a[3]); metadata.discTotal = Int(a[5]) }
                            else if keyString == "©day", let v = try? await item.load(.stringValue), let y = Int(v.prefix(4)) { metadata.year = y }
                            else if keyString == "©lyr" || keyString == "lyrics", let v = try? await item.load(.stringValue) {
                                metadata.lyricsText = v
                                metadata.hasSyncedLyrics = v.contains("[") && v.contains("]") && v.contains(":")
                            }
                        } else {
                            if keyString.lowercased() == "uslt" || keyString.lowercased() == "sylt" || keyString.lowercased() == "lyrics", let v = try? await item.load(.stringValue) {
                                metadata.lyricsText = v
                                metadata.hasSyncedLyrics = v.contains("[") && v.contains("]") && v.contains(":")
                            }
                        }
                    }
                }
            } catch {
                print("Failed to read advanced metadata for \(url.lastPathComponent): \(error)")
            }
        }
        
        await detectSidecarLyrics(url: url, metadata: &metadata)
        
        return metadata
    }
    
    private static func parseMP4Fragments(url: URL) async -> Double {
        guard let file = FileHandle(forReadingAtPath: url.path) else { return 0 }
        defer { try? file.close() }
        
        var totalDuration: Double = 0
        var foundSidx = false
        var timescale: UInt32 = 1000
        
        var offset: UInt64 = 0
        let fileSize = (try? file.seekToEnd()) ?? 0
        
        while offset < fileSize {
            try? file.seek(toOffset: offset)
            guard let header = try? file.read(upToCount: 8), header.count == 8 else { break }
            let size = UInt64(UInt32(bigEndian: header[0..<4].withUnsafeBytes { $0.load(as: UInt32.self) }))
            let type = String(data: header[4..<8], encoding: .ascii) ?? ""
            
            var actualSize = size
            if size == 1 {
                guard let largeSizeData = try? file.read(upToCount: 8), largeSizeData.count == 8 else { break }
                actualSize = UInt64(bigEndian: largeSizeData.withUnsafeBytes { $0.load(as: UInt64.self) })
            }
            if actualSize < 8 { break }
            
            if type == "moov" || type == "traf" || type == "mvex" {
                offset += (size == 1 ? 16 : 8)
                continue
            }
            
            if type == "mvhd" {
                if let data = try? file.read(upToCount: 32) {
                    let version = data[0]
                    if version == 1 {
                        timescale = UInt32(bigEndian: data[20..<24].withUnsafeBytes { $0.load(as: UInt32.self) })
                    } else {
                        timescale = UInt32(bigEndian: data[12..<16].withUnsafeBytes { $0.load(as: UInt32.self) })
                    }
                }
            }
            
            if type == "sidx" {
                if let data = try? file.read(upToCount: 40) {
                    let version = data[0]
                    let tsOffset = 8
                    let ts = UInt32(bigEndian: data[tsOffset..<tsOffset+4].withUnsafeBytes { $0.load(as: UInt32.self) })
                    if ts > 0 { timescale = ts }
                    
                    var earliestPresTimeOffset = tsOffset + 4
                    if version == 0 { earliestPresTimeOffset += 4 + 4 }
                    else { earliestPresTimeOffset += 8 + 8 }
                    
                    let refCountOffset = earliestPresTimeOffset + 2
                    let refCount = UInt16(bigEndian: data[refCountOffset..<refCountOffset+2].withUnsafeBytes { $0.load(as: UInt16.self) })
                    
                    var sidxDuration: UInt64 = 0
                    var currentOffset = UInt64(offset + (size == 1 ? 16 : 8) + UInt64(refCountOffset + 2))
                    
                    for _ in 0..<refCount {
                        try? file.seek(toOffset: currentOffset)
                        if let itemData = try? file.read(upToCount: 12) {
                            let subsegmentDuration = UInt32(bigEndian: itemData[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) })
                            sidxDuration += UInt64(subsegmentDuration)
                            currentOffset += 12
                        } else {
                            break
                        }
                    }
                    if sidxDuration > 0 && timescale > 0 {
                        totalDuration = Double(sidxDuration) / Double(timescale)
                        foundSidx = true
                        break
                    }
                }
            }
            
            if type == "mehd" {
                if let data = try? file.read(upToCount: 12) {
                    let version = data[0]
                    var fragmentDuration: UInt64 = 0
                    if version == 1 {
                        fragmentDuration = UInt64(bigEndian: data[4..<12].withUnsafeBytes { $0.load(as: UInt64.self) })
                    } else {
                        fragmentDuration = UInt64(UInt32(bigEndian: data[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }))
                    }
                    if fragmentDuration > 0 && timescale > 0 {
                        totalDuration = Double(fragmentDuration) / Double(timescale)
                        foundSidx = true
                    }
                }
            }
            
            offset += actualSize
        }
        
        return foundSidx ? totalDuration : 0
    }
    
    private static func decodeDuration(url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return 0 }
        guard let reader = try? AVAssetReader(asset: asset) else { return 0 }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        
        if reader.startReading() {
            var lastTime: CMTime = .zero
            while let sample = output.copyNextSampleBuffer() {
                lastTime = CMSampleBufferGetPresentationTimeStamp(sample)
                CMSampleBufferInvalidate(sample)
            }
            if reader.status == .completed {
                return lastTime.seconds > 0 ? lastTime.seconds : 0
            }
        }
        return 0
    }
    
    private static func detectSidecarLyrics(url: URL, metadata: inout ParsedMetadata) async {
        let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
        if FileManager.default.fileExists(atPath: lrcURL.path) {
            if let lrcData = try? Data(contentsOf: lrcURL),
               let lrcString = String(data: lrcData, encoding: .utf8) {
                metadata.lyricsText = lrcString
                metadata.hasSyncedLyrics = lrcString.contains("[") && lrcString.contains("]") && lrcString.contains(":")
                metadata.sidecarLyricsPath = lrcURL.path
            }
        }
    }
    
    public static func findFFprobe() -> String? {
        var paths = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        let exeURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let exeDir = exeURL.deletingLastPathComponent().path
        paths.append(exeDir + "/ffprobe")
        paths.append(exeDir + "/bin/ffprobe")
        paths.append(Bundle.main.bundlePath + "/Contents/MacOS/ffprobe")
        paths.append(FileManager.default.currentDirectoryPath + "/bin/ffprobe")
        
        let rootPath = exeURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        paths.append(rootPath.appendingPathComponent("bin/ffprobe").path)
        
        if let resourcePath = Bundle.main.resourcePath {
            paths.append(resourcePath + "/ffprobe")
        }
        for path in paths {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue { return path }
        }
        return nil
    }
    
    private static func parseWithFFprobe(url: URL, ffprobePath: String, metadata: inout ParsedMetadata) async {
        let data = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: ffprobePath)
                task.arguments = ["-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", url.path]
                let pipe = Pipe()
                task.standardOutput = pipe
                
                var didFinish = false
                let timeoutWorkItem = DispatchWorkItem {
                    if !didFinish { task.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 60.0, execute: timeoutWorkItem)
                
                do {
                    try task.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    didFinish = true
                    continuation.resume(returning: data)
                } catch {
                    didFinish = true
                    continuation.resume(returning: Data())
                }
            }
        }
        
        guard !data.isEmpty else { return }
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let format = json["format"] as? [String: Any] {
                if let durationStr = format["duration"] as? String, let duration = TimeInterval(durationStr) {
                    metadata.duration = duration
                }
                if let tags = format["tags"] as? [String: Any] {
                    if let title = tags["title"] as? String { metadata.title = title }
                    if let artist = tags["artist"] as? String { metadata.artist = artist }
                    if let album = tags["album"] as? String { metadata.album = album }
                    if let genre = tags["genre"] as? String { metadata.genre = genre }
                    if let date = tags["date"] as? String, let year = Int(date.prefix(4)) { metadata.year = year }
                }
            }
        } catch {}
    }
    
    private static func parseFraction(_ string: String, into value: inout Int, total: inout Int) {
        let components = string.split(separator: "/")
        if components.count >= 1, let v = Int(components[0]) { value = v }
        if components.count >= 2, let t = Int(components[1]) { total = t }
    }
}
