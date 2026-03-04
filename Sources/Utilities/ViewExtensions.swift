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

/// Returns true if the current first responder is a text input field.
func isTextFieldActive() -> Bool {
    guard let responder = NSApp.keyWindow?.firstResponder else { return false }
    return responder is NSTextView || responder is NSTextField
}
