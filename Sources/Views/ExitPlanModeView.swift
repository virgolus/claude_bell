import SwiftUI

/// Renders an ExitPlanMode permission request with the plan as markdown
/// and the typical Claude Code plan-approval options as selectable buttons.
struct ExitPlanModeView: View {
    let request: PendingRequest
    let store: RequestStore
    @ObservedObject private var bodyStyle = BodyStyleSettings.shared

    private var planText: String {
        request.toolInput["plan"]?.description
            ?? request.toolInput["content"]?.description
            ?? ""
    }

    private let options: [(index: Int, label: String, description: String)] = [
        (1, "Yes, clear context & auto-accept edits", "Clear context and accept edits automatically (shift+tab)"),
        (2, "Yes, auto-accept edits", "Accept edits automatically"),
        (3, "Yes, manually approve edits", "Review and approve each edit"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Plan content as rendered markdown
            if !planText.isEmpty {
                Text("Plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                MarkdownText(planText, font: bodyStyle.bodyFont(size: .body), textColor: bodyStyle.fontColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(bodyStyle.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            Text("Approve this plan?")
                .font(.callout.weight(.medium))

            // Option buttons
            ForEach(options, id: \.index) { option in
                optionRow(option)
            }

            // Custom response
            SendTextField(placeholder: "Or type feedback...") { text in
                send(text)
            }
        }
    }

    private func optionRow(_ option: (index: Int, label: String, description: String)) -> some View {
        HStack(spacing: 8) {
            Text("\(option.index).")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(.body.weight(.medium))
                Text(option.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            send("\(option.index)")
        }
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }

    @discardableResult
    private func send(_ text: String) -> Bool {
        // Approving the plan resumes the hook irreversibly, so we always tear
        // the card down here. The feedback text rides the terminal-paste path;
        // if it can't reach the tab it stays on the clipboard for manual paste.
        request.respond(.allow)
        let sent = TerminalBridge.sendText(
            text,
            toCwd: request.cwd,
            transcriptPath: request.transcriptPath,
            marker: TerminalBridge.markerString(code: RequestStore.markerCode(from: request.sessionId)),
            iTermSessionId: store.iTermSessionId(for: request.sessionId)
        )
        store.removeRequest(id: request.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.activate()
        }
        return sent
    }

}
