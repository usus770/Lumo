import Foundation
import Accelerate
import AVFoundation

enum AudioQualityStatus: String, Codable, Sendable {
    case lossy = "Lossy"
    case trueLossless = "True Lossless"
    case suspectedFake = "Suspected Fake Lossless"
}

struct SpectrogramData: Sendable {
    let frequencies: [Float]
    let magnitudes: [Float]
}

actor QualityAnalyzer {
    static let shared = QualityAnalyzer()
    
    enum AnalyzerError: Error {
        case failedToOpen
        case noData
    }
    
    private init() {}
    
    /// Analyzes the track and returns the spectrogram and a quality status.
    func analyze(url: URL) async throws -> (SpectrogramData, AudioQualityStatus) {
        let decoder = try AudioDecoderFactory.decoder(for: url)
        try decoder.open(url: url)
        
        // Seek to 1/3 of the track to avoid silence at the beginning
        let duration = decoder.duration
        if duration > 10 {
            try? decoder.seek(to: duration / 3.0)
        }
        
        let sampleRate = Float(decoder.outputFormat.sampleRate)
        
        // We'll read ~1 second of audio
        var totalFrames: AVAudioFrameCount = 0
        let targetFrames = AVAudioFrameCount(sampleRate)
        
        var allData: [Float] = []
        
        while totalFrames < targetFrames, let buffer = try decoder.readNextBuffer() {
            let frames = buffer.frameLength
            if let floatData = buffer.floatChannelData {
                let channelData = floatData[0] // just analyze left channel
                let bufferData = Array(UnsafeBufferPointer(start: channelData, count: Int(frames)))
                allData.append(contentsOf: bufferData)
            }
            totalFrames += frames
        }
        
        guard !allData.isEmpty else {
            throw AnalyzerError.noData
        }
        
        // Perform FFT using Accelerate
        let frameCount = allData.count
        let log2n = vDSP_Length(log2(Float(frameCount)))
        let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        let n = 1 << log2n
        let halfN = n / 2
        
        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)
        
        var magnitudes = [Float](repeating: 0, count: halfN)
        var frequencies = [Float](repeating: 0, count: halfN)
        
        // Apply Hann window
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var windowedData = [Float](repeating: 0, count: n)
        vDSP_vmul(allData, 1, window, 1, &windowedData, 1, vDSP_Length(n))
        
        windowedData.withUnsafeBufferPointer { ptr in
            realp.withUnsafeMutableBufferPointer { realPtr in
                imagp.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    
                    ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                    
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                    
                    // Calculate magnitudes
                    vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))
                }
            }
        }
        
        // Convert to dB and calculate frequencies
        var dbMagnitudes = [Float](repeating: 0, count: halfN)
        var reference: Float = 1.0
        vDSP_vdbcon(magnitudes, 1, &reference, &dbMagnitudes, 1, vDSP_Length(halfN), 0)
        
        let nyquist = sampleRate / 2.0
        for i in 0..<halfN {
            frequencies[i] = Float(i) * (nyquist / Float(halfN))
        }
        
        let spectrogram = SpectrogramData(frequencies: frequencies, magnitudes: dbMagnitudes)
        let status = determineStatus(url: url, frequencies: frequencies, magnitudes: dbMagnitudes, nyquist: nyquist)
        
        return (spectrogram, status)
    }
    
    private func determineStatus(url: URL, frequencies: [Float], magnitudes: [Float], nyquist: Float) -> AudioQualityStatus {
        let ext = url.pathExtension.lowercased()
        let lossyExts = ["mp3", "aac", "ogg", "opus", "wma", "m4a"] // Note: m4a can be ALAC but we'll assume lossy for extension check, verify below if ALAC.
        
        var isLossyContainer = lossyExts.contains(ext)
        if ext == "m4a" {
            // Very naive check, normally we read AVAsset tracks to check for ALAC vs AAC
            // We'll leave it as lossyContainer for simplicity unless we do deeper AVAsset probing
            let asset = AVAsset(url: url)
            if let track = asset.tracks(withMediaType: .audio).first {
                let formatDescs = track.formatDescriptions as! [CMAudioFormatDescription]
                if let desc = formatDescs.first, let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                    if asbd.pointee.mFormatID == kAudioFormatAppleLossless {
                        isLossyContainer = false
                    }
                }
            }
        }
        
        if isLossyContainer {
            return .lossy
        }
        
        // It's in a lossless container (FLAC, ALAC, WAV). Check for fake lossless.
        // A fake lossless typically has a hard cutoff around 16kHz - 20kHz
        let noiseFloor: Float = -80.0
        var maxFreqWithEnergy: Float = 0
        
        for i in (0..<magnitudes.count).reversed() {
            if magnitudes[i] > noiseFloor {
                maxFreqWithEnergy = frequencies[i]
                break
            }
        }
        
        // If sample rate is 44.1kHz, nyquist is 22.05kHz.
        // MP3 128kbps cuts off at 16kHz. 320kbps cuts off at 20kHz.
        if maxFreqWithEnergy > 0 && maxFreqWithEnergy < 21000 && nyquist >= 22050 {
            // Could be fake lossless
            return .suspectedFake
        }
        
        return .trueLossless
    }
}
