import AVFoundation
import Foundation

/// Decodes formats not supported natively by Apple (e.g. WebM, Opus, Ogg, FLAC edge-cases)
/// Uses a bundled or system-installed FFmpeg binary via Process.
final class FallbackDecoder: AudioDecoder, @unchecked Sendable {

    private var process: Process?
    private var outputPipe: Pipe?

    private(set) var outputFormat: AVAudioFormat
    private var fileDuration: TimeInterval = 0
    private var fileURL: URL?

    // We request f32le (Float32 little endian), stereo, 44100 Hz from ffmpeg.
    // Output is interleaved; we deinterleave in readNextBuffer().
    init() {
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 2,
            interleaved: false
        )!
    }

    func open(url: URL) throws {
        self.fileURL = url

        let ffmpegPath = findFFmpeg()
        guard !ffmpegPath.isEmpty else {
            throw NSError(domain: "LumoAudio", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "FFmpeg is required to play this format (\(url.pathExtension)). Run: brew install ffmpeg"
            ])
        }

        let ffprobePath = findFFprobe()
        self.fileDuration = getDuration(url: url, ffprobePath: ffprobePath)

        try startDecodingProcess(url: url, time: 0)
    }

    // MARK: - Process management

    private func killCurrentProcess() {
        guard let p = process else { return }
        if p.isRunning {
            p.terminate()
            // Close the write end so any blocking readDataToEndOfFile returns.
            try? outputPipe?.fileHandleForWriting.close()
            // Wait up to 1 s for the process to die before moving on.
            let deadline = Date().addingTimeInterval(1.0)
            while p.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if p.isRunning { p.interrupt() }
        }
        process = nil
        outputPipe = nil
    }

    private func startDecodingProcess(url: URL, time: TimeInterval) throws {
        // Kill the previous process and wait for it to exit.
        killCurrentProcess()

        let ffmpeg = findFFmpeg()
        guard !ffmpeg.isEmpty else {
            throw NSError(domain: "LumoAudio", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "FFmpeg binary not found."
            ])
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = [
            "-nostdin",
            "-nostats",
            "-loglevel", "error",
            "-ss", String(format: "%.3f", time),
            "-i", url.path,
            "-f", "f32le",
            "-acodec", "pcm_f32le",
            "-ar", "44100",
            "-ac", "2",
            "pipe:1"
        ]

        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice

        try p.run()

        self.process = p
        self.outputPipe = pipe
    }

    // MARK: - AudioDecoder

    var duration: TimeInterval { fileDuration }

    func readNextBuffer() throws -> AVAudioPCMBuffer? {
        guard let pipe = outputPipe else { return nil }

        // ~0.5 s of stereo f32le at 44100 Hz
        let chunkSize = 44100 * 2 * 4 / 2   // 176 400 bytes
        let data = try pipe.fileHandleForReading.read(upToCount: chunkSize)

        guard let data = data, !data.isEmpty else { return nil }

        // Each sample is 4 bytes; interleaved stereo → frameCount = bytes / (2 ch × 4 B)
        let frameCount = AVAudioFrameCount(data.count / (2 * 4))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount

        // Deinterleave: FFmpeg outputs L R L R …  →  L L L …  R R R …
        data.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Float.self).baseAddress else { return }
            let channels = Int(buffer.format.channelCount)   // 2
            let frames   = Int(frameCount)
            for ch in 0..<channels {
                guard let dst = buffer.floatChannelData?[ch] else { continue }
                for f in 0..<frames {
                    dst[f] = src[f * channels + ch]
                }
            }
        }

        return buffer
    }

    func seek(to time: TimeInterval) throws {
        guard let url = fileURL else { return }
        try startDecodingProcess(url: url, time: time)
    }

    deinit {
        killCurrentProcess()
    }

    // MARK: - Binary discovery

    private func findFFmpeg() -> String { findBinary("ffmpeg") }
    private func findFFprobe() -> String { findBinary("ffprobe") }

    private func findBinary(_ name: String) -> String {
        var paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        let exeDir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .deletingLastPathComponent().path
        paths += [
            "\(exeDir)/\(name)",
            "\(exeDir)/Lumo.app/Contents/MacOS/\(name)",
            Bundle.main.bundlePath + "/Contents/MacOS/\(name)",
            (Bundle.main.resourcePath ?? "") + "/\(name)",
            FileManager.default.currentDirectoryPath + "/bin/\(name)"
        ]
        let fm = FileManager.default
        for path in paths {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
                return path
            }
        }
        return ""
    }

    private func getDuration(url: URL, ffprobePath: String) -> TimeInterval {
        guard !ffprobePath.isEmpty,
              FileManager.default.fileExists(atPath: ffprobePath) else { return 0 }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffprobePath)
        task.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path
        ]
        task.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        if let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let d = TimeInterval(s) {
            return d
        }
        return 0
    }
}
