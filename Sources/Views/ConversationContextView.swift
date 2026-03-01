import SwiftUI

struct ConversationContextView: View {
    let transcriptPath: String
    var startExpanded: Bool = false
    @State private var messages: [TranscriptMessage] = []
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("Conversation Context")
                        .font(.caption.weight(.semibold))
                    Text("(\(messages.count) messages)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding(.vertical, 4)
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

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isUser ? "person.fill" : "brain")
                .font(.caption)
                .foregroundStyle(isUser ? .blue : .purple)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                if !message.textContent.isEmpty {
                    MarkdownText(message.textContent, font: .callout)
                }

                ForEach(message.toolUses) { tool in
                    HStack(spacing: 4) {
                        Image(systemName: ToolIconMapper.icon(for: tool.name))
                            .font(.caption)
                        Text(tool.name)
                            .font(.callout.weight(.medium))
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isUser ? Color.blue.opacity(0.08) : Color.purple.opacity(0.08))
        )
    }
}
