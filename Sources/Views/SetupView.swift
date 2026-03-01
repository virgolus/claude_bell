import SwiftUI
import Carbon.HIToolbox

struct SetupView: View {
    @State private var installed = HookInstaller.isInstalled
    @State private var statuslineInstalled = StatuslineInstaller.isInstalled
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var isRecording = false
    @State private var shortcutLabel = GlobalShortcut.shared.shortcutDescription
    @State private var selectedSound = RequestStore.selectedSound

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

                // Statusline section
                GroupBox("Status Line") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: statuslineInstalled ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(statuslineInstalled ? .green : .secondary)
                            Text(statuslineInstalled ? "Status line active" : "Status line not configured")
                                .font(.body.weight(.medium))
                        }

                        Text("Show model, context usage, duration and git branch in Claude Code's status line.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if statuslineInstalled {
                            Button("Remove Status Line") {
                                do {
                                    try StatuslineInstaller.uninstall()
                                    statuslineInstalled = false
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } else {
                            Button("Install Status Line") {
                                do {
                                    try StatuslineInstaller.install()
                                    statuslineInstalled = true
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                    .padding(4)
                }

                // Sound section
                GroupBox("Notification Sound") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sound played when a new permission request arrives.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Picker("Sound:", selection: $selectedSound) {
                                ForEach(RequestStore.availableSounds, id: \.self) { sound in
                                    Text(sound).tag(sound)
                                }
                            }
                            .frame(width: 200)
                            .onChange(of: selectedSound) { _, newValue in
                                RequestStore.selectedSound = newValue
                                NSSound(named: newValue)?.play()
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
                    }
                    .padding(4)
                }
            }
            .padding()
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
