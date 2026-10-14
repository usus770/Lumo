import Foundation
import SwiftUI
import OSLog

@Observable
final class AudioConverterManager: @unchecked Sendable {
    static let shared = AudioConverterManager()
    
    var jobs: [ConversionJob] = []
    var settings = ConversionSettings()
    
    var isProcessing: Bool {
        jobs.contains(where: { $0.status == .processing })
    }
    
    var hasLossyJobs: Bool {
        jobs.contains(where: { $0.isSourceLossy && ($0.status == .pending || $0.status == .processing) })
    }
    
    private let engine = AudioConverterEngine()
    private var activeTask: Task<Void, Never>?
    
    private init() {}
    
    @MainActor
    func addFiles(_ urls: [URL]) {
        for url in urls {
            // Check if already in queue
            if jobs.contains(where: { $0.sourceURL == url }) { continue }
            
            let ext = url.pathExtension.lowercased()
            let isLossy = ["mp3", "aac", "m4a", "ogg", "opus", "wma"].contains(ext) 
            
            var job = ConversionJob(sourceURL: url, metadata: nil)
            job.isSourceLossy = isLossy
            jobs.append(job)
            
            // Asynchronously estimate size
            let jobId = job.id
            Task {
                if let size = await estimateSize(for: url, settings: settings) {
                    if let index = jobs.firstIndex(where: { $0.id == jobId }) {
                        jobs[index].sizeEstimateBytes = size
                    }
                }
            }
        }
    }
    
    private func estimateSize(for url: URL, settings: ConversionSettings) async -> Int64? {
        do {
            var decoder = try AudioDecoderFactory.decoder(for: url)
            do {
                try decoder.open(url: url)
            } catch {
                decoder = FallbackDecoder()
                try decoder.open(url: url)
            }
            let duration = decoder.duration
            let sampleRate = settings.sampleRate == .keepOriginal ? decoder.outputFormat.sampleRate : Double(settings.sampleRate.rawValue)
            let bitDepth = settings.bitDepth == .keepOriginal ? 16.0 : Double(settings.bitDepth.rawValue)
            let channels = Double(decoder.outputFormat.channelCount)
            
            var bytesPerSecond = (sampleRate * bitDepth * channels) / 8.0
            
            if settings.outputFormat == .flac || settings.outputFormat == .alac {
                bytesPerSecond *= 0.6 // rough 60% estimate for lossless compression
            }
            
            return Int64(bytesPerSecond * duration)
        } catch {
            return nil
        }
    }
    
    @MainActor
    func removeJob(id: UUID) {
        jobs.removeAll(where: { $0.id == id })
    }
    
    @MainActor
    func clearCompleted() {
        jobs.removeAll(where: { $0.status == .completed || $0.status == .cancelled || $0.status == .failed })
    }
    
    @MainActor
    func cancelAll() {
        activeTask?.cancel()
        for i in jobs.indices {
            if jobs[i].status == .pending || jobs[i].status == .processing {
                jobs[i].status = .cancelled
            }
        }
    }
    
    @MainActor
    func startProcessing() {
        guard !isProcessing else { return }
        
        activeTask = Task {
            await processQueue()
        }
    }
    
    private func processQueue() async {
        let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount
        
        await withTaskGroup(of: Void.self) { group in
            var runningTasks = 0
            
            for index in await MainActor.run(body: { jobs.indices }) {
                guard await MainActor.run(body: { jobs[index].status == .pending }) else { continue }
                
                if Task.isCancelled { break }
                
                if runningTasks >= maxConcurrent {
                    await group.next()
                    runningTasks -= 1
                }
                
                await MainActor.run {
                    jobs[index].status = .processing
                }
                
                group.addTask {
                    await self.processJob(at: index)
                }
                runningTasks += 1
            }
            
            // Wait for all remaining tasks
            for await _ in group {
                runningTasks -= 1
            }
        }
        
        await MainActor.run {
            self.activeTask = nil
        }
    }
    
    private func processJob(at index: Int) async {
        let job = await MainActor.run { jobs[index] }
        let currentSettings = await MainActor.run { settings }
        
        do {
            let outputURL = try await engine.convert(job: job, settings: currentSettings) { progress in
                Task { @MainActor in
                    if self.jobs.indices.contains(index) {
                        self.jobs[index].progress = progress
                    }
                }
            }
            
            await MainActor.run {
                if self.jobs.indices.contains(index) {
                    self.jobs[index].status = .completed
                    self.jobs[index].outputURL = outputURL
                    self.jobs[index].progress = 1.0
                }
            }
            
            // Handle replaceOriginal and addToLibrary here if needed
            if currentSettings.addToLibrary {
                Task {
                    await LibraryScanner.shared.scan(folderURL: outputURL)
                }
            }
            
        } catch {
            await MainActor.run {
                if self.jobs.indices.contains(index) {
                    if error is CancellationError {
                        self.jobs[index].status = .cancelled
                    } else {
                        self.jobs[index].status = .failed
                        self.jobs[index].errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
