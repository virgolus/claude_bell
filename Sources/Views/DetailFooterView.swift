import SwiftUI

/// Consistent footer bar with Dismiss and Open in Terminal buttons.
/// When `focusedButton` is provided, keyboard navigation is managed by the parent view.
/// When `focusedButton` is nil (standalone), the footer manages its own keyboard navigation.
struct DetailFooterView: View {
    let cwd: String
    let transcriptPath: String
    let isPassive: Bool
    let onDismiss: () -> Void
    let onOpenInTerminal: (() -> Void)?

    /// When non-nil, parent controls which button is highlighted (no local key monitor).
    var focusedButton: FooterButton?

    /// When true, the footer manages its own keyboard navigation.
    /// When false, the parent view manages keyboard events (even if focusedButton is nil).
    let standalone: Bool

    /// When standalone, local state manages focus.
    @State private var localFocused: FooterButton = .dismiss
    @State private var keyMonitor: Any?

    enum FooterButton: Hashable, CaseIterable {
        case dismiss, openInTerminal
    }

    private var activeFocus: FooterButton {
        focusedButton ?? localFocused
    }

    init(cwd: String, transcriptPath: String = "", isPassive: Bool = false, standalone: Bool = true, focusedButton: FooterButton? = nil, onOpenInTerminal: (() -> Void)? = nil, onDismiss: @escaping () -> Void) {
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.isPassive = isPassive
        self.standalone = standalone
        self.focusedButton = focusedButton
        self.onOpenInTerminal = onOpenInTerminal
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
                    if let onOpenInTerminal {
                        onOpenInTerminal()
                    } else {
                        TerminalBridge.focusTerminalTab(forCwd: cwd, transcriptPath: transcriptPath)
                        onDismiss()
                    }
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
            if standalone { installKeyMonitor() }
        }
        .onDisappear {
            if standalone { removeKeyMonitor() }
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't intercept keys when a text field is active (e.g. renaming a session)
            if isTextFieldActive() { return event }
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
            if let onOpenInTerminal {
                onOpenInTerminal()
            } else {
                TerminalBridge.focusTerminalTab(forCwd: cwd, transcriptPath: transcriptPath)
                onDismiss()
            }
        }
    }
}
