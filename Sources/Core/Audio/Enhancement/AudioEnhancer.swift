import AVFoundation
import CoreML

/// Protocol defining an audio enhancement processor.
protocol AudioEnhancer: Sendable {
    /// Offline processing: enhances a single buffer.
    func enhance(buffer: AVAudioPCMBuffer) async throws -> AVAudioPCMBuffer
    
    /// Real-time processing: returns an AVAudioNode that can be attached to an AVAudioEngine.
    var processingNode: AVAudioNode { get }
    
    /// Called when the engine format changes.
    func updateFormat(_ format: AVAudioFormat)
}

/// DSP-based harmonic exciter and upsampler.
final class DSPEnhancer: AudioEnhancer, @unchecked Sendable {
    
    private let distortionNode = AVAudioUnitDistortion()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 1)
    
    init() {
        // Configure as a subtle harmonic exciter
        distortionNode.loadFactoryPreset(.multiEcho1) // Just an example, normally we'd build a custom distortion curve
        distortionNode.preGain = -6.0
        distortionNode.wetDryMix = 15.0
        
        let filter = eqNode.bands[0]
        filter.filterType = .highShelf
        filter.frequency = 8000.0
        filter.gain = 3.0
        filter.bypass = false
    }
    
    var processingNode: AVAudioNode {
        // For simplicity, we just return the distortion node for real-time.
        // A true chain would wrap them in an audio unit or we just expose them.
        return distortionNode
    }
    
    func updateFormat(_ format: AVAudioFormat) {
        // Setup internal parameters if needed
    }
    
    func enhance(buffer: AVAudioPCMBuffer) async throws -> AVAudioPCMBuffer {
        // Offline processing:
        // Create a local node to avoid 'owningEngine' conflicts with the real-time engine.
        let offlineDistortion = AVAudioUnitDistortion()
        offlineDistortion.loadFactoryPreset(.multiEcho1)
        offlineDistortion.preGain = -6.0
        offlineDistortion.wetDryMix = 15.0
        
        let offlineEngine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        
        offlineEngine.attach(player)
        offlineEngine.attach(offlineDistortion)
        
        offlineEngine.connect(player, to: offlineDistortion, format: buffer.format)
        offlineEngine.connect(offlineDistortion, to: offlineEngine.mainMixerNode, format: buffer.format)
        
        try offlineEngine.enableManualRenderingMode(.offline, format: buffer.format, maximumFrameCount: buffer.frameCapacity)
        try offlineEngine.start()
        
        player.scheduleBuffer(buffer, completionHandler: nil)
        player.play()
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            throw NSError(domain: "DSPEnhancer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
        }
        
        let renderStatus = try offlineEngine.renderOffline(buffer.frameLength, to: outputBuffer)
        offlineEngine.stop()
        
        if renderStatus == .success {
            return outputBuffer
        } else {
            throw NSError(domain: "DSPEnhancer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to render offline"])
        }
    }
}

/// AI-based bandwidth extension.
final class CoreMLEnhancer: AudioEnhancer, @unchecked Sendable {
    private let dspFallback = DSPEnhancer()
    private var model: MLModel?
    
    init() {
        // Attempt to load user-supplied model
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lumoDir = appSupport.appendingPathComponent("Lumo")
        let modelURL = lumoDir.appendingPathComponent("BandwidthExtension.mlmodelc")
        
        if FileManager.default.fileExists(atPath: modelURL.path) {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all // Use Neural Engine if available
                self.model = try MLModel(contentsOf: modelURL, configuration: config)
            } catch {
                print("Failed to load Core ML model: \(error)")
            }
        }
    }
    
    var processingNode: AVAudioNode {
        // Real-time CoreML via AVAudioNode is difficult in Swift without AUv3 C++.
        // We fallback to DSP for real-time playback, or use an AVAudioSourceNode with a circular buffer.
        // For simplicity in this demo, we use the DSP node.
        return dspFallback.processingNode
    }
    
    func updateFormat(_ format: AVAudioFormat) {
        dspFallback.updateFormat(format)
    }
    
    func enhance(buffer: AVAudioPCMBuffer) async throws -> AVAudioPCMBuffer {
        guard let model = model else {
            // Fallback to DSP if no model is installed
            return try await dspFallback.enhance(buffer: buffer)
        }
        
        // Execute Core ML inference (placeholder logic)
        // Convert AVAudioPCMBuffer -> MLMultiArray -> CoreML -> MLMultiArray -> AVAudioPCMBuffer
        // This is a highly complex transformation depending on the model's IO.
        
        // Placeholder for compilation
        return try await dspFallback.enhance(buffer: buffer)
    }
}

/// Manager for the current active enhancer.
@Observable
final class AudioEnhancementManager: @unchecked Sendable {
    static let shared = AudioEnhancementManager()
    
    var isEnabled: Bool = false {
        didSet {
            // Notify AudioEngine to toggle bypass or reconnect graph
            NotificationCenter.default.post(name: .enhancementStateDidChange, object: nil)
        }
    }
    
    var useAIEnhancer: Bool = false
    
    let dspEnhancer = DSPEnhancer()
    let aiEnhancer = CoreMLEnhancer()
    
    var activeEnhancer: AudioEnhancer {
        useAIEnhancer ? aiEnhancer : dspEnhancer
    }
}

extension Notification.Name {
    static let enhancementStateDidChange = Notification.Name("enhancementStateDidChange")
}
