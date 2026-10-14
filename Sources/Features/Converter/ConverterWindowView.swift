import SwiftUI
import UniformTypeIdentifiers

struct ConverterWindowView: View {
    @State private var manager = AudioConverterManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar/Settings Area
            VStack(alignment: .leading, spacing: 16) {
                Text("Lossless Audio Converter")
                    .font(.headline)
                
                HStack(spacing: 24) {
                    VStack(alignment: .leading) {
                        Text("Output Format:")
                            .font(.subheadline)
                        Picker("", selection: $manager.settings.outputFormat) {
                            ForEach(ConversionOutputFormat.allCases) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Sample Rate:")
                            .font(.subheadline)
                        Picker("", selection: $manager.settings.sampleRate) {
                            ForEach(ConversionSampleRate.allCases) { sr in
                                Text(sr.displayName).tag(sr)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Bit Depth:")
                            .font(.subheadline)
                        Picker("", selection: $manager.settings.bitDepth) {
                            ForEach(ConversionBitDepth.allCases) { bd in
                                Text(bd.displayName).tag(bd)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Processing:")
                            .font(.subheadline)
                        Toggle("Enhance Audio", isOn: $manager.settings.applyEnhancement)
                            .padding(.top, 4)
                    }
                }
                
                HStack {
                    Text("Output Folder:")
                    if let folder = manager.settings.outputFolder {
                        Text(folder.lastPathComponent)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not selected")
                            .foregroundStyle(.secondary)
                    }
                    Button("Choose...") {
                        selectOutputFolder()
                    }
                }
            }
            .padding()
            .background(.windowBackground)
            
            if manager.hasLossyJobs {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Converting a lossy file to lossless keeps the same audio quality. It will not restore lost detail, and the file will be larger.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
                .background(.yellow.opacity(0.1))
            }
            
            Divider()
            
            // Queue Area
            List {
                if manager.jobs.isEmpty {
                    Text("Drag and drop audio files here to convert")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else {
                    ForEach(manager.jobs) { job in
                        HStack {
                            VStack(alignment: .leading) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(job.sourceURL.lastPathComponent)
                                        .lineLimit(1)
                                    if job.sizeEstimateBytes > 0 {
                                        Text("~" + formatBytes(job.sizeEstimateBytes))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if job.isSourceLossy {
                                        Text("Lossy Source")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(.orange.opacity(0.2))
                                            .foregroundStyle(.orange)
                                            .cornerRadius(4)
                                    }
                                }
                                if job.status == .failed, let error = job.errorMessage {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            if job.status == .processing {
                                ProgressView(value: job.progress, total: 1.0)
                                    .frame(width: 100)
                            } else {
                                Text(statusText(for: job.status))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Button {
                                manager.removeJob(id: job.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
                return true
            }
            
            Divider()
            
            // Bottom Action Bar
            HStack {
                Button("Clear Completed") {
                    manager.clearCompleted()
                }
                .disabled(manager.isProcessing)
                
                Spacer()
                
                if manager.isProcessing {
                    Button("Cancel") {
                        manager.cancelAll()
                    }
                } else {
                    Button("Start Conversion") {
                        manager.startProcessing()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.jobs.isEmpty || manager.settings.outputFolder == nil)
                }
            }
            .padding()
            .background(.windowBackground)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private func statusText(for status: ConversionJob.JobStatus) -> String {
        switch status {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .completed: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            manager.settings.outputFolder = panel.url
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        self.manager.addFiles([url])
                    }
                }
                group.leave()
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
