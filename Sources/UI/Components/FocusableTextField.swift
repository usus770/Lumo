import SwiftUI
import AppKit

/// An AppKit NSTextField representable that guarantees immediate first-responder keyboard focus
/// and reliable text input without macOS SwiftUI focus-stealing or alert bugs.
struct FocusableTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onCommit: () -> Void = {}
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.delegate = context.coordinator
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior
        textField.font = .systemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        
        // As soon as this view is added to a window, immediately make it the first responder
        DispatchQueue.main.async {
            if let window = textField.window {
                window.makeFirstResponder(textField)
            }
        }
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField
        
        init(_ parent: FocusableTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let tf = obj.object as? NSTextField {
                parent.text = tf.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            return false
        }
    }
}
