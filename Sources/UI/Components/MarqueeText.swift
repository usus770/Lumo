import SwiftUI

/// Smooth marquee text component that checks for overflow against available width.
/// If text fits: displays statically without clipping or masks.
/// If text overflows: slowly scrolls back and forth with soft fade masks on both edges,
/// preventing abrupt mid-letter clipping.
struct MarqueeText: View {
    let text: String
    let font: Font
    var color: Color = .white
    var opacity: Double = 1.0
    
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animationTask: Task<Void, Never>? = nil
    
    private var isOverflowing: Bool {
        textWidth > containerWidth && containerWidth > 0
    }
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundColor(color)
                    .opacity(opacity)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.preference(
                                key: MarqueeTextWidthKey.self,
                                value: textGeo.size.width
                            )
                        }
                    )
                    .offset(x: offset)
            }
            .frame(width: w, alignment: .leading)
            .clipped()
            .mask(
                HStack(spacing: 0) {
                    if isOverflowing && offset < -4 {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 16)
                    }
                    Color.black
                    if isOverflowing && offset > -(textWidth - w - 4) {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 16)
                    }
                }
            )
            .onPreferenceChange(MarqueeTextWidthKey.self) { measuredWidth in
                self.textWidth = measuredWidth
                self.containerWidth = w
                restartMarquee(w: w, tw: measuredWidth)
            }
            .onChange(of: w) { _, newW in
                self.containerWidth = newW
                restartMarquee(w: newW, tw: textWidth)
            }
            .onChange(of: text) { _, _ in
                self.offset = 0
                restartMarquee(w: containerWidth, tw: textWidth)
            }
            .onDisappear {
                animationTask?.cancel()
            }
        }
    }
    
    private func restartMarquee(w: CGFloat, tw: CGFloat) {
        animationTask?.cancel()
        guard tw > w && w > 0 else {
            withAnimation(.easeOut(duration: 0.2)) {
                self.offset = 0
            }
            return
        }
        
        let overflow = tw - w + 24
        let speed: Double = 28.0 // points per second
        let scrollDuration = Double(overflow) / speed
        
        animationTask = Task { @MainActor in
            self.offset = 0
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s initial pause
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: scrollDuration)) {
                    self.offset = -overflow
                }
                try? await Task.sleep(nanoseconds: UInt64((scrollDuration + 2.0) * 1_000_000_000))
                if Task.isCancelled { break }
                
                withAnimation(.easeInOut(duration: scrollDuration)) {
                    self.offset = 0
                }
                try? await Task.sleep(nanoseconds: UInt64((scrollDuration + 2.0) * 1_000_000_000))
            }
        }
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
