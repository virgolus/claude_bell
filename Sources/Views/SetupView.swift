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
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.title.weight(.bold))
                    .padding(.bottom, 4)

                // MARK: - Hooks
                settingsSection(title: "Claude Code Hooks", icon: "link.circle.fill", iconColor: .orange) {
                    HStack {
                        Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(installed ? .green : .red)
                        Text(installed ? "Hooks installed" : "Hooks not installed")
                            .font(.body.weight(.medium))
                    }

                    Text("Intercept permission requests and notifications from Claude Code.")
                        .font(.callout)
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
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                    if showSuccess {
                        Text("Done! Changes apply to new Claude Code sessions.")
                            .font(.callout).foregroundStyle(.green)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showSuccess = false }
                            }
                    }
                }

                // MARK: - Status Line
                settingsSection(title: "Status Line", icon: "text.line.last.and.arrowtriangle.forward", iconColor: .blue) {
                    HStack {
                        Image(systemName: statuslineInstalled ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(statuslineInstalled ? .green : .red)
                        Text(statuslineInstalled ? "Status line active" : "Status line not configured")
                            .font(.body.weight(.medium))
                    }

                    Text("Show model, context usage, duration and git branch in Claude Code's status line.")
                        .font(.callout)
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

                // MARK: - Sound
                settingsSection(title: "Notification Sound", icon: "speaker.wave.2.fill", iconColor: .purple) {
                    Text("Sound played when a new permission request arrives.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Picker("Sound:", selection: $selectedSound) {
                        ForEach(RequestStore.availableSounds, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    }
                    .frame(width: 220)
                    .onChange(of: selectedSound) { _, newValue in
                        RequestStore.selectedSound = newValue
                        NSSound(named: newValue)?.play()
                    }
                }

                // MARK: - Shortcut
                settingsSection(title: "Global Shortcut", icon: "keyboard.fill", iconColor: .orange) {
                    Text("Press the shortcut to toggle the panel from anywhere.")
                        .font(.callout)
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
                                    .fill(isRecording ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.15))
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
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }

                // MARK: - Version
                HStack {
                    Spacer()
                    Text("Claude Bell v\(AppVersion.current) (\(AppVersion.build))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.top, 8)
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

    // MARK: - Section builder

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.body)
                Text(title)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                    .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
        }
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
