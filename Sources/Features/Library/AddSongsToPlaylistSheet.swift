import SwiftUI

/// Sheet for browsing library tracks and adding them to a playlist.
struct AddSongsToPlaylistSheet: View {
    let playlist: Playlist
    let allTracks: [Track]
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedTrackIDs = Set<Track.ID>()
    
    private var existingTrackIDs: Set<Track.ID> {
        Set(playlist.entries.map(\.trackId))
    }
    
    private var filteredTracks: [Track] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return allTracks.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
        return allTracks.filter { track in
            track.displayTitle.localizedCaseInsensitiveContains(trimmed) ||
            track.displayArtist.localizedCaseInsensitiveContains(trimmed) ||
            track.displayAlbum.localizedCaseInsensitiveContains(trimmed)
        }.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }
    
    private var availableCount: Int {
        filteredTracks.filter { !existingTrackIDs.contains($0.id) }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.title2)
                    .foregroundStyle(LumoColors.accent)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Songs to Playlist")
                        .font(LumoFonts.headingMedium)
                        .foregroundStyle(LumoColors.textPrimary)
                    Text(playlist.name)
                        .font(LumoFonts.bodySmall)
                        .foregroundStyle(LumoColors.textSecondary)
                }
                
                Spacer()
                
                SearchBar(text: $searchText, placeholder: "Search songs, artists, albums…")
                    .frame(width: 240)
            }
            .padding(16)
            
            Divider()
            
            // Sub-bar with selection helpers
            HStack {
                Text("\(filteredTracks.count) songs found")
                    .font(LumoFonts.caption)
                    .foregroundStyle(LumoColors.textTertiary)
                
                Spacer()
                
                if availableCount > 0 {
                    Button("Select All") {
                        let addable = filteredTracks.filter { !existingTrackIDs.contains($0.id) }.map(\.id)
                        selectedTrackIDs.formUnion(addable)
                    }
                    .buttonStyle(.plain)
                    .font(LumoFonts.caption)
                    .foregroundStyle(LumoColors.accent)
                    
                    Text("•")
                        .foregroundStyle(LumoColors.textTertiary)
                    
                    Button("Deselect All") {
                        selectedTrackIDs.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(LumoFonts.caption)
                    .foregroundStyle(LumoColors.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(LumoColors.cardBackground)
            
            Divider()
            
            // Track list
            if filteredTracks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(LumoColors.textTertiary)
                    Text("No matching songs")
                        .font(LumoFonts.bodyMedium)
                        .foregroundStyle(LumoColors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredTracks) { track in
                        let alreadyIn = existingTrackIDs.contains(track.id)
                        let isSelected = selectedTrackIDs.contains(track.id)
                        
                        HStack(spacing: 12) {
                            // Checkbox
                            Button {
                                if !alreadyIn {
                                    if isSelected {
                                        selectedTrackIDs.remove(track.id)
                                    } else {
                                        selectedTrackIDs.insert(track.id)
                                    }
                                }
                            } label: {
                                Image(systemName: alreadyIn ? "checkmark.circle.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                                    .foregroundStyle(alreadyIn ? LumoColors.textTertiary : (isSelected ? LumoColors.accent : LumoColors.textTertiary))
                                    .font(.system(size: 16))
                            }
                            .buttonStyle(.plain)
                            .disabled(alreadyIn)
                            
                            // Artwork
                            ArtworkView(
                                data: ArtworkCache.load(hash: track.artworkHash),
                                fallbackTitle: track.displayTitle,
                                size: 36,
                                cornerRadius: 4
                            )
                            
                            // Track details
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.displayTitle)
                                    .font(LumoFonts.bodyMedium.weight(.medium))
                                    .foregroundStyle(alreadyIn ? LumoColors.textTertiary : LumoColors.textPrimary)
                                    .lineLimit(1)
                                
                                Text("\(track.displayArtist) • \(track.displayAlbum)")
                                    .font(LumoFonts.bodySmall)
                                    .foregroundStyle(LumoColors.textTertiary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            if alreadyIn {
                                Text("Added")
                                    .font(LumoFonts.micro)
                                    .foregroundStyle(LumoColors.textTertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            
                            Text(track.formattedDuration)
                                .font(LumoFonts.caption)
                                .foregroundStyle(LumoColors.textTertiary)
                                .frame(width: 45, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !alreadyIn {
                                if isSelected {
                                    selectedTrackIDs.remove(track.id)
                                } else {
                                    selectedTrackIDs.insert(track.id)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            
            Divider()
            
            // Footer
            HStack {
                Text("\(selectedTrackIDs.count) song\(selectedTrackIDs.count == 1 ? "" : "s") selected")
                    .font(LumoFonts.bodySmall)
                    .foregroundStyle(LumoColors.textSecondary)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.lumoSecondary)
                .keyboardShortcut(.cancelAction)
                
                Button {
                    Task {
                        await PlaylistManager.shared.addTracks(trackIDs: selectedTrackIDs, toPlaylist: playlist.id)
                        dismiss()
                    }
                } label: {
                    Text(selectedTrackIDs.isEmpty ? "Add Songs" : "Add \(selectedTrackIDs.count) Song\(selectedTrackIDs.count == 1 ? "" : "s")")
                }
                .buttonStyle(.lumoPrimary)
                .disabled(selectedTrackIDs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 550, minHeight: 450)
    }
}
