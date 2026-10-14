import SwiftUI

extension View {
    /// Conditionally apply a modifier.
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Apply a modifier only on macOS 15+.
    @ViewBuilder
    func onMacOS15<Content: View>(
        _ transform: (Self) -> Content
    ) -> some View {
        if #available(macOS 15, *) {
            transform(self)
        } else {
            self
        }
    }
}
