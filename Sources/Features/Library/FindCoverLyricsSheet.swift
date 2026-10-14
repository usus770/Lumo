import SwiftUI
import AppKit

/// Sheet for searching and applying manual or automatic cover art and lyrics for a specific song.
struct FindCoverLyricsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let track: Track
    var onSaved: (() -> Void)? = nil
    
    // Search fields
    @State private var searchQuery: String = ""
    @State private var rawTitle: String = ""
    @State private var pastedLink: String = ""
    
    // Results & Selection
    @State private var results: [MetadataSearchResult] = []
    @State private var selectedResult: MetadataSearchResult? = nil
    @State private var preview: MetadataFetcherCoordinator.CandidatePreview? = nil
    
    // UI States
    @State private var isLoading = false
    @State private var isPreviewLoading = false
    @State private var errorMessage: String? = nil
    @State private var isOffline = false
    
    // Active search / preview tasks for cancellation
    @State private var activeSearchTask: Task<Void, Never>? = nil
    @State private var activePreviewTask: Task<Void, Never>? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            
            HStack(spacing: 0) {
                // Left pane: search bar & results list
                VStack(spacing: 12) {
                    searchBarSection
                    linkPasteSection
                    Divider()
                    resultsListSection
                }
                .frame(width: 440)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Right pane: selected preview details
                VStack(spacing: 0) {
                    if let sel = selectedResult {
                        previewPane(for: sel)
                    } else {
                        emptyPreviewPlaceholder
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
            
            Divider()
            bottomButtonBar
        }
        .frame(width: 880, height: 620)
        .onAppear {
            setupInitialQuery()
            performSearch()
        }
        .onDisappear {
            cancelAllTasks()
        }
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Find Cover Art & Lyrics")
                    .font(LumoFonts.headingSmall)
                Text(track.displayTitle + " • " + track.displayArtist)
                    .font(LumoFonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                cancelAllTasks()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(LumoTheme.surface)
    }
    
    // MARK: - Search Inputs
    
    // MARK: - Search Inputs
    
    private var searchBarSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search title and artist...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if MetadataFetcherCoordinator.extractYouTubeVideoId(from: searchQuery) != nil {
                            handlePastedLink(input: searchQuery)
                        } else {
                            performSearch()
                        }
                    }
                    .contextMenu {
                        Button("Paste") {
                            if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                                searchQuery = clip
                                if MetadataFetcherCoordinator.extractYouTubeVideoId(from: clip) != nil {
                                    handlePastedLink(input: clip)
                                } else {
                                    performSearch()
                                }
                            }
                        }
                    }
                
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                        searchQuery = clip
                        if MetadataFetcherCoordinator.extractYouTubeVideoId(from: clip) != nil {
                            handlePastedLink(input: clip)
                        } else {
                            performSearch()
                        }
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Paste text or YouTube link from clipboard")
                
                Button("Search") {
                    if MetadataFetcherCoordinator.extractYouTubeVideoId(from: searchQuery) != nil {
                        handlePastedLink(input: searchQuery)
                    } else {
                        performSearch()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            
            if !rawTitle.isEmpty {
                Text("Original: \(rawTitle)")
                    .font(LumoFonts.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    private var linkPasteSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 13))
                
                TextField("Paste YouTube link (e.g. youtu.be/...)", text: $pastedLink)
                    .textFieldStyle(.plain)
                    .font(LumoFonts.bodySmall)
                    .onSubmit { handlePastedLink() }
                    .contextMenu {
                        Button("Paste") {
                            pasteLinkFromClipboard()
                        }
                    }
                
                if !pastedLink.isEmpty {
                    Button {
                        pastedLink = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    pasteLinkFromClipboard()
                } label: {
                    Label("Paste Link", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Paste YouTube link from clipboard and load exact match")
                
                if !pastedLink.isEmpty {
                    Button("Load") {
                        handlePastedLink()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(7)
            .background(Color(NSColor.textBackgroundColor).opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
            
            // Status detection hint
            if let vid = MetadataFetcherCoordinator.extractYouTubeVideoId(from: pastedLink) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Detected Video ID: \(vid) — Loading exact match...")
                        .foregroundStyle(.secondary)
                }
                .font(LumoFonts.micro)
                .padding(.horizontal, 4)
            } else if !pastedLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Could not detect video ID. Supported: youtube.com/watch?v=..., youtu.be/...")
                        .foregroundStyle(.secondary)
                }
                .font(LumoFonts.micro)
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .onChange(of: pastedLink) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, MetadataFetcherCoordinator.extractYouTubeVideoId(from: trimmed) != nil {
                handlePastedLink(input: trimmed)
            }
        }
    }
    
    private func pasteLinkFromClipboard() {
        if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
            pastedLink = clip
            handlePastedLink(input: clip)
        }
    }
    
    // MARK: - Results List
    
    private var resultsListSection: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Searching YouTube Music & catalog...")
                        .font(LumoFonts.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isOffline {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Network Unreachable")
                        .font(LumoFonts.headingSmall)
                    Text("Please check your internet connection and try again.")
                        .font(LumoFonts.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry Search") {
                        performSearch()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if let error = errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text("Search Failed")
                        .font(LumoFonts.headingSmall)
                    Text(error)
                        .font(LumoFonts.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        performSearch()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No Matches Found")
                        .font(LumoFonts.headingSmall)
                    Text("Try adjusting the search query or pasting a direct YouTube video link.")
                        .font(LumoFonts.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $selectedResult) {
                    ForEach(results) { res in
                        resultRow(res)
                            .tag(res)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
    
    private func resultRow(_ res: MetadataSearchResult) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            AsyncImage(url: URL(string: res.thumbnailURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    Color.secondary.opacity(0.15)
                        .overlay(Image(systemName: "music.note").font(.system(size: 14)).foregroundStyle(.secondary))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(res.title)
                    .font(LumoFonts.bodySmall.weight(.medium))
                    .lineLimit(1)
                
                Text(res.artist + (res.album.isEmpty ? "" : " • \(res.album)"))
                    .font(LumoFonts.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(res.formattedDuration)
                        .font(LumoFonts.micro)
                        .foregroundStyle(.tertiary)
                    
                    matchScoreBadge(score: res.matchScore, duration: res.duration)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedResult = res
            loadPreview(for: res)
        }
    }
    
    private func matchScoreBadge(score: Double, duration: TimeInterval) -> some View {
        let pct = Int((score * 100).rounded())
        let isStrongDuration = abs(track.duration - duration) <= 3.0 && track.duration > 0
        
        let color: Color
        let label: String
        
        if score >= 0.85 {
            color = .green
            label = isStrongDuration ? "\(pct)% Strong Match" : "\(pct)% Match"
        } else if score >= 0.60 {
            color = .orange
            label = "\(pct)% Match"
        } else {
            color = .secondary
            label = "\(pct)%"
        }
        
        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    
    // MARK: - Right Preview Pane
    
    private var emptyPreviewPlaceholder: some View {
        VStack(spacing: 12) {
            LumoMarkView(size: 64, opacity: 0.40, isAnimated: false)
            Text("Select a Result")
                .font(LumoFonts.headingSmall)
                .foregroundStyle(LumoTheme.textPrimary)
            Text("Choose a match from the left list to inspect high-resolution album art, metadata, and lyrics preview.")
                .font(LumoFonts.caption)
                .foregroundStyle(LumoTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func previewPane(for res: MetadataSearchResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header preview: Large artwork + Track Details
                HStack(alignment: .top, spacing: 18) {
                    // Large cover art preview
                    ZStack {
                        if let coverData = preview?.coverCandidate?.data,
                           let nsImage = NSImage(data: coverData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                        } else {
                            AsyncImage(url: URL(string: res.highResArtworkURL ?? res.thumbnailURL ?? "")) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable()
                                        .aspectRatio(1, contentMode: .fit)
                                default:
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.1))
                                        .overlay(ProgressView())
                                }
                            }
                        }
                    }
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    
                    // Metadata tags
                    VStack(alignment: .leading, spacing: 6) {
                        Text(res.title)
                            .font(LumoFonts.headingMedium)
                            .lineLimit(2)
                        
                        Text(res.artist)
                            .font(LumoFonts.bodyLarge.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                        
                        if !res.album.isEmpty {
                            Text(res.album)
                                .font(LumoFonts.bodyMedium)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        HStack(spacing: 8) {
                            Label(res.formattedDuration, systemImage: "clock")
                                .font(LumoFonts.caption)
                                .foregroundStyle(.secondary)
                            
                            if let cover = preview?.coverCandidate {
                                if cover.isVideoThumbnail {
                                    Text("Video Thumbnail")
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.yellow.opacity(0.2))
                                        .foregroundStyle(.yellow)
                                        .clipShape(Capsule())
                                } else {
                                    Text("Square Album Art")
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundStyle(.green)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    Spacer()
                }
                
                Divider()
                
                // Lyrics Preview Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Lyrics Preview")
                            .font(LumoFonts.headingSmall)
                        Spacer()
                        
                        if isPreviewLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if let lyrics = preview?.lyricsCandidate {
                            HStack(spacing: 6) {
                                if lyrics.isSynced {
                                    Label("Synced", systemImage: "waveform")
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.2))
                                        .foregroundStyle(.purple)
                                        .clipShape(Capsule())
                                } else {
                                    Label("Plain Text", systemImage: "text.alignleft")
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.2))
                                        .foregroundStyle(.secondary)
                                        .clipShape(Capsule())
                                }
                                
                                Text("via \(lyrics.source)")
                                    .font(LumoFonts.micro)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    if isPreviewLoading {
                        HStack {
                            Spacer()
                            ProgressView("Fetching lyrics from LRCLIB & YouTube Music...")
                                .font(LumoFonts.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 30)
                    } else if let lyrics = preview?.lyricsCandidate, !lyrics.lyricsText.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            let sampleLines = lyrics.lyricsText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(10)
                            ForEach(Array(sampleLines), id: \.self) { line in
                                Text(line)
                                    .font(LumoFonts.bodySmall)
                                    .foregroundStyle(line.hasPrefix("[") ? Color.accentColor.opacity(0.8) : Color.primary)
                            }
                            if lyrics.lyricsText.components(separatedBy: .newlines).count > 10 {
                                Text("...")
                                    .font(LumoFonts.bodySmall)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "text.badge.xmark")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                            Text("No lyrics available for this match")
                                .font(LumoFonts.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Bottom Actions
    
    private var bottomButtonBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                cancelAllTasks()
                dismiss()
            }
            .buttonStyle(.lumoSecondary)
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button("Apply Lyrics Only") {
                applySelection(cover: false, lyrics: true)
            }
            .buttonStyle(.lumoSecondary)
            .disabled(selectedResult == nil || preview?.lyricsCandidate == nil)
            
            Button("Apply Cover Only") {
                applySelection(cover: true, lyrics: false)
            }
            .buttonStyle(.lumoSecondary)
            .disabled(selectedResult == nil || preview?.coverCandidate == nil)
            
            Button("Apply") {
                applySelection(cover: true, lyrics: true)
            }
            .buttonStyle(.lumoPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedResult == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(LumoTheme.surface)
    }
    
    // MARK: - Action Methods
    
    private func setupInitialQuery() {
        let (clean, raw) = MetadataFetcherCoordinator.cleanSearchQuery(
            title: track.displayTitle,
            artist: track.displayArtist
        )
        self.searchQuery = clean
        self.rawTitle = raw
    }
    
    private func cancelAllTasks() {
        activeSearchTask?.cancel()
        activeSearchTask = nil
        activePreviewTask?.cancel()
        activePreviewTask = nil
    }
    
    private func performSearch() {
        cancelAllTasks()
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        isOffline = false
        selectedResult = nil
        preview = nil
        
        activeSearchTask = Task {
            // Enforce 15-second search timeout
            let hits = await MetadataFetcherCoordinator.shared.search(query: q, localTrack: track)
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                self.results = hits
                self.isLoading = false
                if let first = hits.first {
                    self.selectedResult = first
                    self.loadPreview(for: first)
                }
            }
        }
    }
    
    private func handlePastedLink(input: String? = nil) {
        let linkToProcess = (input ?? pastedLink).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !linkToProcess.isEmpty else { return }
        guard let vid = MetadataFetcherCoordinator.extractYouTubeVideoId(from: linkToProcess) else {
            self.errorMessage = "Could not parse YouTube video ID from the provided link."
            return
        }
        
        cancelAllTasks()
        isLoading = true
        errorMessage = nil
        isOffline = false
        selectedResult = nil
        preview = nil
        
        activeSearchTask = Task {
            // 1. Direct lookup for this specific video ID (fast Innertube / oEmbed resolution)
            let directHit = try? await YouTubeMusicProvider.shared.lookupVideoId(vid)
            if Task.isCancelled { return }
            
            if var hit = directHit {
                hit.matchScore = 1.0
                hit.source = "YouTube Music (Exact Link)"
                
                // Also search via coordinator for catalog matches & LRCLIB lyrics using resolved title
                let (cleanedTitle, _) = MetadataFetcherCoordinator.cleanSearchQuery(title: hit.title, artist: hit.artist)
                let otherHits = await MetadataFetcherCoordinator.shared.search(query: cleanedTitle, localTrack: track)
                if Task.isCancelled { return }
                
                await MainActor.run {
                    var combined = [hit]
                    for other in otherHits where other.videoId != hit.videoId {
                        combined.append(other)
                    }
                    self.results = combined
                    self.selectedResult = hit
                    self.isLoading = false
                    self.loadPreview(for: hit)
                }
            } else {
                let hits = await MetadataFetcherCoordinator.shared.search(query: vid, localTrack: track)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.results = hits
                    self.isLoading = false
                    if let first = hits.first {
                        self.selectedResult = first
                        self.loadPreview(for: first)
                    } else {
                        self.errorMessage = "Could not find YouTube video for ID: \(vid)"
                    }
                }
            }
        }
    }
    
    private func loadPreview(for res: MetadataSearchResult) {
        activePreviewTask?.cancel()
        isPreviewLoading = true
        
        activePreviewTask = Task {
            let p = await MetadataFetcherCoordinator.shared.fetchPreview(for: res, localTrack: track)
            if Task.isCancelled { return }
            await MainActor.run {
                if self.selectedResult?.id == res.id {
                    self.preview = p
                    self.isPreviewLoading = false
                }
            }
        }
    }
    
    private func applySelection(cover: Bool, lyrics: Bool) {
        guard let sel = selectedResult else { return }
        let cCand = preview?.coverCandidate
        let lCand = preview?.lyricsCandidate
        
        Task {
            await MetadataFetcherCoordinator.shared.applyMatch(
                trackId: track.id,
                candidate: sel,
                coverCandidate: cover ? cCand : nil,
                lyricsCandidate: lyrics ? lCand : nil,
                applyCover: cover && cCand != nil,
                applyLyrics: lyrics && lCand != nil
            )
            
            await MainActor.run {
                onSaved?()
                dismiss()
            }
        }
    }
}
