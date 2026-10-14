import SwiftUI

/// Queue and "Up Next" manager for Lumo iOS.
/// Allows drag-and-drop reordering ("one song over another"), swipe-to-delete,
/// direct jumping, and queue clearance.
public struct iOSQueueView: View {
    @ObservedObject private var playbackState = iOSPlaybackState.shared
    @ObservedObject private var audioEngine = iOSAudioEngine.shared
    @State private var editMode: EditMode = .inactive
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                LumoTheme.bg0.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Bar
                    headerBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    
                    List {
                        // MARK: - Now Playing Section
                        if let current = playbackState.currentTrack {
                            Section {
                                nowPlayingCard(track: current)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                            } header: {
                                Text("NOW PLAYING")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(LumoTheme.accentPink)
                            }
                        }
                        
                        // MARK: - Up Next Section
                        Section {
                            if playbackState.queue.isEmpty {
                                emptyQueueCard
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                            } else {
                                ForEach(Array(playbackState.queue.enumerated()), id: \.element.id) { index, track in
                                    queueRow(index: index, track: track)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                        .listRowBackground(LumoTheme.surface)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                withAnimation {
                                                    playbackState.removeQueueItem(at: index)
                                                }
                                            } label: {
                                                Label("Remove", systemImage: "trash")
                                            }
                                        }
                                }
                                .onMove { fromOffsets, toOffset in
                                    playbackState.moveQueueItem(fromOffsets: fromOffsets, toOffset: toOffset)
                                }
                                .onDelete { offsets in
                                    for idx in offsets.sorted().reversed() {
                                        playbackState.removeQueueItem(at: idx)
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text("UP NEXT")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(LumoTheme.textSecondary)
                                Spacer()
                                Text("\(playbackState.queue.count) songs")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(LumoTheme.textTertiary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, $editMode)
                }
            }
            .navigationTitle("Playing Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation {
                            editMode = (editMode == .active) ? .inactive : .active
                        }
                    } label: {
                        Text(editMode == .active ? "Done" : "Reorder")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LumoTheme.accentPink)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if !playbackState.queue.isEmpty {
                        Button {
                            withAnimation {
                                playbackState.clearQueue()
                            }
                        } label: {
                            Text("Clear")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.red.opacity(0.85))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            // Queue Badge
            HStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LumoTheme.accentPink)
                Text("Queue (\(playbackState.queue.count))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LumoTheme.textPrimary)
            }
            
            Spacer()
            
            // Shuffle Toggle
            Button {
                withAnimation {
                    playbackState.toggleShuffle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 12, weight: .bold))
                    Text(playbackState.isShuffleEnabled ? "Shuffled" : "Shuffle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(playbackState.isShuffleEnabled ? Color.white : LumoTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(playbackState.isShuffleEnabled ? LumoTheme.accentPink : LumoTheme.surfaceRaised)
                .clipShape(Capsule())
            }
        }
    }
    
    private func nowPlayingCard(track: iOSTrack) -> some View {
        HStack(spacing: 12) {
            // Artwork
            if let data = track.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LumoTheme.surfaceRaised)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(LumoTheme.accentPink)
                    )
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LumoTheme.textPrimary)
                    .lineLimit(1)
                
                Text(track.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LumoTheme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Live Equalizer Animation
            HStack(spacing: 2.5) {
                ForEach(0..<4) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(LumoTheme.accentPink)
                        .frame(width: 3, height: audioEngine.isPlaying ? CGFloat([14, 22, 10, 18][i]) : 4)
                        .animation(
                            audioEngine.isPlaying
                                ? Animation.easeInOut(duration: 0.35).repeatForever().delay(Double(i) * 0.1)
                                : .default,
                            value: audioEngine.isPlaying
                        )
                }
            }
            .frame(height: 24)
            .padding(.trailing, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LumoTheme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(LumoTheme.accentPink.opacity(0.35), lineWidth: 1)
                )
        )
    }
    
    private func queueRow(index: Int, track: iOSTrack) -> some View {
        HStack(spacing: 12) {
            // Index Number
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(LumoTheme.textTertiary)
                .frame(width: 24, alignment: .leading)
            
            // Artwork
            if let data = track.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LumoTheme.surfaceRaised)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 12))
                            .foregroundStyle(LumoTheme.textTertiary)
                    )
            }
            
            // Title & Artist
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LumoTheme.textPrimary)
                    .lineLimit(1)
                
                Text(track.artist)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(LumoTheme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Duration
            Text(track.formattedDuration)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(LumoTheme.textTertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                playbackState.playQueueItem(at: index)
            }
        }
    }
    
    private var emptyQueueCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 32))
                .foregroundStyle(LumoTheme.textTertiary)
            Text("Your queue is empty")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LumoTheme.textSecondary)
            Text("Tap any song in Library or swipe to add songs.")
                .font(.system(size: 12))
                .foregroundStyle(LumoTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
