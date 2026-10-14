import AVFoundation

/// Decodes formats natively supported by Apple (MP3, AAC, ALAC, FLAC, WAV, AIFF, etc.)
final class NativeDecoder: AudioDecoder, @unchecked Sendable {
    
    private var file: AVAudioFile?
    
    /// We standardise all output to stereo 44.1kHz or whatever the engine uses,
    /// but usually it's best to use the standard processing format.
    private(set) var outputFormat: AVAudioFormat
    
    // Use a larger buffer size (2 seconds) to prevent audio dropouts/stuttering
    private let bufferCapacity: AVAudioFrameCount
    
    init() {
        self.outputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        self.bufferCapacity = AVAudioFrameCount(2.0 * 44100) // ~2 seconds
    }
    
    func open(url: URL) throws {
        self.file = try AVAudioFile(forReading: url)
        
        // Convert to standard stereo PCM format
        if let standardFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file!.fileFormat.sampleRate,
            channels: 2,
            interleaved: false
        ) {
            self.outputFormat = standardFormat
        }
    }
    
    var duration: TimeInterval {
        guard let file = file else { return 0 }
        let sampleRate = file.fileFormat.sampleRate
        let length = file.length
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(length) / sampleRate
    }
    
    func readNextBuffer() throws -> AVAudioPCMBuffer? {
        guard let file = file else { return nil }
        
        // If we've reached the end, return nil
        if file.framePosition >= file.length {
            return nil
        }
        
        let framesToRead = min(bufferCapacity, AVAudioFrameCount(file.length - file.framePosition))
        guard framesToRead > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesToRead) else {
            return nil
        }
        
        try file.read(into: buffer)
        return buffer
    }
    
    func seek(to time: TimeInterval) throws {
        guard let file = file else { return }
        
        let targetFrame = AVAudioFramePosition(time * file.fileFormat.sampleRate)
        let safeFrame = max(0, min(targetFrame, file.length - 1))
        
        file.framePosition = safeFrame
    }
}
