import SwiftUI

/// Consistent footer bar with Dismiss and Open in Terminal buttons.
struct DetailFooterView: View {
    let cwd: String
    let isPassive: Bool
    let onDismiss: () -> Void

    enum FooterButton: Hashable, CaseIterable {
        case dismiss, openInTerminal
    }

    @State private var focused: FooterButton = .dismiss
    @State private var keyMonitor: Any?

    init(cwd: String, isPassive: Bool = false, onDismiss: @escaping () -> Void) {
        self.cwd = cwd
        self.isPassive = isPassive
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button {
                    onDismiss()
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(focused == .dismiss ? Color.accentColor : Color.clear, lineWidth: 2)
                )

                Spacer()

                Button {
                    TerminalBridge.focusTerminalTab(forCwd: cwd)
                    onDismiss()
                } label: {
                    Label("Open in Terminal", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(focused == .openInTerminal ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            }
            .padding()
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 123: // left arrow
                focused = .dismiss
                return nil
            case 124: // right arrow
                focused = .openInTerminal
                return nil
            case 36: // return
                activate()
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

    private func activate() {
        switch focused {
        case .dismiss:
            onDismiss()
        case .openInTerminal:
            TerminalBridge.focusTerminalTab(forCwd: cwd)
            onDismiss()
        }
    }
}
