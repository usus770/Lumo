import SwiftUI
import AppKit

/// Interactive Playing Queue / Up Next popover view.
/// Allows viewing current track, upcoming tracks, drag-and-drop reordering ("put one song over another"),
/// quick arrow reordering, one-click or double-click to play immediately, and clearing or shuffling the queue.
struct QueuePopoverView: View {
    @Environment(PlaybackState.self) private var playbackState
    @State private var hoveredQueueId: UUID? = nil
    @State private var draggedItem: TrackInfo? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerView
            
            Divider()
                .overlay(LumoTheme.stroke)
            
            // Scrollable Content
            ScrollView {
                VStack(spacing: 16) {
                    // Now Playing Card
                    nowPlayingSection
                    
                    // Up Next Section with Reorderable Rows
                    upNextSection
                }
                .padding(14)
            }
        }
        .frame(width: 380, height: 500)
        .background(LumoTheme.bg1)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(LumoTheme.accentPink)
            
            Text("Playing Queue")
                .font(LumoFonts.headingSmall.weight(.bold))
                .foregroundStyle(LumoTheme.textPrimary)
            
            if !playbackState.queue.isEmpty {
                Text("\(playbackState.queue.count)")
                    .font(LumoFonts.micro.weight(.bold))
                    .foregroundStyle(LumoTheme.accentAmber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(LumoTheme.surfaceRaised)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(LumoTheme.stroke, lineWidth: 1)
                    )
            }
            
            Spacer()
            
            // Re-shuffle upcoming queue
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    playbackState.shuffleQueue()
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(LumoIconButtonStyle(size: 26, isActive: playbackState.isShuffleEnabled))
            .help("Shuffle upcoming songs")
            .disabled(playbackState.queue.isEmpty)
            
            // Clear entire queue
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    playbackState.clearQueue()
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(LumoIconButtonStyle(size: 26))
            .help("Clear upcoming queue")
            .disabled(playbackState.queue.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(LumoTheme.surface)
    }
    
    // MARK: - Now Playing Card
    
    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOW PLAYING")
                .font(LumoFonts.micro.weight(.bold))
                .foregroundStyle(LumoTheme.textTertiary)
                .tracking(0.8)
            
            if let current = playbackState.currentTrack {
                HStack(spacing: 12) {
                    ArtworkView(
                        data: current.artworkData,
                        fallbackTitle: current.title,
                        size: 44,
                        cornerRadius: 6
                    )
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(current.title)
                            .font(LumoFonts.bodyMedium.weight(.semibold))
                            .foregroundStyle(LumoTheme.textPrimary)
                            .lineLimit(1)
                        
                        Text(current.artist.isEmpty ? "Unknown Artist" : current.artist)
                            .font(LumoFonts.caption)
                            .foregroundStyle(LumoTheme.textSecondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    AnimatedEqualizerView(barCount: 3, height: 16, isPlaying: playbackState.isPlaying)
                        .padding(.trailing, 4)
                    
                    Text(current.formattedDuration)
                        .font(LumoFonts.mono)
                        .foregroundStyle(LumoTheme.textTertiary)
                }
                .padding(10)
                .background(LumoTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(LumoTheme.strokeActive, lineWidth: 1)
                )
            } else {
                HStack {
                    Text("No track currently playing")
                        .font(LumoFonts.caption)
                        .foregroundStyle(LumoTheme.textTertiary)
                    Spacer()
                }
                .padding(12)
                .background(LumoTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(LumoTheme.stroke, lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Up Next Section
    
    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("UP NEXT")
                    .font(LumoFonts.micro.weight(.bold))
                    .foregroundStyle(LumoTheme.textTertiary)
                    .tracking(0.8)
                
                Spacer()
                
                if !playbackState.queue.isEmpty {
                    Text("\(playbackState.queue.count) song\(playbackState.queue.count == 1 ? "" : "s")")
                        .font(LumoFonts.micro)
                        .foregroundStyle(LumoTheme.textTertiary)
                }
            }
            
            if playbackState.queue.isEmpty {
                VStack(spacing: 10) {
                    LumoMarkView(size: 36, opacity: 0.30)
                        .padding(.top, 16)
                    
                    Text("Queue is empty")
                        .font(LumoFonts.bodyMedium.weight(.medium))
                        .foregroundStyle(LumoTheme.textSecondary)
                    
                    Text("Play any album or song list to queue upcoming music, or right-click a song to 'Play Next'.")
                        .font(LumoFonts.caption)
                        .foregroundStyle(LumoTheme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)
                .background(LumoTheme.surface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(LumoTheme.stroke, lineWidth: 1)
                )
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(Array(playbackState.queue.enumerated()), id: \.element.queueId) { index, track in
                        queueRow(index: index, track: track)
                    }
                }
            }
        }
    }
    
    // MARK: - Queue Row
    
    private func queueRow(index: Int, track: TrackInfo) -> some View {
        let isHovered = hoveredQueueId == track.queueId
        
        return HStack(spacing: 8) {
            // Drag grip indicator
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isHovered ? LumoTheme.textSecondary : LumoTheme.textTertiary.opacity(0.6))
                .frame(width: 14)
                .help("Drag to reorder")
            
            // Index number or Play button on hover
            ZStack {
                if isHovered {
                    Button {
                        playbackState.playQueueItem(at: index)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LumoTheme.accentPink)
                    }
                    .buttonStyle(.plain)
                    .help("Play now")
                } else {
                    Text("\(index + 1)")
                        .font(LumoFonts.micro)
                        .foregroundStyle(LumoTheme.textTertiary)
                }
            }
            .frame(width: 18)
            
            // Artwork
            ArtworkView(
                data: track.artworkData,
                fallbackTitle: track.title,
                size: 32,
                cornerRadius: 4
            )
            
            // Track Info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(LumoFonts.bodySmall.weight(.medium))
                    .foregroundStyle(LumoTheme.textPrimary)
                    .lineLimit(1)
                
                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(LumoFonts.micro)
                    .foregroundStyle(LumoTheme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Action Controls on Hover
            if isHovered {
                HStack(spacing: 4) {
                    // Quick Move Up Button
                    if index > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                playbackState.moveQueueItem(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                            }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(LumoTheme.textSecondary)
                                .frame(width: 20, height: 20)
                                .background(LumoTheme.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Move song up")
                    }
                    
                    // Quick Move Down Button
                    if index < playbackState.queue.count - 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                playbackState.moveQueueItem(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(LumoTheme.textSecondary)
                                .frame(width: 20, height: 20)
                                .background(LumoTheme.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Move song down")
                    }
                    
                    // Remove Button
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            playbackState.removeQueueItem(at: index)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(LumoTheme.textTertiary)
                            .frame(width: 20, height: 20)
                            .background(LumoTheme.surfaceRaised)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove from queue")
                }
            } else {
                Text(track.formattedDuration)
                    .font(LumoFonts.mono)
                    .foregroundStyle(LumoTheme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHovered ? LumoTheme.surfaceRaised : LumoTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHovered ? LumoTheme.strokeActive : LumoTheme.stroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredQueueId = hovering ? track.queueId : nil
        }
        .onTapGesture(count: 2) {
            playbackState.playQueueItem(at: index)
        }
        .onDrag {
            self.draggedItem = track
            return NSItemProvider(object: track.queueId.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: QueueDropDelegate(
            targetTrack: track,
            queue: Binding(
                get: { playbackState.queue },
                set: { playbackState.queue = $0 }
            ),
            draggedItem: $draggedItem,
            onMove: { from, to in
                playbackState.moveQueueItem(fromOffsets: from, toOffset: to)
            }
        ))
    }
}

// MARK: - Drag & Drop Delegate

struct QueueDropDelegate: DropDelegate {
    let targetTrack: TrackInfo
    @Binding var queue: [TrackInfo]
    @Binding var draggedItem: TrackInfo?
    let onMove: (IndexSet, Int) -> Void
    
    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem,
              dragged.queueId != targetTrack.queueId,
              let fromIndex = queue.firstIndex(where: { $0.queueId == dragged.queueId }),
              let toIndex = queue.firstIndex(where: { $0.queueId == targetTrack.queueId }) else { return }
        
        if fromIndex != toIndex {
            let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                onMove(IndexSet(integer: fromIndex), destination)
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
