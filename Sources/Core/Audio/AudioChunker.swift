import Foundation
@preconcurrency import AVFoundation

public struct AudioChunker {
    /// Extracts a chunk from the given AVAsset, downsamples to 16kHz Mono, and returns as a 16-bit WAV Data.
    public static func extractWAV(from url: URL, startTime: TimeInterval, duration: TimeInterval) async throws -> Data {
        let asset = AVURLAsset(url: url)
        
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "AudioChunker", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio track found"])
        }
        
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let firstDesc = formatDescriptions.first else {
            throw NSError(domain: "AudioChunker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get audio format"])
        }
        let srcFormat = AVAudioFormat(cmAudioFormatDescription: firstDesc)
        
        guard let destFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 16000,
                                             channels: 1,
                                             interleaved: false) else {
            throw NSError(domain: "AudioChunker", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create dest format"])
        }
        
        let assetReader = try AVAssetReader(asset: asset)
        let timeRange = CMTimeRange(start: CMTime(seconds: startTime, preferredTimescale: 600),
                                    duration: CMTime(seconds: duration, preferredTimescale: 600))
        assetReader.timeRange = timeRange
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: srcFormat.sampleRate,
            AVNumberOfChannelsKey: srcFormat.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        assetReader.add(trackOutput)
        
        guard let pcmFormat = AVAudioFormat(standardFormatWithSampleRate: srcFormat.sampleRate, channels: srcFormat.channelCount),
              let converter = AVAudioConverter(from: pcmFormat, to: destFormat) else {
            throw NSError(domain: "AudioChunker", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create converter"])
        }
        
        assetReader.startReading()
        
        var audioData = Data()
        
        while assetReader.status == .reading {
            if let sampleBuffer = trackOutput.copyNextSampleBuffer(),
               let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                
                let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
                let localPcmBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(numSamples))!
                localPcmBuffer.frameLength = localPcmBuffer.frameCapacity
                
                // Copy data from block buffer to PCM buffer
                var lengthAtOffset = 0
                var totalLength = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
                
                if let dataPointer = dataPointer, let channelData = localPcmBuffer.floatChannelData {
                    let ptr = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
                    let channelCount = Int(pcmFormat.channelCount)
                    for frame in 0..<Int(numSamples) {
                        for channel in 0..<channelCount {
                            channelData[channel][frame] = ptr[frame * channelCount + channel]
                        }
                    }
                }
                
                // Convert to 16kHz mono
                let outFrameCapacity = AVAudioFrameCount((Double(numSamples) / srcFormat.sampleRate) * 16000.0)
                let outBuffer = AVAudioPCMBuffer(pcmFormat: destFormat, frameCapacity: outFrameCapacity)!
                
                var error: NSError?
                final class State: @unchecked Sendable { var hasData = true }
                let state = State()
                
                converter.convert(to: outBuffer, error: &error, withInputFrom: { inNumPackets, outStatus in
                    if state.hasData {
                        outStatus.pointee = .haveData
                        state.hasData = false
                        return localPcmBuffer
                    } else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                })
                
                if let err = error {
                    print("Conversion error: \(err)")
                    continue
                }
                
                // Append 16-bit data
                if let int16Data = outBuffer.int16ChannelData {
                    let ptr = int16Data[0]
                    audioData.append(UnsafeBufferPointer(start: ptr, count: Int(outBuffer.frameLength)))
                }
            } else {
                break
            }
        }
        
        if assetReader.status == .failed {
            if let error = assetReader.error { throw error }
        }
        
        return createWAV(from: audioData, sampleRate: 16000, channels: 1)
    }
    
    private static func createWAV(from pcmData: Data, sampleRate: Int, channels: Int) -> Data {
        let byteRate = sampleRate * channels * 2
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: Int32(pcmData.count + 36)) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: Int32(16)) { Array($0) }) // Subchunk1Size
        header.append(contentsOf: withUnsafeBytes(of: Int16(1)) { Array($0) }) // AudioFormat (PCM)
        header.append(contentsOf: withUnsafeBytes(of: Int16(channels)) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate)) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: Int32(byteRate)) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: Int16(channels * 2)) { Array($0) }) // BlockAlign
        header.append(contentsOf: withUnsafeBytes(of: Int16(16)) { Array($0) }) // BitsPerSample
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: Int32(pcmData.count)) { Array($0) })
        header.append(pcmData)
        return header
    }
}
