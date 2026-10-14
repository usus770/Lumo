import Foundation
import AVFoundation

/// Core logic for converting a single audio file.
actor AudioConverterEngine {
    
    enum ConverterError: Error, LocalizedError {
        case outputFolderNotSpecified
        case destinationExists
        case unableToCreateOutputFormat
        case converterSetupFailed
        
        var errorDescription: String? {
            switch self {
            case .outputFolderNotSpecified: return "Output folder not specified."
            case .destinationExists: return "Destination file already exists."
            case .unableToCreateOutputFormat: return "Unable to create target output format."
            case .converterSetupFailed: return "Failed to setup AVAudioConverter."
            }
        }
    }
    
    func convert(
        job: ConversionJob,
        settings: ConversionSettings,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        // 1. Determine output URL
        let outputURL = try resolveOutputURL(job: job, settings: settings)
        
        // 2. Open Decoder
        var decoder = try AudioDecoderFactory.decoder(for: job.sourceURL)
        do {
            try decoder.open(url: job.sourceURL)
        } catch {
            // NativeDecoder failed (e.g., YouTube DASH m4a files). Let's try FFmpeg fallback!
            print("Decoder failed to open natively (\(error)). Trying FallbackDecoder...")
            decoder = FallbackDecoder()
            try decoder.open(url: job.sourceURL)
        }
        
        // 3. Setup output format
        let sourceFormat = decoder.outputFormat
        let targetSampleRate = settings.sampleRate == .keepOriginal ? sourceFormat.sampleRate : Double(settings.sampleRate.rawValue)
        let targetChannels = sourceFormat.channelCount
        
        var outSettings: [String: Any] = [
            AVFormatIDKey: settings.outputFormat.formatID,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: targetChannels
        ]
        
        let targetBitDepth = settings.bitDepth == .keepOriginal ? 16 : settings.bitDepth.rawValue // simplified, real implementation should read source bit depth if possible
        
        switch settings.outputFormat {
        case .wav, .aiff:
            outSettings[AVLinearPCMBitDepthKey] = targetBitDepth
            outSettings[AVLinearPCMIsFloatKey] = targetBitDepth == 32
            outSettings[AVLinearPCMIsBigEndianKey] = settings.outputFormat == .aiff
            outSettings[AVLinearPCMIsNonInterleaved] = false
        case .alac:
            // ALAC supports up to 32-bit integer, no float
            let clampedBitDepth = targetBitDepth > 32 ? 32 : targetBitDepth
            outSettings[AVEncoderBitDepthHintKey] = clampedBitDepth
        case .flac:
            // FLAC supports up to 24-bit integer, no float
            let clampedBitDepth = targetBitDepth > 24 ? 24 : targetBitDepth
            outSettings[AVEncoderBitDepthHintKey] = clampedBitDepth
        }
        
        print("Creating AVAudioFile for writing at \(outputURL)")
        print("outSettings: \(outSettings)")
        
        let outputFile: AVAudioFile
        let outputProcessingFormat: AVAudioFormat
        do {
            outputFile = try AVAudioFile(forWriting: outputURL, settings: outSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
            outputProcessingFormat = outputFile.processingFormat
        } catch {
            print("Failed to init AVAudioFile for writing: \(error)")
            throw error
        }
        
        // 4. Setup AVAudioConverter if format changes
        // 4. Setup AVAudioConverter if format changes
        var converter: AVAudioConverter? = nil
        if sourceFormat != outputProcessingFormat {
            print("Creating AVAudioConverter from \(sourceFormat) to \(outputProcessingFormat)")
            guard let conv = AVAudioConverter(from: sourceFormat, to: outputProcessingFormat) else {
                print("Failed to init AVAudioConverter")
                throw ConverterError.converterSetupFailed
            }
            conv.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            if settings.dither && targetBitDepth < 32 {
                conv.dither = true
            }
            converter = conv
        }
        
        // 5. Conversion Loop
        let totalDuration = decoder.duration
        var processedDuration: TimeInterval = 0
        
        while let inputBuffer = try decoder.readNextBuffer() {
            try Task.checkCancellation()
            
            var bufferToProcess = inputBuffer
            
            if settings.applyEnhancement {
                bufferToProcess = try await AudioEnhancementManager.shared.activeEnhancer.enhance(buffer: bufferToProcess)
            }
            
            // Peak detection and limiting can be inserted here
            // detectAndLimitPeaks(buffer: bufferToProcess)
            
            if let converter = converter {
                let frameCapacity = AVAudioFrameCount(Double(bufferToProcess.frameLength) * (targetSampleRate / sourceFormat.sampleRate))
                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputProcessingFormat, frameCapacity: frameCapacity) else {
                    continue
                }
                
                var error: NSError?
                let status = converter.convert(to: outputBuffer, error: &error) { packetCount, outStatus in
                    outStatus.pointee = .haveData
                    return bufferToProcess
                }
                
                if status == .error, let err = error {
                    throw err
                }
                
                if outputBuffer.frameLength > 0 {
                    do {
                        try outputFile.write(from: outputBuffer)
                    } catch {
                        print("Failed to write to outputFile from outputBuffer: \(error)")
                        throw error
                    }
                }
            } else {
                do {
                    try outputFile.write(from: bufferToProcess)
                } catch {
                    print("Failed to write to outputFile from bufferToProcess: \(error)")
                    throw error
                }
            }
            
            processedDuration += Double(bufferToProcess.frameLength) / sourceFormat.sampleRate
            if totalDuration > 0 {
                let progress = min(1.0, processedDuration / totalDuration)
                progressHandler(progress)
            }
        }
        
        progressHandler(1.0)
        return outputURL
    }
    
    private func resolveOutputURL(job: ConversionJob, settings: ConversionSettings) throws -> URL {
        guard let folder = settings.outputFolder else {
            throw ConverterError.outputFolderNotSpecified
        }
        
        var filename = settings.filenameTemplate
        let title = job.metadata?.title ?? job.sourceURL.deletingPathExtension().lastPathComponent
        let artist = job.metadata?.artist ?? "Unknown Artist"
        
        filename = filename.replacingOccurrences(of: "{title}", with: title)
        filename = filename.replacingOccurrences(of: "{artist}", with: artist)
        // Clean invalid characters
        filename = filename.replacingOccurrences(of: "/", with: "-")
        filename = filename.replacingOccurrences(of: ":", with: "-")
        
        let ext = settings.outputFormat.fileExtension
        var outputURL = folder.appendingPathComponent("\(filename).\(ext)")
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            switch settings.conflictResolution {
            case .skip:
                throw ConverterError.destinationExists
            case .overwrite:
                try? FileManager.default.removeItem(at: outputURL)
            case .rename:
                var counter = 2
                while FileManager.default.fileExists(atPath: outputURL.path) {
                    outputURL = folder.appendingPathComponent("\(filename) \(counter).\(ext)")
                    counter += 1
                }
            }
        }
        
        return outputURL
    }
}
