import SwiftUI
import AppKit

// MARK: - Root container

struct SettingsContainerView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .frame(width: 580, height: 620)
                .tabItem { Label("General", systemImage: "gearshape") }

            NotificationsSettingsTab()
                .frame(width: 580, height: 360)
                .tabItem { Label("Notifications", systemImage: "bell") }

            AppearanceSettingsTab()
                .frame(width: 580, height: 640)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .background(SettingsWindowAccessor())
    }
}

// MARK: - General tab

private struct GeneralSettingsTab: View {
    @State private var hooksInstalled = HookInstaller.isInstalled
    @State private var hooksError: String?
    @State private var showHookConfirm = false
    @State private var holdSeconds = DirectReplySettings.holdSeconds

    @State private var autoModeEnabled = AutoModeInstaller.isEnabled
    @State private var autoModeError: String?

    @State private var statuslineInstalled = StatuslineInstaller.isInstalled
    @State private var statuslineError: String?
    @State private var showStatuslineConfirm = false

    @State private var isRecordingShortcut = false
    @State private var shortcutLabel = GlobalShortcut.shared.shortcutDescription

    var body: some View {
        Form {
            // MARK: Hooks
            Section {
                LabeledContent("Status") {
                    statusBadge(installed: hooksInstalled,
                                installedText: "Installed",
                                missingText: "Not installed")
                }
                if hooksInstalled {
                    Button(role: .destructive) {
                        do {
                            try HookInstaller.uninstall()
                            hooksInstalled = false
                            hooksError = nil
                        } catch {
                            hooksError = error.localizedDescription
                        }
                    } label: {
                        Label("Remove Hooks", systemImage: "trash")
                    }
                } else {
                    Button { showHookConfirm = true } label: {
                        Label("Install Hooks…", systemImage: "arrow.down.circle")
                    }
                        .buttonStyle(.borderedProminent)
                        .alert("Install Hooks?", isPresented: $showHookConfirm) {
                            Button("Install") {
                                do {
                                    try HookInstaller.install()
                                    hooksInstalled = true
                                    hooksError = nil
                                } catch {
                                    hooksError = error.localizedDescription
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will modify ~/.claude/settings.json to register Claude Bell hooks.")
                        }
                }
                if let hooksError {
                    Label(hooksError, systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .font(.callout)
                        .help(hooksError)
                }
            } header: {
                sectionHeader("Claude Code Hooks", systemImage: "link")
            } footer: {
                Text("Intercept permission requests and notifications from Claude Code.")
            }

            // MARK: Direct Reply
            Section {
                Picker("Hold duration", selection: $holdSeconds) {
                    ForEach(DirectReplySettings.presets, id: \.seconds) { preset in
                        Text(preset.label).tag(preset.seconds)
                    }
                }
                .onChange(of: holdSeconds) { _, newValue in
                    DirectReplySettings.holdSeconds = newValue
                    // Rewrite the Stop hook timeout to match
                    if hooksInstalled {
                        do {
                            try HookInstaller.install()
                            hooksError = nil
                        } catch {
                            hooksError = error.localizedDescription
                        }
                    }
                }
                if let hooksError {
                    Label(hooksError, systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .font(.callout)
                        .help(hooksError)
                }
            } header: {
                sectionHeader("Direct Reply", systemImage: "bolt")
            } footer: {
                Text("After Claude finishes a turn, ClaudeBell keeps a direct channel open for this long: panel replies are delivered through the Stop hook instead of typing into the terminal. Pressing Esc in the terminal or focusing a terminal app releases it early.")
            }

            // MARK: Auto Mode
            Section {
                Toggle("Auto Mode", isOn: $autoModeEnabled)
                    .onChange(of: autoModeEnabled) { _, newValue in
                        do {
                            if newValue {
                                try AutoModeInstaller.enable()
                            } else {
                                try AutoModeInstaller.disable()
                            }
                            autoModeError = nil
                        } catch {
                            autoModeEnabled = !newValue
                            autoModeError = error.localizedDescription
                        }
                    }
                if let autoModeError {
                    Label(autoModeError, systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .font(.callout)
                        .help(autoModeError)
                }
            } header: {
                sectionHeader("Auto Mode", systemImage: "wand.and.stars")
            } footer: {
                Text("When enabled, Claude Code automatically approves or denies tool use based on an AI classifier instead of prompting you each time. Restart the Claude Code session for changes to take effect.")
            }

            // MARK: Status Line
            Section {
                LabeledContent("Status") {
                    statusBadge(installed: statuslineInstalled,
                                installedText: "Active",
                                missingText: "Not configured")
                }
                if statuslineInstalled {
                    Button(role: .destructive) {
                        do {
                            try StatuslineInstaller.uninstall()
                            statuslineInstalled = false
                            statuslineError = nil
                        } catch {
                            statuslineError = error.localizedDescription
                        }
                    } label: {
                        Label("Remove Status Line", systemImage: "trash")
                    }
                } else {
                    Button { showStatuslineConfirm = true } label: {
                        Label("Install Status Line…", systemImage: "arrow.down.circle")
                    }
                        .buttonStyle(.borderedProminent)
                        .alert("Install Status Line?", isPresented: $showStatuslineConfirm) {
                            Button("Install") {
                                do {
                                    try StatuslineInstaller.install()
                                    statuslineInstalled = true
                                    statuslineError = nil
                                } catch {
                                    statuslineError = error.localizedDescription
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will modify ~/.claude/settings.json and create a status line script.")
                        }
                }
                if let statuslineError {
                    Label(statuslineError, systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .font(.callout)
                        .help(statuslineError)
                }
            } header: {
                sectionHeader("Status Line", systemImage: "text.line.last.and.arrowtriangle.forward")
            } footer: {
                Text("Show model, context usage, duration and git branch in Claude Code's status line.")
            }

            // MARK: Shortcut
            Section {
                LabeledContent("Shortcut") {
                    HStack(spacing: 8) {
                        Text(shortcutLabel)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isRecordingShortcut ? Color.accentColor : Color.secondary.opacity(0.3),
                                            lineWidth: 1)
                            )
                        Button(isRecordingShortcut ? "Listening…" : "Change") {
                            isRecordingShortcut = true
                        }
                        .disabled(isRecordingShortcut)
                    }
                }
            } header: {
                sectionHeader("Global Shortcut", systemImage: "command")
            } footer: {
                if isRecordingShortcut {
                    Text("Press your desired combination (must include ⌘ or ⌃).")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("Press the shortcut from anywhere to toggle the panel.")
                }
            }
        }
        .formStyle(.grouped)
        .background(ShortcutRecorder(isRecording: $isRecordingShortcut, onRecord: { keyCode, modifiers in
            GlobalShortcut.shared.keyCode = keyCode
            GlobalShortcut.shared.modifierFlags = modifiers
            GlobalShortcut.shared.restart()
            shortcutLabel = GlobalShortcut.shared.shortcutDescription
        }))
    }
}

// MARK: - Notifications tab

private struct NotificationsSettingsTab: View {
    @State private var selectedSound = RequestStore.selectedSound
    @State private var macOSNotifications = AppDefaults.shared.bool(forKey: "macOSNotificationsEnabled")
    @State private var toolErrorNotifications = AppDefaults.shared.bool(forKey: "toolErrorNotificationsEnabled")
    @ObservedObject private var store = RequestStore.shared

    var body: some View {
        Form {
            Section {
                Picker("Sound", selection: $selectedSound) {
                    ForEach(RequestStore.availableSounds, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .help("Sound played when a new permission request arrives.")
                .onChange(of: selectedSound) { _, newValue in
                    RequestStore.selectedSound = newValue
                    NSSound(named: newValue)?.play()
                }

                Toggle("Mute All Notification Sounds", isOn: $store.isMuted)
            } header: {
                sectionHeader("Sound", systemImage: "speaker.wave.2")
            } footer: {
                Text("Sound played when a new permission request arrives.")
            }

            Section {
                Toggle("Tool Error Notifications", isOn: $toolErrorNotifications)
                    .onChange(of: toolErrorNotifications) { _, enabled in
                        AppDefaults.shared.set(enabled, forKey: "toolErrorNotificationsEnabled")
                    }

                Toggle("macOS Notification Banners", isOn: $macOSNotifications)
                    .onChange(of: macOSNotifications) { _, enabled in
                        AppDefaults.shared.set(enabled, forKey: "macOSNotificationsEnabled")
                        if enabled {
                            NotificationManager.requestPermission()
                        }
                    }
            } header: {
                sectionHeader("Alerts", systemImage: "bell.badge")
            } footer: {
                Text("Show a notification when a tool fails, or surface events through the standard macOS Notification Center.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance tab

private struct AppearanceSettingsTab: View {
    @ObservedObject private var bodyStyle = BodyStyleSettings.shared

    var body: some View {
        Form {
            // MARK: Panel
            Section {
                Picker("Position", selection: $bodyStyle.panelPosition) {
                    ForEach(BodyStyleSettings.PanelPosition.allCases, id: \.self) { pos in
                        Text(pos.label).tag(pos)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Width") {
                    HStack(spacing: 8) {
                        Slider(value: $bodyStyle.panelWidth, in: 500...1400, step: 50)
                            .help("Width of the menu bar panel, in points. Ignored in Fullscreen mode.")
                        Text("\(Int(bodyStyle.panelWidth)) pt")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                        Button("Reset") { bodyStyle.resetPanelWidth() }
                            .controlSize(.small)
                            .help("Restore the default width.")
                    }
                }
                .disabled(bodyStyle.panelPosition == .fullscreen)
            } header: {
                sectionHeader("Panel", systemImage: "macwindow")
            } footer: {
                Text("Choose where the panel appears on screen. Width is ignored in Fullscreen mode.")
            }

            // MARK: Appearance mode
            Section {
                Picker("Theme", selection: $bodyStyle.appearance) {
                    ForEach(BodyStyleSettings.Appearance.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Force a light or dark interface, or follow the system setting.")
            } header: {
                sectionHeader("Appearance", systemImage: "circle.lefthalf.filled")
            }

            // MARK: Notification body style
            Section {
                Picker("Font", selection: Binding(
                    get: { bodyStyle.fontName ?? "" },
                    set: { bodyStyle.fontName = $0.isEmpty ? nil : $0 }
                )) {
                    ForEach(BodyStyleSettings.availableFonts, id: \.label) { font in
                        Text(font.label).tag(font.name ?? "")
                    }
                }
                .help("Typeface used for notification body text.")

                LabeledContent("Size") {
                    HStack(spacing: 8) {
                        Slider(value: $bodyStyle.bodyFontSize, in: 9...28, step: 1)
                            .help("Point size of notification body text. Headings, tables and code scale with it.")
                        Text("\(Int(bodyStyle.bodyFontSize)) pt")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }

                ColorPicker("Background",
                            selection: Binding(
                                get: { bodyStyle.customBackgroundColor },
                                set: { bodyStyle.setCustomBackground($0) }
                            ),
                            supportsOpacity: true)
                    .help("Background colour shown behind notification body text.")

                ColorPicker("Font Color",
                            selection: Binding(
                                get: { bodyStyle.customFontColor },
                                set: { bodyStyle.setCustomFontColor($0) }
                            ),
                            supportsOpacity: false)
                    .help("Colour applied to notification body text.")

                HStack {
                    Spacer()
                    Button("Reset to defaults") {
                        bodyStyle.resetBackgroundColor()
                        bodyStyle.resetFontColor()
                        bodyStyle.resetFontName()
                        bodyStyle.resetFontSize()
                    }
                    .controlSize(.small)
                }

                LabeledContent("Preview") {
                    previewText
                        .font(bodyStyle.bodyFont(size: .body))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(bodyStyle.backgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } header: {
                sectionHeader("Notification Text", systemImage: "textformat")
            } footer: {
                Text("Customise how notification body text is rendered in the panel.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var previewText: some View {
        let text = Text("The quick brown fox jumps over the lazy dog.")
        if let fc = bodyStyle.fontColor {
            text.foregroundStyle(fc)
        } else {
            text
        }
    }
}

// MARK: - Shared helpers

@ViewBuilder
private func statusBadge(installed: Bool, installedText: String, missingText: String) -> some View {
    Label(installed ? installedText : missingText,
          systemImage: installed ? "checkmark.circle.fill" : "circle.dashed")
        .labelStyle(.titleAndIcon)
        .foregroundStyle(installed ? Color.green : Color.secondary)
}

/// Section header with a leading SF Symbol — gives the grouped form a
/// scannable visual rhythm without resorting to iOS-style colored tiles.
@ViewBuilder
private func sectionHeader(_ title: String, systemImage: String) -> some View {
    Label {
        Text(title)
    } icon: {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Window accessor

/// Registers the hosting NSWindow with SettingsWindowController so the
/// rest of the app can still reference it (e.g. to distinguish it from
/// the menu bar panel when repositioning).
private struct SettingsWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            SettingsWindowController.shared.register(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            SettingsWindowController.shared.register(nsView.window)
        }
    }
}
