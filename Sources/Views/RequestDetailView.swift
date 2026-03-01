import SwiftUI

struct RequestDetailView: View {
    @EnvironmentObject var store: RequestStore
    let request: PendingRequest
    @State private var remainingSeconds: Int = 300

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Tool header
                    HStack {
                        Image(systemName: ToolIconMapper.icon(for: request.toolName))
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading) {
                            Text(request.toolName)
                                .font(.title3.weight(.semibold))
                            Text(request.projectName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        // Timeout countdown
                        Text(formatCountdown(remainingSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(remainingSeconds < 60 ? .red : .secondary)
                    }

                    Divider()

                    // Tool input
                    ToolInputView(toolInput: request.toolInput)

                    // Conversation context
                    if !request.transcriptPath.isEmpty {
                        Divider()
                        ConversationContextView(transcriptPath: request.transcriptPath)
                    }
                }
                .padding()
            }

            Divider()

            // Action buttons
            HStack {
                Button("Deny") {
                    request.respond(allow: false)
                    store.removeRequest(id: request.id)
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Allow") {
                    request.respond(allow: true)
                    store.removeRequest(id: request.id)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
        }
        .onReceive(timer) { _ in
            let elapsed = Int(-request.createdAt.timeIntervalSinceNow)
            remainingSeconds = max(0, 300 - elapsed)
        }
        .onAppear {
            let elapsed = Int(-request.createdAt.timeIntervalSinceNow)
            remainingSeconds = max(0, 300 - elapsed)
        }
    }

    private func formatCountdown(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
