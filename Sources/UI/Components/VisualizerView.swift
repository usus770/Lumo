import SwiftUI
import Accelerate
import AVFoundation
import Combine

/// Audio visualizer using AVAudioEngine tap and Accelerate FFT.
/// Shows frequency spectrum bars that animate to the music.
struct VisualizerView: View {
    @State private var visualizer = AudioVisualizer.shared
    @State private var spectrumData: [Float] = Array(repeating: 0, count: 32)
    
    var body: some View {
        GeometryReader { geometry in
            let barCount = 32
            let barWidth = (geometry.size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)
            let maxHeight = geometry.size.height
            
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let magnitude = index < spectrumData.count ? spectrumData[index] : 0
                    let barHeight = max(2, CGFloat(magnitude) * maxHeight)
                    
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    LumoColors.accent,
                                    LumoColors.accentSecondary
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: barWidth, height: barHeight)
                        .animation(
                            .spring(response: 0.15, dampingFraction: 0.7),
                            value: magnitude
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Start observing the visualizer data
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                self.spectrumData = visualizer.spectrumData
            }
        }
    }
}

/// Real-time audio visualizer that connects to AudioEngine
@Observable
final class AudioVisualizer: @unchecked Sendable {
    static let shared = AudioVisualizer()
    
    // FFT setup using Accelerate
    private var fftSetup: FFTSetup?
    private var realBuffer: [Float] = []
    private var imagBuffer: [Float] = []
    private var magnitudes: [Float] = []
    private var window: [Float] = []
    private let bufferSize = 1024
    private let barCount = 32
    
    var spectrumData: [Float] = Array(repeating: 0, count: 32)
    private var tapInstalled = false
    
    private init() {
        setupFFT()
    }
    
    private func setupFFT() {
        let log2n = vDSP_Length(log2(Float(bufferSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        
        realBuffer = [Float](repeating: 0, count: bufferSize)
        imagBuffer = [Float](repeating: 0, count: bufferSize)
        magnitudes = [Float](repeating: 0, count: bufferSize / 2)
        
        // Pre-compute Hann window
        window = [Float](repeating: 0, count: bufferSize)
        vDSP_hann_window(&window, vDSP_Length(bufferSize), Int32(vDSP_HANN_NORM))
    }
    
    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }
    
    /// Call this to install the tap on the audio engine
    func installTap(on engine: AVAudioEngine) {
        guard !tapInstalled else { return }
        
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }
        tapInstalled = true
    }
    
    func removeTap(from engine: AVAudioEngine) {
        engine.mainMixerNode.removeTap(onBus: 0)
        tapInstalled = false
    }
    
    func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData,
              let fftSetup = fftSetup else { return }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Mix down to mono and copy to real buffer
        for i in 0..<min(frameLength, bufferSize) {
            var sum: Float = 0
            for ch in 0..<channelCount {
                sum += channelData[ch][i]
            }
            realBuffer[i] = sum / Float(channelCount)
        }
        
        // Zero-pad if needed
        if frameLength < bufferSize {
            for i in frameLength..<bufferSize {
                realBuffer[i] = 0
            }
        }
        
        // Apply window function (Hann)
        vDSP_vmul(realBuffer, 1, window, 1, &realBuffer, 1, vDSP_Length(bufferSize))
        
        // Clear imaginary buffer
        for i in 0..<bufferSize {
            imagBuffer[i] = 0
        }
        
        // Perform FFT - use withUnsafeMutableBufferPointer to avoid lifetime issues
        realBuffer.withUnsafeMutableBufferPointer { realPtr in
            imagBuffer.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(fftSetup, &splitComplex, 1, vDSP_Length(log2(Float(bufferSize))), FFTDirection(FFT_FORWARD))
                
                // Calculate magnitudes
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(bufferSize / 2))
            }
        }
        
        // Convert to dB and normalize (amplitude to dB: 20*log10)
        var dbMagnitudes = [Float](repeating: 0, count: magnitudes.count)
        for i in 0..<magnitudes.count {
            // 20 * log10(magnitude) for amplitude
            if magnitudes[i] > 0 {
                dbMagnitudes[i] = 20 * log10(magnitudes[i])
            } else {
                dbMagnitudes[i] = -80  // Floor at -80 dB
            }
        }
        
        // Average into barCount bins
        var result = [Float](repeating: 0, count: barCount)
        let binsPerBar = max(1, magnitudes.count / barCount)
        
        for bar in 0..<barCount {
            let start = bar * binsPerBar
            let end = min(start + binsPerBar, magnitudes.count)
            let slice = Array(dbMagnitudes[start..<end])
            
            // Average and normalize (-80dB to 0dB -> 0.0 to 1.0)
            let avg = slice.reduce(0, +) / Float(slice.count)
            let normalized = max(0, min(1, (avg + 80) / 80))
            result[bar] = normalized
        }
        
        // Smooth the result
        DispatchQueue.main.async {
            self.spectrumData = self.spectrumData.enumerated().map { index, oldValue in
                let target = index < result.count ? result[index] : 0
                return oldValue + (target - oldValue) * 0.3
            }
        }
    }
}