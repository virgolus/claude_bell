import SwiftUI

/// Consistent footer bar with Dismiss and Open in Terminal buttons.
/// When `focusedButton` is provided, keyboard navigation is managed by the parent view.
/// When `focusedButton` is nil (standalone), the footer manages its own keyboard navigation.
struct DetailFooterView: View {
    let cwd: String
    let isPassive: Bool
    let onDismiss: () -> Void

    /// When non-nil, parent controls which button is highlighted (no local key monitor).
    var focusedButton: FooterButton?

    /// When standalone (focusedButton == nil), local state manages focus.
    @State private var localFocused: FooterButton = .dismiss
    @State private var keyMonitor: Any?

    enum FooterButton: Hashable, CaseIterable {
        case dismiss, openInTerminal
    }

    private var activeFocus: FooterButton {
        focusedButton ?? localFocused
    }

    private var isStandalone: Bool { focusedButton == nil }

    init(cwd: String, isPassive: Bool = false, focusedButton: FooterButton? = nil, onDismiss: @escaping () -> Void) {
        self.cwd = cwd
        self.isPassive = isPassive
        self.focusedButton = focusedButton
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
                        .stroke(activeFocus == .dismiss ? Color.accentColor : Color.clear, lineWidth: 2)
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
                        .stroke(activeFocus == .openInTerminal ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            }
            .padding()
        }
        .onAppear {
            if isStandalone { installKeyMonitor() }
        }
        .onDisappear {
            if isStandalone { removeKeyMonitor() }
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 123: // left arrow
                localFocused = .dismiss
                return nil
            case 124: // right arrow
                localFocused = .openInTerminal
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

    func activate() {
        switch activeFocus {
        case .dismiss:
            onDismiss()
        case .openInTerminal:
            TerminalBridge.focusTerminalTab(forCwd: cwd)
            onDismiss()
        }
    }
}
