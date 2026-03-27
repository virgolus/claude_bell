import SwiftUI

struct SettingsContainerView: View {
    @State private var selectedTab = 0

    private let tabs: [(String, String)] = [
        ("General", "gearshape"),
        ("Notifications", "bell"),
        ("Appearance", "paintbrush"),
        ("Miscellaneous", "ellipsis.circle"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            HStack(spacing: 2) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    VStack(spacing: 3) {
                        Image(systemName: tab.1)
                            .font(.system(size: 16))
                        Text(tab.0)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == index ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .foregroundStyle(selectedTab == index ? .primary : .secondary)
                    .onTapGesture { selectedTab = index }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case 0: GeneralSettingsTab()
                case 1: NotificationsSettingsTab()
                case 2: AppearanceSettingsTab()
                case 3: MiscellaneousSettingsTab()
                default: GeneralSettingsTab()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 600, height: 640)
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    @State private var installed = HookInstaller.isInstalled
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var showHookConfirm = false
    @State private var isRecording = false
    @State private var shortcutLabel = GlobalShortcut.shared.shortcutDescription

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                            showHookConfirm = true
                        }
                        .buttonStyle(.orangeProminent)
                        .alert("Install Hooks?", isPresented: $showHookConfirm) {
                            Button("Install") {
                                do {
                                    try HookInstaller.install()
                                    installed = true
                                    showSuccess = true
                                    errorMessage = nil
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will modify ~/.claude/settings.json to register Claude Bell hooks.")
                        }
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

                versionFooter
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

// MARK: - Notifications Tab

private struct NotificationsSettingsTab: View {
    @State private var selectedSound = RequestStore.selectedSound
    @State private var macOSNotifications = AppDefaults.shared.bool(forKey: "macOSNotificationsEnabled")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                // MARK: - Mute
                settingsSection(title: "Mute", icon: "bell.slash.fill", iconColor: .gray) {
                    Text("Temporarily silence all notification sounds.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    MuteToggle()
                }

                // MARK: - macOS Notifications
                settingsSection(title: "macOS Notifications", icon: "bell.badge.fill", iconColor: .green) {
                    Text("Show native macOS notification banners for events.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Toggle("Enable macOS Notifications", isOn: $macOSNotifications)
                        .onChange(of: macOSNotifications) { _, enabled in
                            AppDefaults.shared.set(enabled, forKey: "macOSNotificationsEnabled")
                            if enabled {
                                NotificationManager.requestPermission()
                            }
                        }
                }

                versionFooter
            }
            .padding()
        }
    }
}

private struct MuteToggle: View {
    @ObservedObject private var store = RequestStore.shared

    var body: some View {
        Toggle("Muted", isOn: $store.isMuted)
    }
}

// MARK: - Appearance Tab

private struct AppearanceSettingsTab: View {
    @ObservedObject private var bodyStyle = BodyStyleSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Panel Position
                settingsSection(title: "Panel Position", icon: "macwindow", iconColor: .teal) {
                    Text("Choose where the panel appears on screen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Picker("Position:", selection: $bodyStyle.panelPosition) {
                        ForEach(BodyStyleSettings.PanelPosition.allCases, id: \.self) { pos in
                            Text(pos.label).tag(pos)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        Text("Width:")
                            .frame(width: 45, alignment: .leading)
                        Slider(value: $bodyStyle.panelWidth, in: 500...1400, step: 50)
                        Text("\(Int(bodyStyle.panelWidth))pt")
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 50, alignment: .trailing)
                        Button("Reset") { bodyStyle.resetPanelWidth() }
                            .font(.caption)
                    }
                    .disabled(bodyStyle.panelPosition == .fullscreen)
                }

                settingsSection(title: "Notification Style", icon: "textformat", iconColor: .cyan) {
                    Text("Customize the appearance of notification body text.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Picker("Appearance:", selection: $bodyStyle.appearance) {
                        ForEach(BodyStyleSettings.Appearance.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .frame(width: 220)

                    InlineColorPicker(
                        label: "Background:",
                        color: $bodyStyle.customBackgroundColor,
                        isCustom: bodyStyle.hasCustomBackground,
                        onSelect: { bodyStyle.setCustomBackground($0) },
                        onReset: { bodyStyle.resetBackgroundColor() }
                    )

                    InlineColorPicker(
                        label: "Font Color:",
                        color: $bodyStyle.customFontColor,
                        isCustom: bodyStyle.hasCustomFontColor,
                        onSelect: { bodyStyle.setCustomFontColor($0) },
                        onReset: { bodyStyle.resetFontColor() }
                    )

                    HStack {
                        Picker("Font:", selection: Binding(
                            get: { bodyStyle.fontName ?? "" },
                            set: { bodyStyle.fontName = $0.isEmpty ? nil : $0 }
                        )) {
                            ForEach(BodyStyleSettings.availableFonts, id: \.label) { font in
                                Text(font.label)
                                    .tag(font.name ?? "")
                            }
                        }
                        .frame(width: 260)

                        Button("Reset") { bodyStyle.resetFontName() }
                            .font(.caption)
                    }

                    // Preview
                    previewText
                        .font(bodyStyle.bodyFont(size: .body))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(bodyStyle.backgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                versionFooter
            }
            .padding()
        }
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

// MARK: - Miscellaneous Tab

private struct MiscellaneousSettingsTab: View {
    @State private var statuslineInstalled = StatuslineInstaller.isInstalled
    @State private var errorMessage: String?
    @State private var showStatuslineConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                            showStatuslineConfirm = true
                        }
                        .buttonStyle(.orangeProminent)
                        .alert("Install Status Line?", isPresented: $showStatuslineConfirm) {
                            Button("Install") {
                                do {
                                    try StatuslineInstaller.install()
                                    statuslineInstalled = true
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will modify ~/.claude/settings.json and create a status line script.")
                        }
                    }

                    if let error = errorMessage {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                }

                versionFooter
            }
            .padding()
        }
    }
}

// MARK: - Shared helpers

private var versionFooter: some View {
    HStack {
        Spacer()
        Text("Claude Bell v\(AppVersion.current) (\(AppVersion.build))")
            .font(.caption)
            .foregroundStyle(.tertiary)
        Spacer()
    }
    .padding(.top, 8)
}

func settingsSection<Content: View>(
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

struct InlineColorPicker: View {
    let label: String
    @Binding var color: Color
    let isCustom: Bool
    let onSelect: (Color) -> Void
    let onReset: () -> Void

    private static let presets: [Color] = [
        .black, .white,
        Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1),
        .red, .orange, .yellow, .green, .mint, .cyan, .blue, .indigo, .purple, .pink,
        Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 0.06),
    ]

    @State private var hexText: String = ""
    @State private var showHex = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .frame(width: 80, alignment: .leading)

                if isCustom {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                        )
                } else {
                    Text("Auto")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }

                ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, preset in
                    SwatchButton(color: preset) {
                        onSelect(preset)
                        hexText = preset.toHex() ?? ""
                    }
                }

                Button {
                    showHex.toggle()
                    if showHex { hexText = color.toHex() ?? "" }
                } label: {
                    Image(systemName: "number")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button("Reset") { onReset() }
                    .font(.caption)
            }

            if showHex {
                HStack(spacing: 6) {
                    Text("#")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    TextField("Hex", text: $hexText)
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit {
                            if let c = Color(hex: hexText) { onSelect(c) }
                        }
                }
                .padding(.leading, 80)
            }
        }
    }
}

struct SwatchButton: View {
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
