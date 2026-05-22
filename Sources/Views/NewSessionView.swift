import SwiftUI
import AppKit

struct NewSessionView: View {
    @ObservedObject private var bodyStyle = BodyStyleSettings.shared
    @ObservedObject private var recents = RecentProjectsStore.shared
    @State private var directoryURL: URL?
    @State private var sessionName: String = ""
    @State private var initialPrompt: String = ""

    var onCancel: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    Divider()

                    directorySection

                    nameSection

                    promptSection

                    if !recents.entries.isEmpty {
                        Divider()
                        recentsSection
                    }
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

    private var directorySection: some View {
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
                Button("Choose…") { chooseDirectory() }
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Projects")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(recents.entries) { entry in
                    Button {
                        directoryURL = URL(fileURLWithPath: entry.cwd)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(URL(fileURLWithPath: entry.cwd).lastPathComponent)
                                    .font(.callout.weight(.medium))
                                Text(entry.cwd)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(directoryURL?.path == entry.cwd ? Color.orange.opacity(0.15) : Color.clear)
                    )
                }
            }
        }
    }

    // MARK: - Actions

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
        TerminalBridge.openNewSession(cwd: cwd, initialPrompt: initialPrompt)
        recents.recordUsage(cwd, name: trimmedName.isEmpty ? nil : trimmedName)
        if !trimmedName.isEmpty {
            RequestStore.shared.reserveSessionName(cwd: cwd, name: trimmedName)
        }
        onOpen()
    }
}
