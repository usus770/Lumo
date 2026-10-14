@preconcurrency import AVFoundation
@preconcurrency import Combine

/// Core audio engine that wraps AVAudioEngine.
/// Runs as an actor to ensure thread-safe audio graph mutation.
actor AudioEngine {
    static let shared = AudioEngine()

    nonisolated let engine      = AVAudioEngine()
    nonisolated let playerNode  = AVAudioPlayerNode()
    nonisolated let eqNode      = AVAudioUnitEQ(numberOfBands: 10)
    nonisolated let timePitch   = AVAudioUnitTimePitch()  // playback speed
    
    // Enhancement node
    nonisolated var enhancerNode: AVAudioNode {
        AudioEnhancementManager.shared.activeEnhancer.processingNode
    }

    private var currentDecoder: AudioDecoder?
    private var isPlaying = false

    /// A subject that ticks periodically with the current playback time
    nonisolated let timeSubject = PassthroughSubject<TimeInterval, Never>()
    nonisolated var timePublisher: AnyPublisher<TimeInterval, Never> {
        timeSubject.eraseToAnyPublisher()
    }

    private var playbackTimerTask: Task<Void, Never>?

    private var audioTimeAtStart: AVAudioTime?
    private var framePositionAtStart: AVAudioFramePosition = 0
    private var currentSampleRate: Double = 44100

    /// Incremented on every load/seek to cancel stale buffer completions.
    private var bufferGeneration: Int = 0

    // MARK: - Crossfade / gapless
    private var crossfadeDuration: Double = 0       // seconds; 0 = gapless, no fade
    private var nextTrackURL: URL?                  // pre-loaded for gapless/crossfade
    
    // Visualizer tap
    private var visualizerTapInstalled = false

    private init() {
        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.attach(timePitch)
        engine.attach(enhancerNode)

        // Initial graph: playerNode → eqNode → enhancerNode → timePitch → mainMixer
        let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.connect(playerNode, to: eqNode,     format: defaultFormat)
        engine.connect(eqNode,     to: enhancerNode, format: defaultFormat)
        engine.connect(enhancerNode, to: timePitch,  format: defaultFormat)
        engine.connect(timePitch,  to: engine.mainMixerNode, format: defaultFormat)

        // Default EQ: all bands flat (nonisolated — operates directly on nonisolated eqNode)
        let freqs: [Float] = AppConstants.EQ.bandFrequencies
        for (i, band) in eqNode.bands.enumerated() {
            band.filterType  = .parametric
            band.frequency   = freqs[i]
            band.bandwidth   = AppConstants.EQ.defaultBandwidth
            band.gain        = 0
            band.bypass      = false
        }

        do {
            try engine.start()
        } catch {
            print("Failed to start AVAudioEngine: \(error)")
        }
        
        Task {
            await self.applyEnhancementState()
        }
        
        NotificationCenter.default.addObserver(forName: .enhancementStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task {
                await self?.applyEnhancementState()
            }
        }
    }
    
    private func applyEnhancementState() {
        if let distortion = enhancerNode as? AVAudioUnitEffect {
            distortion.bypass = !AudioEnhancementManager.shared.isEnabled
        }
    }


    // MARK: - EQ

    /// Enable/disable EQ and set per-band gains (dB).
    func setEQ(enabled: Bool, gains: [Float]) {
        eqNode.bypass = !enabled
        for (i, band) in eqNode.bands.enumerated() {
            band.gain = i < gains.count ? gains[i] : 0
        }
    }

    // MARK: - Playback speed

    func setPlaybackRate(_ rate: Float) {
        timePitch.rate  = rate
        timePitch.pitch = 0          // keep pitch constant (time-stretch only)
    }

    // MARK: - Crossfade

    func setCrossfadeDuration(_ seconds: Double) {
        crossfadeDuration = max(0, min(seconds, AppConstants.Playback.maxCrossfadeDuration))
    }

    // MARK: - Load

    func load(url: URL) throws {
        playerNode.stop()
        bufferGeneration &+= 1
        let generation = bufferGeneration

        var decoder: AudioDecoder = try AudioDecoderFactory.decoder(for: url)
        do {
            try decoder.open(url: url)
        } catch {
            print("Primary decoder failed (\(url.lastPathComponent)): \(error). Trying FallbackDecoder…")
            if !(decoder is FallbackDecoder) {
                let fallback = FallbackDecoder()
                try fallback.open(url: url)
                decoder = fallback
            } else {
                throw error
            }
        }
        currentDecoder = decoder

        let decoderFormat  = decoder.outputFormat
        currentSampleRate  = decoderFormat.sampleRate

        reconnectGraph(format: decoderFormat)

        framePositionAtStart = 0
        audioTimeAtStart     = nil

        scheduleNextBuffer(generation: generation)
        scheduleNextBuffer(generation: generation)
    }

    // MARK: - Transport

    func play() {
        guard currentDecoder != nil else { return }
        
        if !engine.isRunning {
            do { try engine.start() } catch {
                print("Failed to restart AVAudioEngine: \(error)")
                return
            }
        }
        
        // Install visualizer tap when starting playback
        installVisualizerTap()
        
        playerNode.play()
        isPlaying        = true
        audioTimeAtStart = playerNode.lastRenderTime
        startTimer()
    }
    
    func pause() {
        playerNode.pause()
        isPlaying = false
        stopTimer()
        
        if let nodeTime   = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
            framePositionAtStart += playerTime.sampleTime
        }
        audioTimeAtStart = nil
        
        // Remove visualizer tap when pausing
        removeVisualizerTap()
    }

    func seek(to time: TimeInterval) {
        let wasPlaying = isPlaying
        if wasPlaying { pause() }

        bufferGeneration &+= 1
        let generation = bufferGeneration

        playerNode.stop()

        do {
            try currentDecoder?.seek(to: time)
            framePositionAtStart = AVAudioFramePosition(time * currentSampleRate)
            audioTimeAtStart     = nil

            scheduleNextBuffer(generation: generation)
            scheduleNextBuffer(generation: generation)

            if wasPlaying { play() } else { timeSubject.send(time) }
        } catch {
            print("Seek error: \(error)")
        }
    }

    func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
    }
    
    // MARK: - Visualizer
    
    /// Installs the visualizer tap on the main mixer node.
    func installVisualizerTap() {
        guard !visualizerTapInstalled else { return }
        
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            AudioVisualizer.shared.processBuffer(buffer)
        }
        visualizerTapInstalled = true
    }
    
    /// Removes the visualizer tap.
    func removeVisualizerTap() {
        guard visualizerTapInstalled else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        visualizerTapInstalled = false
    }

    // MARK: - Graph reconnection

    private func reconnectGraph(format: AVAudioFormat) {
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }

        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(eqNode)
        engine.disconnectNodeOutput(enhancerNode)
        engine.disconnectNodeOutput(timePitch)

        engine.connect(playerNode, to: eqNode,    format: format)
        engine.connect(eqNode,    to: enhancerNode,  format: format)
        engine.connect(enhancerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)

        if wasRunning {
            do { try engine.start() } catch {
                print("Failed to restart engine after reconnect: \(error)")
            }
        }
    }

    // MARK: - Buffering

    private func scheduleNextBuffer(generation: Int) {
        guard generation == bufferGeneration else { return }
        guard let decoder = currentDecoder   else { return }

        guard let buffer = try? decoder.readNextBuffer(), buffer.frameLength > 0 else {
            if isPlaying && generation == bufferGeneration {
                handleTrackEnd()
            }
            return
        }

        playerNode.scheduleBuffer(buffer) {
            Task { [weak self] in
                await self?.scheduleNextBuffer(generation: generation)
            }
        }
    }

    private func handleTrackEnd() {
        isPlaying = false
        stopTimer()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .trackDidEnd, object: nil)
        }
    }

    // MARK: - Playback timer

    private func startTimer() {
        playbackTimerTask?.cancel()
        playbackTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { break }
                await self?.reportTime()
            }
        }
    }

    private func stopTimer() {
        playbackTimerTask?.cancel()
        playbackTimerTask = nil
    }

    private func reportTime() {
        guard isPlaying,
              let nodeTime   = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }

        let frames      = framePositionAtStart + playerTime.sampleTime
        let currentTime = TimeInterval(frames) / currentSampleRate
        timeSubject.send(currentTime)
    }
}

extension Notification.Name {
    static let trackDidEnd = Notification.Name("trackDidEnd")
}
