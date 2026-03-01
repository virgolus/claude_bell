import SwiftUI
import Carbon.HIToolbox

struct SetupView: View {
    @State private var installed = HookInstaller.isInstalled
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var isRecording = false
    @State private var shortcutLabel = GlobalShortcut.shared.shortcutDescription
    @State private var accessibilityGranted = false
    private let accessibilityTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hooks section
                GroupBox("Claude Code Hooks") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(installed ? .green : .secondary)
                            Text(installed ? "Hooks installed" : "Hooks not installed")
                                .font(.body.weight(.medium))
                        }

                        Text("Intercept permission requests and notifications from Claude Code.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if installed {
                            Button("Remove Hooks") {
                                do {
                                    try HookInstaller.uninstall()
                                    installed = false
                                    showSuccess = true
                                    errorMessage = nil
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } else {
                            Button("Install Hooks") {
                                do {
                                    try HookInstaller.install()
                                    installed = true
                                    showSuccess = true
                                    errorMessage = nil
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }

                        if let error = errorMessage {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                        if showSuccess {
                            Text("Done! Changes apply to new Claude Code sessions.")
                                .font(.caption).foregroundStyle(.green)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showSuccess = false }
                                }
                        }
                    }
                    .padding(4)
                }

                // Shortcut section
                GroupBox("Global Shortcut") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Press the shortcut to toggle the panel from anywhere.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Current:")
                                .font(.body)

                            Text(shortcutLabel)
                                .font(.system(.body, design: .monospaced).weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isRecording ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isRecording ? Color.orange : Color.clear, lineWidth: 1)
                                )

                            Button(isRecording ? "Press new shortcut..." : "Change") {
                                isRecording = true
                            }
                            .disabled(isRecording)
                        }

                        if isRecording {
                            Text("Press your desired key combination (must include Cmd or Ctrl)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(accessibilityGranted ? .green : .orange)
                            Text(accessibilityGranted ? "Accessibility granted" : "Accessibility not granted")
                                .font(.caption)
                                .foregroundStyle(accessibilityGranted ? Color.secondary : Color.orange)

                            if !accessibilityGranted {
                                Button("Open Settings") {
                                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                                    NSWorkspace.shared.open(url)
                                    // Timer will auto-detect when granted
                                }
                                .font(.caption)
                            }
                        }
                    }
                    .padding(4)
                }
            }
            .padding()
        }
        .onAppear { accessibilityGranted = AXIsProcessTrusted() }
        .onReceive(accessibilityTimer) { _ in
            let trusted = AXIsProcessTrusted()
            if trusted != accessibilityGranted {
                accessibilityGranted = trusted
                if trusted { GlobalShortcut.shared.restart() }
            }
        }
        .background(ShortcutRecorder(isRecording: $isRecording, onRecord: { keyCode, modifiers in
            GlobalShortcut.shared.keyCode = keyCode
            GlobalShortcut.shared.modifierFlags = modifiers
            GlobalShortcut.shared.restart()
            shortcutLabel = GlobalShortcut.shared.shortcutDescription
        }))
    }

}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (Int, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onRecord = { keyCode, modifiers in
            onRecord(keyCode, modifiers)
            DispatchQueue.main.async { isRecording = false }
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.isRecordingEnabled = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class ShortcutRecorderView: NSView {
    var onRecord: ((Int, NSEvent.ModifierFlags) -> Void)?
    var isRecordingEnabled = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecordingEnabled else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags
        guard flags.contains(.command) || flags.contains(.control) else {
            return
        }

        let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        onRecord?(Int(event.keyCode), flags.intersection(relevant))
    }
}
