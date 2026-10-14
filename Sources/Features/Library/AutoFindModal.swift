import SwiftUI

/// Modal sheet for configuring and monitoring automatic background cover & lyrics resolution across songs.
struct AutoFindModal: View {
    @Environment(\.dismiss) private var dismiss
    
    var selectedTrackIds: Set<UUID> = []
    var onFinished: (() -> Void)? = nil
    
    @State private var scope: AutoFindScope = .missingLyrics
    @State private var isRunning = false
    @State private var progress = AutoFindProgress()
    @State private var autoTask: Task<Void, Never>? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            headerView
            
            if !isRunning && !progress.isFinished {
                configurationView
            } else {
                progressView
            }
            
            Divider()
            
            actionButtonsView
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            if !selectedTrackIds.isEmpty {
                scope = .selected
            }
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars.inverse")
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Find Covers & Lyrics")
                    .font(LumoFonts.headingMedium)
                Text("Automatically match metadata, download high-res artwork, and fetch synchronized lyrics.")
                    .font(LumoFonts.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
    
    private var configurationView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Select Search Scope:")
                .font(LumoFonts.bodySmall.weight(.medium))
            
            Picker("Scope", selection: $scope) {
                if !selectedTrackIds.isEmpty {
                    Text("Selected Songs (\(selectedTrackIds.count))").tag(AutoFindScope.selected)
                }
                Text("Songs Missing Cover").tag(AutoFindScope.missingCover)
                Text("Songs Missing Lyrics").tag(AutoFindScope.missingLyrics)
                Text("All Songs in Library").tag(AutoFindScope.all)
            }
            .pickerStyle(.radioGroup)
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Confidence threshold >= 85%: Applied automatically", systemImage: "checkmark.seal")
                    .font(LumoFonts.caption)
                    .foregroundStyle(.green)
                Label("Confidence 60%–84%: Saved to 'Needs Review' tab for 1-click confirmation", systemImage: "hand.raised")
                    .font(LumoFonts.caption)
                    .foregroundStyle(.orange)
                Label("Manual choices are locked and will never be overwritten", systemImage: "lock.shield")
                    .font(LumoFonts.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var progressView: some View {
        VStack(spacing: 16) {
            // Counter & current song
            VStack(spacing: 4) {
                HStack {
                    Text(progress.isFinished ? "Batch Complete!" : (progress.isPaused ? "Paused" : "Analyzing Library..."))
                        .font(LumoFonts.bodyLarge.weight(.semibold))
                    Spacer()
                    Text("\(progress.processed) / \(progress.total)")
                        .font(LumoFonts.bodyMedium.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                
                ProgressView(value: progress.fractionCompleted)
                    .tint(progress.isFinished ? .green : .accentColor)
                
                if !progress.currentTrackTitle.isEmpty && !progress.isFinished {
                    Text("Processing: \(progress.currentTrackTitle)")
                        .font(LumoFonts.micro)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            // Statistics Grid
            HStack(spacing: 20) {
                statBox(title: "Applied", count: progress.appliedCount, color: .green)
                statBox(title: "Needs Review", count: progress.needsReviewCount, color: .orange)
                statBox(title: "No Match", count: progress.noMatchCount, color: .secondary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func statBox(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(LumoFonts.micro)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var actionButtonsView: some View {
        HStack {
            if isRunning {
                Button(progress.isPaused ? "Resume" : "Pause") {
                    if progress.isPaused {
                        progress.isPaused = false
                        Task { await MetadataFetcherCoordinator.shared.resumeAutoFind() }
                    } else {
                        progress.isPaused = true
                        Task { await MetadataFetcherCoordinator.shared.pauseAutoFind() }
                    }
                }
                .controlSize(.small)
                
                Button("Cancel Job") {
                    Task {
                        await MetadataFetcherCoordinator.shared.cancelAutoFind()
                        await MainActor.run {
                            isRunning = false
                            progress.isCancelled = true
                        }
                    }
                }
                .controlSize(.small)
                
                Spacer()
            } else if progress.isFinished || progress.isCancelled {
                Spacer()
                Button("Done") {
                    onFinished?()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Start Auto-Find") {
                    startJob()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    private func startJob() {
        isRunning = true
        autoTask = Task {
            await MetadataFetcherCoordinator.shared.autoFindMissing(
                scope: scope,
                selectedIds: selectedTrackIds
            ) { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                    if newProgress.isFinished || newProgress.isCancelled {
                        self.isRunning = false
                    }
                }
            }
        }
    }
}
