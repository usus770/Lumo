import SwiftUI

/// Modal sheet for creating a new playlist with guaranteed keyboard typing support.
struct NewPlaylistSheet: View {
    var initialTracks: [Track.ID] = []
    @Binding var isPresented: Bool
    var onCreated: ((Playlist) -> Void)? = nil
    
    @State private var name: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LumoColors.accent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 20))
                        .foregroundStyle(LumoColors.accent)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Playlist")
                        .font(LumoFonts.headingMedium)
                        .foregroundStyle(LumoColors.textPrimary)
                    if initialTracks.isEmpty {
                        Text("Enter a name for your new playlist")
                            .font(LumoFonts.bodySmall)
                            .foregroundStyle(LumoColors.textTertiary)
                    } else {
                        Text("\(initialTracks.count) song\(initialTracks.count == 1 ? "" : "s") will be added")
                            .font(LumoFonts.bodySmall)
                            .foregroundStyle(LumoColors.textTertiary)
                    }
                }
                
                Spacer()
            }
            
            FocusableTextField(placeholder: "Playlist name", text: $name) {
                create()
            }
            .frame(height: 28)
            
            HStack(spacing: 12) {
                Spacer()
                
                Button("Cancel") {
                    name = ""
                    isPresented = false
                }
                .buttonStyle(.lumoSecondary)
                .keyboardShortcut(.cancelAction)
                
                Button("Create") {
                    create()
                }
                .buttonStyle(.lumoPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(LumoColors.background)
    }
    
    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            let created = await PlaylistManager.shared.createPlaylist(name: trimmed, trackIDs: initialTracks)
            await MainActor.run {
                name = ""
                isPresented = false
                onCreated?(created)
            }
        }
    }
}
