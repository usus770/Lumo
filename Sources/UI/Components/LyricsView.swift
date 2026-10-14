import SwiftUI

/// Parses and displays synced lyrics (LRC format) with line-by-line highlighting,
/// binary-search tracking, offset stepper, script romanization, and manual paste support.
struct LyricsView: View {
    let lyricsText: String?
    let hasSyncedLyrics: Bool
    let currentTime: TimeInterval
    
    @State private var parsedLines: [LyricLine] = []
    @State private var currentLineIndex: Int = 0
    @State private var scriptMode: LyricsScriptMode = .original
    @State private var showingPasteSheet: Bool = false
    @State private var pastedText: String = ""
    @State private var hasNonLatin: Bool = false
    
    private var snapshot: NowPlayingSnapshot {
        NowPlayingSnapshot.shared
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Toolbar
            lyricsToolbar
            
            Divider()
                .opacity(0.15)
            
            // Content
            if snapshot.isFetchingLyrics {
                searchingView
            } else if let lyricsText = lyricsText, !lyricsText.isEmpty {
                if hasSyncedLyrics && !parsedLines.isEmpty {
                    syncedLyricsView
                } else {
                    plainLyricsView(lyricsText)
                }
            } else {
                emptyLyricsView
            }
        }
        .sheet(isPresented: $showingPasteSheet) {
            pasteLyricsSheet
        }
        .onChange(of: lyricsText) { _, newValue in
            if let text = newValue {
                parseLyrics(text)
            } else {
                parsedLines = []
                hasNonLatin = false
            }
        }
        .onChange(of: currentTime) { _, newTime in
            updateCurrentLine(for: newTime)
        }
        .onAppear {
            if let text = lyricsText {
                parseLyrics(text)
            }
        }
    }
    
    // MARK: - Toolbar / Controls
    
    private var lyricsToolbar: some View {
        HStack(spacing: 12) {
            // Source & Confidence status
            if let src = snapshot.lyricsSource {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("\(src)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LumoColors.textSecondary)
                }
            } else if snapshot.isFetchingLyrics {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Searching…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LumoColors.textTertiary)
                }
            }
            
            Spacer()
            
            // Romanization / Script toggle
            if hasNonLatin {
                HStack(spacing: 2) {
                    Button(action: { cycleScriptMode() }) {
                        HStack(spacing: 3) {
                            Text("Aa")
                                .font(.system(size: 11, weight: .bold))
                            Text(scriptMode.rawValue)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(LumoColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Lyrics Script: Original, Romanized, or Both")
                }
            }
            
            // Offset Stepper (±100ms)
            HStack(spacing: 4) {
                Button(action: {
                    adjustOffset(by: -0.1)
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(LumoColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .help("Sync 100ms earlier")
                
                let offsetMs = Int((snapshot.totalLyricsOffset * 1000).rounded())
                Text("\(offsetMs >= 0 ? "+" : "")\(offsetMs)ms")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(LumoColors.textSecondary)
                    .frame(minWidth: 46)
                
                Button(action: {
                    adjustOffset(by: +0.1)
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(LumoColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .help("Sync 100ms later")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Synced Lyrics View
    
    private var syncedLyricsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(parsedLines.enumerated()), id: \.element.id) { index, line in
                        VStack(alignment: .leading, spacing: 2) {
                            // Primary text
                            Text(lineText(for: line.text))
                                .font(.system(size: 16, weight: index == currentLineIndex ? .bold : .medium))
                                .foregroundStyle(
                                    index == currentLineIndex ? LumoColors.accent : LumoColors.textSecondary.opacity(0.85)
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // Secondary romanized text if mode is .both
                            if scriptMode == .both && Romanizer.hasNonLatinScript(text: line.text) {
                                Text(Romanizer.romanize(text: line.text))
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(
                                        index == currentLineIndex ? LumoColors.accent.opacity(0.7) : LumoColors.textTertiary
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .id(line.id)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            snapshot.seek(to: line.time)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: currentLineIndex) { _, newIndex in
                guard newIndex >= 0 && newIndex < parsedLines.count else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(parsedLines[newIndex].id, anchor: .center)
                }
            }
        }
    }
    
    // MARK: - Plain Lyrics View
    
    private func plainLyricsView(_ text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                let lines = text.components(separatedBy: .newlines)
                ForEach(lines.indices, id: \.self) { idx in
                    let l = lines[idx]
                    Text(lineText(for: l))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(LumoColors.textSecondary)
                    
                    if scriptMode == .both && Romanizer.hasNonLatinScript(text: l) {
                        Text(Romanizer.romanize(text: l))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(LumoColors.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
    
    // MARK: - Searching & Empty States
    
    private var searchingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("Searching for lyrics…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LumoColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyLyricsView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "quote.bubble")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(LumoColors.accent.opacity(0.4))
            
            Text("No Lyrics Found")
                .font(LumoFonts.headingMedium)
                .foregroundStyle(LumoColors.textPrimary)
            
            Text("Lyrics could not be found automatically.")
                .font(LumoFonts.bodySmall)
                .foregroundStyle(LumoColors.textTertiary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 10) {
                Button("Search Again") {
                    snapshot.refetchLyrics(forceRemote: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Paste Lyrics") {
                    showingPasteSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 4)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Sheet for Pasting Lyrics
    
    private var pasteLyricsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste Lyrics")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(LumoColors.textPrimary)
            
            Text("Paste plain text or synced LRC format with [mm:ss.xx] timestamps.")
                .font(.system(size: 12))
                .foregroundStyle(LumoColors.textSecondary)
            
            TextEditor(text: $pastedText)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(LumoColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(minHeight: 220)
            
            HStack {
                Button("Cancel") {
                    showingPasteSheet = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save Lyrics") {
                    savePastedLyrics()
                    showingPasteSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 360)
    }
    
    // MARK: - Helpers & Binary Search
    
    private func lineText(for raw: String) -> String {
        switch scriptMode {
        case .original, .both:
            return raw
        case .romanized:
            return Romanizer.hasNonLatinScript(text: raw) ? Romanizer.romanize(text: raw) : raw
        }
    }
    
    private func cycleScriptMode() {
        switch scriptMode {
        case .original: scriptMode = .romanized
        case .romanized: scriptMode = .both
        case .both: scriptMode = .original
        }
    }
    
    private func adjustOffset(by delta: TimeInterval) {
        let newOffset = snapshot.userLyricsOffset + delta
        snapshot.setUserLyricsOffset(newOffset)
    }
    
    private func parseLyrics(_ text: String) {
        let result = LyricsParser.parse(text)
        self.parsedLines = result.lines
        self.hasNonLatin = result.lines.contains { Romanizer.hasNonLatinScript(text: $0.text) }
        updateCurrentLine(for: currentTime)
    }
    
    /// Binary-search for the active line index
    private func updateCurrentLine(for time: TimeInterval) {
        guard !parsedLines.isEmpty else { return }
        let effectiveTime = snapshot.lyricsTime(at: ProcessInfo.processInfo.systemUptime)
        
        let newIndex = binarySearchActiveLine(for: effectiveTime)
        if newIndex != currentLineIndex && newIndex >= 0 && newIndex < parsedLines.count {
            currentLineIndex = newIndex
        }
    }
    
    private func binarySearchActiveLine(for time: TimeInterval) -> Int {
        guard !parsedLines.isEmpty else { return 0 }
        if time < parsedLines[0].time { return 0 }
        if time >= parsedLines.last!.time { return parsedLines.count - 1 }
        
        var low = 0
        var high = parsedLines.count - 1
        var best = 0
        
        while low <= high {
            let mid = (low + high) / 2
            if parsedLines[mid].time <= time {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }
    
    private func savePastedLyrics() {
        let clean = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let parsed = LyricsParser.parse(clean)
        snapshot.lyricsText = clean
        snapshot.hasSyncedLyrics = parsed.isSynced
        snapshot.lyricsSource = "User Pasted"
        self.parsedLines = parsed.lines
        self.hasNonLatin = parsed.lines.contains { Romanizer.hasNonLatinScript(text: $0.text) }
    }
}
