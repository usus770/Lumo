import SwiftUI
import Charts

struct TrackInfoView: View {
    @State var track: Track
    @State private var isAnalyzing = false
    @State private var spectrogram: SpectrogramData?
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                ArtworkView(data: ArtworkCache.load(hash: track.artworkHash), fallbackTitle: track.displayTitle, size: 80, cornerRadius: 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.displayTitle)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                    Text(track.displayArtist)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(track.displayAlbum)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding()
            .background(.windowBackground)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Audio Properties
                    GroupBox("Audio Properties") {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                            GridRow {
                                Text("Codec / Ext").foregroundStyle(.secondary)
                                Text(track.fileExtension.uppercased())
                            }
                            GridRow {
                                Text("Bitrate").foregroundStyle(.secondary)
                                Text("\(track.bitrate) kbps")
                            }
                            GridRow {
                                Text("Sample Rate").foregroundStyle(.secondary)
                                Text("\(track.sampleRate) Hz")
                            }
                            GridRow {
                                Text("Bit Depth").foregroundStyle(.secondary)
                                Text("\(track.bitDepth)-bit")
                            }
                            GridRow {
                                Text("Channels").foregroundStyle(.secondary)
                                Text("\(track.channels)")
                            }
                            GridRow {
                                Text("File Size").foregroundStyle(.secondary)
                                Text(formatBytes(track.fileSize))
                            }
                            
                            if let status = track.qualityStatus {
                                GridRow {
                                    Text("Quality Assessment").foregroundStyle(.secondary)
                                    statusBadge(for: status)
                                }
                            }
                        }
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Spectrogram / Analysis
                    GroupBox("Quality Analyzer") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let spec = spectrogram {
                                Chart {
                                    ForEach(Array(zip(spec.frequencies, spec.magnitudes).enumerated()), id: \.offset) { index, data in
                                        LineMark(
                                            x: .value("Frequency", data.0),
                                            y: .value("Magnitude", data.1)
                                        )
                                        .foregroundStyle(.blue.opacity(0.8))
                                    }
                                }
                                .chartXScale(domain: 0...24000)
                                .chartYScale(domain: -100...0)
                                .chartXAxis {
                                    AxisMarks(values: [0, 5000, 10000, 15000, 20000, 24000]) { value in
                                        AxisGridLine()
                                        AxisTick()
                                        AxisValueLabel {
                                            if let intVal = value.as(Int.self) {
                                                Text("\(intVal / 1000) kHz")
                                            }
                                        }
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks(values: [-100, -80, -60, -40, -20, 0]) { value in
                                        AxisGridLine()
                                        AxisTick()
                                        AxisValueLabel {
                                            if let intVal = value.as(Int.self) {
                                                Text("\(intVal) dB")
                                            }
                                        }
                                    }
                                }
                                .frame(height: 200)
                                .padding(.top, 8)
                                
                            } else if isAnalyzing {
                                ProgressView("Analyzing Audio Frequencies...")
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .frame(height: 200)
                            } else {
                                Text("Run the analyzer to detect high-frequency cutoffs and identify upconverted lossy files.")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            if let err = errorMessage {
                                Text(err)
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                            
                            Button(isAnalyzing ? "Analyzing..." : "Run Quality Check") {
                                analyzeAudio()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isAnalyzing)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
    
    private func analyzeAudio() {
        isAnalyzing = true
        errorMessage = nil
        spectrogram = nil
        
        let url = URL(fileURLWithPath: track.filePath)
        
        Task {
            do {
                let (specData, status) = try await QualityAnalyzer.shared.analyze(url: url)
                await MainActor.run {
                    self.spectrogram = specData
                    self.track.qualityStatus = status
                    self.isAnalyzing = false
                    
                    // Persist the status in background
                    Task {
                        var allTracks = await PersistenceStore.shared.loadAll(Track.self)
                        if let idx = allTracks.firstIndex(where: { $0.id == track.id }) {
                            allTracks[idx].qualityStatus = status
                            try? await PersistenceStore.shared.saveAll(allTracks)
                            NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isAnalyzing = false
                }
            }
        }
    }
    
    @ViewBuilder
    private func statusBadge(for status: AudioQualityStatus) -> some View {
        HStack {
            Image(systemName: badgeIcon(for: status))
            Text(status.rawValue)
                .font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(badgeColor(for: status).opacity(0.2))
        .foregroundStyle(badgeColor(for: status))
        .cornerRadius(4)
    }
    
    private func badgeIcon(for status: AudioQualityStatus) -> String {
        switch status {
        case .lossy: return "waveform"
        case .trueLossless: return "checkmark.seal.fill"
        case .suspectedFake: return "exclamationmark.triangle.fill"
        }
    }
    
    private func badgeColor(for status: AudioQualityStatus) -> Color {
        switch status {
        case .lossy: return .orange
        case .trueLossless: return .green
        case .suspectedFake: return .red
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
