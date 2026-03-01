import SwiftUI
import AppKit

enum ActionButton {
    case allow
    case deny
}

struct RequestDetailView: View {
    @EnvironmentObject var store: RequestStore
    let request: PendingRequest
    @State private var remainingSeconds: Int = 300
    @State private var focused: ActionButton = .allow
    @State private var keyMonitor: Any?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
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
                        Text(formatCountdown(remainingSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(remainingSeconds < 60 ? .red : .secondary)
                    }

                    Divider()

                    ToolInputView(toolInput: request.toolInput)

                    if !request.transcriptPath.isEmpty {
                        Divider()
                        ConversationContextView(transcriptPath: request.transcriptPath)
                    }
                }
                .padding()
            }

            Divider()

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    actionButton(label: "Deny", icon: "xmark.circle", action: .deny, color: .red)
                    actionButton(label: "Allow", icon: "checkmark.circle", action: .allow, color: .orange)
                }

                HStack {
                    Button {
                        request.respond(allow: false)
                        store.removeRequest(id: request.id)
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        TerminalBridge.focusTerminalTab(forCwd: request.cwd)
                    } label: {
                        Label("Open in Terminal", systemImage: "terminal")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
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
            focused = .allow
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func actionButton(label: String, icon: String, action: ActionButton, color: Color) -> some View {
        let isFocused = focused == action
        return HStack(spacing: 6) {
            Image(systemName: icon)
            Text(label)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFocused ? color.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? color : Color.secondary.opacity(0.3), lineWidth: isFocused ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            focused = action
            confirm()
        }
    }

    private func confirm() {
        let allow = focused == .allow
        request.respond(allow: allow)
        store.removeRequest(id: request.id)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 123: // left arrow
                focused = .deny
                return nil
            case 124: // right arrow
                focused = .allow
                return nil
            case 36: // return
                confirm()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func formatCountdown(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
