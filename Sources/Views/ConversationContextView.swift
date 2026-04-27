import SwiftUI

struct ConversationContextView: View {
    let transcriptPath: String
    var startExpanded: Bool = false
    @State private var messages: [TranscriptMessage] = []
    @State private var isExpanded = false
    @ObservedObject private var bodyStyle = BodyStyleSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.subheadline)
                    Text("Conversation Context")
                        .font(.headline)
                    Text("(\(messages.count) messages)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        MessageBubble(message: message, bodyStyle: bodyStyle)
                    }
                }
            }
        }
        .onAppear {
            messages = TranscriptParser.parseLastMessages(from: transcriptPath)
            isExpanded = startExpanded
        }
    }
}

private struct MessageBubble: View {
    let message: TranscriptMessage
    @ObservedObject var bodyStyle: BodyStyleSettings

    var isUser: Bool { message.role == "user" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isUser ? "person.circle.fill" : "sparkle")
                    .font(.callout)
                    .foregroundStyle(isUser ? Color.blue : Color.orange)
                Text(isUser ? "You" : "Claude")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !message.textContent.isEmpty {
                MarkdownText(
                    message.textContent,
                    font: bodyStyle.bodyFont(size: .body),
                    textColor: bodyStyle.fontColor
                )
            }

            ForEach(message.toolUses) { tool in
                HStack(spacing: 6) {
                    Image(systemName: ToolIconMapper.icon(for: tool.name))
                        .font(.callout)
                    Text(tool.name)
                        .font(.body.weight(.medium))
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bodyStyle.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}
