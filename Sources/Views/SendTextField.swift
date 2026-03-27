import SwiftUI

/// Reusable text field + Send button row.
struct SendTextField: View {
    var placeholder: String = "Type your response..."
    var onSend: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($focused)
                .onSubmit { send() }

            Button("Send") { send() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.orangeProminent)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
    }
}
