import SwiftUI

struct FixMatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let track: Track
    let onSave: () -> Void
    
    @State private var editedTitle: String = ""
    @State private var editedArtist: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Fix Metadata Match")
                .font(LumoFonts.headingMedium)
                .padding(.top)
            
            Form {
                Section(header: Text("Original File")) {
                    Text(URL(fileURLWithPath: track.filePath).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Section(header: Text("Parsed Info")) {
                    TextField("Title", text: $editedTitle)
                    TextField("Artist", text: $editedArtist)
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save Match") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
        .onAppear {
            editedTitle = track.displayTitle
            editedArtist = track.displayArtist
        }
    }
    
    private func saveChanges() {
        Task {
            var allTracks = await PersistenceStore.shared.loadAll(Track.self)
            if let idx = allTracks.firstIndex(where: { $0.id == track.id }) {
                allTracks[idx].title = editedTitle
                allTracks[idx].artistName = editedArtist
                allTracks[idx].metadataSource = .manual
                allTracks[idx].metadataConfidence = 1.0
                try? await PersistenceStore.shared.saveAll(allTracks)
                
                await MainActor.run {
                    NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
                    onSave()
                    dismiss()
                }
            }
        }
    }
}
