import SwiftUI
import AppKit

/// Reusable text field + Send button row.
///
/// `onSend` returns whether the reply was delivered. When it returns `false`
/// (e.g. the terminal-paste fallback couldn't find the session's tab) the
/// typed text is kept in the field and an inline warning is shown, so the
/// user's input is never silently lost.
struct SendTextField: View {
    var placeholder: String = "Type your response..."
    var onSend: (String) -> Bool

    @State private var text = ""
    @State private var deliveryFailed = false
    /// When delivery fails specifically because ClaudeBell lacks an effective
    /// Accessibility grant (the paste keystroke can't be sent), we point the
    /// user at the fix instead of the generic "couldn't find the tab" message.
    @State private var accessibilityMissing = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($focused)
                    .onSubmit { send() }
                    .onChange(of: text) { _, _ in deliveryFailed = false; accessibilityMissing = false }

                Button("Send") { send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.orangeProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if accessibilityMissing {
                VStack(alignment: .leading, spacing: 4) {
                    Label("ClaudeBell can't type into the terminal: Accessibility permission isn't active for this build. Your text was copied to the clipboard.", systemImage: "lock.trianglebadge.exclamationmark.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Accessibility Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            } else if deliveryFailed {
                Label("Couldn't reach the session's terminal tab. Your text was copied to the clipboard — switch to that session and paste it.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if onSend(trimmed) {
            text = ""
            deliveryFailed = false
            accessibilityMissing = false
        } else {
            // Keep the text so it isn't lost; surface the failure. The reply
            // handler has already placed it on the clipboard. Distinguish the
            // "no effective Accessibility grant" case — the paste keystroke
            // can't fire — from a genuine tab-not-found so the user is pointed
            // at the actual fix rather than told to hunt for a tab.
            if TerminalBridge.isAccessibilityTrusted {
                deliveryFailed = true
            } else {
                accessibilityMissing = true
            }
        }
    }
}
