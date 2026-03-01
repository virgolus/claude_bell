import SwiftUI

struct ConversationContextView: View {
    let transcriptPath: String
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 200)
            }
        }
        .onAppear {
            messages = TranscriptParser.parseLastMessages(from: transcriptPath)
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
                    let truncated = message.textContent.count > 300
                        ? String(message.textContent.prefix(300)) + "..."
                        : message.textContent
                    Text(truncated)
                        .font(.caption)
                        .textSelection(.enabled)
                }

                ForEach(message.toolUses) { tool in
                    HStack(spacing: 4) {
                        Image(systemName: ToolIconMapper.icon(for: tool.name))
                            .font(.caption2)
                        Text(tool.name)
                            .font(.caption.weight(.medium))
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
