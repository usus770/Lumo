import SwiftUI

/// Extracts dominant colors from artwork data and renders a dynamic
/// animated gradient background.
struct DynamicBackground: View {
    let artworkData: Data?
    
    @State private var colors: [Color] = [
        Color(hue: 0.74, saturation: 0.30, brightness: 0.12),
        Color(hue: 0.80, saturation: 0.25, brightness: 0.08)
    ]
    
    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.5, 0.5], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ],
                    colors: meshColors
                )
            } else {
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.5), value: colors)
        .onChange(of: artworkData) { _, newData in
            extractColors(from: newData)
        }
        .onAppear {
            extractColors(from: artworkData)
        }
    }
    
    /// Map our extracted colors to 9 mesh gradient points.
    private var meshColors: [Color] {
        let c = colors
        let base0 = c.indices.contains(0) ? c[0] : .black
        let base1 = c.indices.contains(1) ? c[1] : .black
        let base2 = c.indices.contains(2) ? c[2] : base0
        
        return [
            base0.opacity(0.7), base1.opacity(0.5), base2.opacity(0.6),
            base1.opacity(0.6), base0.opacity(0.4), base1.opacity(0.5),
            base2.opacity(0.5), base0.opacity(0.6), base1.opacity(0.7)
        ]
    }
    
    /// Extract dominant colors from image data using simple sampling.
    private func extractColors(from data: Data?) {
        guard let data, let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(
                  forProposedRect: nil,
                  context: nil,
                  hints: nil
              ) else {
            // Reset to default gradient
            withAnimation(.easeInOut(duration: 1.0)) {
                colors = [
                    Color(hue: 0.74, saturation: 0.30, brightness: 0.12),
                    Color(hue: 0.80, saturation: 0.25, brightness: 0.08)
                ]
            }
            return
        }
        
        // Sample colors from the image at key positions
        let width = cgImage.width
        let height = cgImage.height
        
        guard width > 0, height > 0,
              let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data,
              let rawData = CFDataGetBytePtr(pixelData) else {
            return
        }
        
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        
        // Sample 5 points: center, corners
        let samplePoints: [(Int, Int)] = [
            (width / 2, height / 2),     // Center
            (width / 4, height / 4),     // Top-left quadrant
            (3 * width / 4, height / 4), // Top-right quadrant
            (width / 4, 3 * height / 4), // Bottom-left
            (3 * width / 4, 3 * height / 4) // Bottom-right
        ]
        
        var extractedColors: [Color] = []
        for (x, y) in samplePoints {
            let offset = y * bytesPerRow + x * bytesPerPixel
            guard offset + 2 < CFDataGetLength(pixelData) else { continue }
            
            let r = CGFloat(rawData[offset]) / 255.0
            let g = CGFloat(rawData[offset + 1]) / 255.0
            let b = CGFloat(rawData[offset + 2]) / 255.0
            
            // Darken and desaturate slightly for background use
            extractedColors.append(
                Color(
                    red: r * 0.4,
                    green: g * 0.4,
                    blue: b * 0.4
                )
            )
        }
        
        if !extractedColors.isEmpty {
            withAnimation(.easeInOut(duration: 1.5)) {
                colors = extractedColors
            }
        }
    }
}
