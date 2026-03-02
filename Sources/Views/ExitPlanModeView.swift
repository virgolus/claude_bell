import SwiftUI

/// Renders an ExitPlanMode permission request with the plan as markdown
/// and the typical Claude Code plan-approval options as selectable buttons.
struct ExitPlanModeView: View {
    let request: PendingRequest
    let store: RequestStore

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

    @State private var customText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Plan content as rendered markdown
            if !planText.isEmpty {
                Text("Plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                MarkdownText(planText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
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
            HStack(spacing: 8) {
                TextField("Or type feedback...", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendCustom() }

                Button("Send") { sendCustom() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(customText.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func send(_ text: String) {
        request.respond(.allow)
        TerminalBridge.sendText(text, toCwd: request.cwd)
        store.removeRequest(id: request.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.activate()
        }
    }

    private func sendCustom() {
        let text = customText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        send(text)
    }
}
