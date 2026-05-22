import SwiftUI

/// Footer bar with a single Dismiss button. The previous "Open in Terminal"
/// button has moved into the notification/request header.
struct DetailFooterView: View {
    let cwd: String
    let transcriptPath: String
    let isPassive: Bool
    let onDismiss: () -> Void

    /// When non-nil, parent controls focus (keeps a stable API for RequestDetailView).
    var focusedButton: FooterButton?

    /// When true, the footer manages its own keyboard navigation.
    let standalone: Bool

    @State private var localFocused: FooterButton = .dismiss
    @State private var keyMonitor: Any?

    enum FooterButton: Hashable, CaseIterable {
        case dismiss
    }

    private var activeFocus: FooterButton {
        focusedButton ?? localFocused
    }

    init(
        cwd: String,
        transcriptPath: String = "",
        isPassive: Bool = false,
        standalone: Bool = true,
        focusedButton: FooterButton? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.isPassive = isPassive
        self.standalone = standalone
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
            if isTextFieldActive() { return event }
            if event.keyCode == 36 { // return
                activate()
                return nil
            }
            return event
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
        }
    }
}
