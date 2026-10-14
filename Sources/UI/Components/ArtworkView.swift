import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Displays album artwork with shimmer loading state, fallback placeholder,
/// and a "Fix artwork…" context menu to pick local files, paste URLs, or search again.
struct ArtworkView: View {
    let data: Data?
    var fallbackTitle: String = ""
    var size: CGFloat = 48
    var cornerRadius: CGFloat = AppConstants.UI.artworkCornerRadius
    var isLoading: Bool = false
    var showFixMenu: Bool = true
    
    @State private var showingURLPrompt: Bool = false
    @State private var inputURLText: String = ""
    @State private var shimmerOffset: CGFloat = -1.0
    
    private var isEffectivelyLoading: Bool {
        if isLoading { return true }
        let snapshot = NowPlayingSnapshot.shared
        if data == nil && snapshot.isFetchingArtwork {
            return fallbackTitle.isEmpty || fallbackTitle == snapshot.title
        }
        return false
    }
    
    private var seededColors: [Color] {
        var hash = 0
        for char in fallbackTitle.utf8 {
            hash = (hash &* 31) &+ Int(char)
        }
        let hue1 = Double(abs(hash) % 360) / 360.0
        let hue2 = Double(abs(hash &* 17) % 360) / 360.0
        return [
            Color(hue: hue1, saturation: 0.8, brightness: 0.8),
            Color(hue: hue2, saturation: 0.9, brightness: 0.6)
        ]
    }
    
    var body: some View {
        Group {
            if isEffectivelyLoading {
                // Shimmer Loading Animation
                shimmerView
            } else if let data, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Placeholder with generated gradient based on title hash
                ZStack {
                    LinearGradient(
                        colors: seededColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    if fallbackTitle.isEmpty {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.35, weight: .light))
                            .foregroundStyle(.white.opacity(0.8))
                    } else {
                        Text(String(fallbackTitle.prefix(1)).uppercased())
                            .font(.system(size: size * 0.4, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .contextMenu {
            if showFixMenu {
                fixArtworkMenu
            }
        }
        .sheet(isPresented: $showingURLPrompt) {
            pasteURLSheet
        }
    }
    
    // MARK: - Shimmer Placeholder
    
    private var shimmerView: some View {
        ZStack {
            Color.white.opacity(0.08)
            
            LinearGradient(
                colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.25),
                    Color.white.opacity(0.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .offset(x: shimmerOffset * size * 2)
            
            Image(systemName: "music.note")
                .font(.system(size: size * 0.3, weight: .light))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.0
            }
        }
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private var fixArtworkMenu: some View {
        Menu {
            Button {
                NowPlayingSnapshot.shared.refetchArtwork()
            } label: {
                Label("Search Online Again", systemImage: "arrow.triangle.2.circlepath")
            }
            
            Button {
                chooseLocalImage()
            } label: {
                Label("Choose Local Image…", systemImage: "photo")
            }
            
            Button {
                inputURLText = ""
                showingURLPrompt = true
            } label: {
                Label("Paste Artwork URL…", systemImage: "link")
            }
        } label: {
            Label("Fix Artwork…", systemImage: "photo.badge.plus")
        }
    }
    
    // MARK: - Local Image Picker
    
    private func chooseLocalImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose Album Artwork"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.image]
        
        if panel.runModal() == .OK, let url = panel.url, let fileData = try? Data(contentsOf: url) {
            NowPlayingSnapshot.shared.setManualArtwork(data: fileData)
        }
    }
    
    // MARK: - Paste URL Sheet
    
    private var pasteURLSheet: some View {
        VStack(spacing: 16) {
            Text("Paste Artwork URL")
                .font(LumoFonts.headingLarge)
                .foregroundStyle(LumoColors.textPrimary)
            
            Text("Enter a direct image URL (JPEG/PNG/WebP) to set as album artwork.")
                .font(LumoFonts.bodySmall)
                .foregroundStyle(LumoColors.textSecondary)
                .multilineTextAlignment(.center)
            
            TextField("https://example.com/cover.jpg", text: $inputURLText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 340)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    showingURLPrompt = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Apply") {
                    if let url = URL(string: inputURLText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        NowPlayingSnapshot.shared.setManualArtworkURL(url)
                    }
                    showingURLPrompt = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(inputURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
