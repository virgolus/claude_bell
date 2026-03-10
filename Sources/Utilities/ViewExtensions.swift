import SwiftUI
import AppKit

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

/// Returns true if the current first responder is an editable text input field.
func isTextFieldActive() -> Bool {
    guard let responder = NSApp.keyWindow?.firstResponder else { return false }
    if let textView = responder as? NSTextView {
        return textView.isEditable
    }
    if let textField = responder as? NSTextField {
        return textField.isEditable
    }
    return false
}
