import SwiftUI

struct TextInputView: View {
    let notification: NotificationEntry
    let onSend: (String) -> Void
    let onOpenTerminal: () -> Void
    @ObservedObject private var bodyStyle = BodyStyleSettings.shared

    @State private var inputText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !notification.message.isEmpty {
                MarkdownText(notification.message, font: bodyStyle.bodyFont(size: .body), textColor: bodyStyle.fontColor)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(bodyStyle.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

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
        }
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onSend(text)
        inputText = ""
    }
}
