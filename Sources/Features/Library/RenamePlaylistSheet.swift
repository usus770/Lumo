import SwiftUI

/// Modal sheet for renaming a playlist with guaranteed keyboard typing support.
struct RenamePlaylistSheet: View {
    let playlist: Playlist
    @Binding var isPresented: Bool
    
    @State private var name: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LumoColors.accent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "pencil")
                        .font(.system(size: 20))
                        .foregroundStyle(LumoColors.accent)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rename Playlist")
                        .font(LumoFonts.headingMedium)
                        .foregroundStyle(LumoColors.textPrimary)
                    Text("Current name: \(playlist.name)")
                        .font(LumoFonts.bodySmall)
                        .foregroundStyle(LumoColors.textTertiary)
                }
                
                Spacer()
            }
            
            FocusableTextField(placeholder: "Playlist name", text: $name) {
                rename()
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
                
                Button("Rename") {
                    rename()
                }
                .buttonStyle(.lumoPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(LumoColors.background)
        .onAppear {
            name = playlist.name
        }
    }
    
    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await PlaylistManager.shared.renamePlaylist(id: playlist.id, newName: trimmed)
            await MainActor.run {
                name = ""
                isPresented = false
            }
        }
    }
}
