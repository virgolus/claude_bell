import SwiftUI

struct TextInputView: View {
    let notification: NotificationEntry
    let onSend: (String) -> Void
    let onOpenTerminal: () -> Void

    @State private var inputText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(notification.message)
                .font(.body)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
                TextField("Type your response...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit {
                        send()
                    }

                Button("Send") {
                    send()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Button {
                onOpenTerminal()
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
                    .font(.caption)
            }
            .buttonStyle(.link)
        }
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onSend(text)
        inputText = ""
    }
}
