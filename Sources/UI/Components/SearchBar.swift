import SwiftUI

/// Search bar with SF Symbol, clear button, and focus ring.
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var onSubmit: (() -> Void)?
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isFocused ? LumoColors.accent : LumoColors.textTertiary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(LumoFonts.bodyMedium)
                .focused($isFocused)
                .onSubmit {
                    onSubmit?()
                }
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(LumoColors.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isFocused ? LumoColors.accent.opacity(0.5) : .clear,
                            lineWidth: 1
                        )
                )
        )
        .animation(.easeOut(duration: 0.2), value: isFocused)
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
    }
}
