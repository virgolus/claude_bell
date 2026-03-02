import SwiftUI

/// Consistent footer bar with Dismiss and Open in Terminal buttons.
struct DetailFooterView: View {
    let cwd: String
    let isPassive: Bool
    let onDismiss: () -> Void

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
                        .font(.caption)
                }
                .if(isPassive) {
                    $0.keyboardShortcut(.return, modifiers: [])
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    TerminalBridge.focusTerminalTab(forCwd: cwd)
                    onDismiss()
                } label: {
                    Label("Open in Terminal", systemImage: "terminal")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
