import SwiftUI

/// Reusable text field + Send button row.
///
/// `onSend` returns whether the reply was delivered. When it returns `false`
/// (e.g. the terminal-paste fallback couldn't find the session's tab) the
/// typed text is kept in the field and an inline warning is shown, so the
/// user's input is never silently lost.
struct SendTextField: View {
    var placeholder: String = "Type your response..."
    var onSend: (String) -> Bool

    @State private var text = ""
    @State private var deliveryFailed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($focused)
                    .onSubmit { send() }
                    .onChange(of: text) { _, _ in deliveryFailed = false }

                Button("Send") { send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.orangeProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if deliveryFailed {
                Label("Couldn't reach the session's terminal tab. Your text was copied to the clipboard — switch to that session and paste it.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if onSend(trimmed) {
            text = ""
            deliveryFailed = false
        } else {
            // Keep the text so it isn't lost; surface the failure. The reply
            // handler has already placed it on the clipboard.
            deliveryFailed = true
        }
    }
}
