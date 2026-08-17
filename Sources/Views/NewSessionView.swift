import SwiftUI
import AppKit

struct NewSessionView: View {
    enum SourceMode: String, Hashable, CaseIterable {
        case recent, browse

        var label: String {
            switch self {
            case .recent: return "Recent"
            case .browse: return "Browse"
            }
        }
    }

    @ObservedObject private var bodyStyle = BodyStyleSettings.shared
    @ObservedObject private var recents = RecentProjectsStore.shared
    @State private var sourceMode: SourceMode
    @State private var directoryURL: URL?
    @State private var sessionName: String = ""
    @State private var initialPrompt: String = ""

    var onCancel: () -> Void
    var onOpen: () -> Void

    init(onCancel: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.onCancel = onCancel
        self.onOpen = onOpen
        _sourceMode = State(initialValue: RecentProjectsStore.shared.entries.isEmpty ? .browse : .recent)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    Divider()

                    sourcePicker

                    sourceContent

                    Divider()

                    nameSection

                    promptSection
                }
                .padding()
            }

            Divider()

            HStack(spacing: 10) {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open Session") { open() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(directoryURL == nil)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.bubble.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("New Session")
                    .font(.headline)
                Text("Open a new terminal tab and start Claude in a chosen directory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var sourcePicker: some View {
        Picker("", selection: $sourceMode) {
            ForEach(SourceMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: sourceMode) { _, _ in
            directoryURL = nil
            sessionName = ""
        }
    }

    @ViewBuilder
    private var sourceContent: some View {
        switch sourceMode {
        case .recent:
            if recents.entries.isEmpty {
                emptyRecents
            } else {
                recentsSection
            }
        case .browse:
            browseSection
        }
    }

    private var emptyRecents: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No recent projects yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Switch to Browse to pick a directory, or open a session and it will appear here next time.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Directory")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text(directoryURL?.path ?? "No directory selected")
                    .font(.callout)
                    .foregroundStyle(directoryURL == nil ? .tertiary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(directoryURL == nil ? "Choose…" : "Change…") { chooseDirectory() }
            }
            .padding(10)
            .background(bodyStyle.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session name (optional)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(directoryURL?.lastPathComponent ?? "e.g. API refactor", text: $sessionName)
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(10)
                .background(bodyStyle.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            Text("Shown in the sidebar and the Recent Projects menu.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Initial prompt (optional)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $initialPrompt)
                .font(bodyStyle.bodyFont(size: .body))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100, maxHeight: 220)
                .padding(8)
                .background(bodyStyle.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            Text("Will be passed to `claude` as the first argument.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(recents.entries) { entry in
                Button {
                    selectRecent(entry)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: directoryURL?.path == entry.cwd ? "folder.fill" : "folder")
                            .foregroundStyle(directoryURL?.path == entry.cwd ? Color.orange : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.displayLabel)
                                .font(.callout.weight(.medium))
                            Text(entry.cwd)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if directoryURL?.path == entry.cwd {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.orange)
                                .font(.callout.weight(.semibold))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(directoryURL?.path == entry.cwd ? Color.orange.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            directoryURL?.path == entry.cwd ? Color.orange.opacity(0.35) : Color.clear,
                            lineWidth: 1
                        )
                )
            }
        }
    }

    // MARK: - Actions

    private func selectRecent(_ entry: RecentProjectsStore.Entry) {
        directoryURL = URL(fileURLWithPath: entry.cwd)
        if let name = entry.name, !name.isEmpty, sessionName.isEmpty {
            sessionName = name
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick the directory where Claude should start"
        if let current = directoryURL { panel.directoryURL = current }
        NSApplication.shared.activate()
        if panel.runModal() == .OK, let url = panel.url {
            directoryURL = url
        }
    }

    private func open() {
        guard let url = directoryURL else { return }
        let cwd = url.path
        let trimmedName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Close the panel BEFORE launching: opening a tab posts Cmd+T to
        // whichever app is frontmost, and while our panel holds key focus that
        // is ClaudeBell — the tab never opens and the command would land in the
        // terminal's already-selected tab (i.e. a live claude session).
        RequestStore.shared.onDismissPanel?()
        TerminalBridge.openNewSession(cwd: cwd, initialPrompt: initialPrompt)
        recents.recordUsage(cwd, name: trimmedName.isEmpty ? nil : trimmedName)
        if !trimmedName.isEmpty {
            RequestStore.shared.reserveSessionName(cwd: cwd, name: trimmedName)
        }
        onOpen()
    }
}
