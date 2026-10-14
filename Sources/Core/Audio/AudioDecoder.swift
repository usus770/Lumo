import AVFoundation
import CoreAudio

/// Protocol defining the interface for an audio decoder.
protocol AudioDecoder: Sendable {
    /// Attempts to open the file and prepare for decoding.
    func open(url: URL) throws
    
    /// The total duration of the opened file.
    var duration: TimeInterval { get }
    
    /// Reads the next buffer of audio data.
    /// Returns nil when end of file is reached.
    func readNextBuffer() throws -> AVAudioPCMBuffer?
    
    /// Seeks to the specified time.
    func seek(to time: TimeInterval) throws
    
    /// The audio format being decoded into (typically standard PCM).
    var outputFormat: AVAudioFormat { get }
}

/// Factory to select the appropriate decoder.
enum AudioDecoderFactory {
    static func decoder(for url: URL) throws -> AudioDecoder {
        let ext = url.pathExtension.lowercased()
        if AppConstants.Library.nativeFormats.contains(ext) {
            return NativeDecoder()
        } else {
            return FallbackDecoder()
        }
    }
}
