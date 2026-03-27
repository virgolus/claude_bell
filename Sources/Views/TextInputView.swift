import SwiftUI

struct TextInputView: View {
    let notification: NotificationEntry
    let onSend: (String) -> Void
    let onOpenTerminal: () -> Void
    @ObservedObject private var bodyStyle = BodyStyleSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !notification.message.isEmpty {
                MarkdownText(notification.message, font: bodyStyle.bodyFont(size: .body), textColor: bodyStyle.fontColor)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(bodyStyle.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            SendTextField(onSend: onSend)
        }
    }
}
