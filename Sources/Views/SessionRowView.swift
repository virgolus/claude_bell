import SwiftUI

struct SessionRowView: View {
    @EnvironmentObject var store: RequestStore
    let session: SessionInfo

    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)

            if isEditing {
                TextField("Session name", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.weight(.medium))
                    .onSubmit { commitRename() }
                    .onExitCommand { isEditing = false }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if session.customName != nil {
                        Text(session.projectName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(session.id.prefix(8) + "...")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if !isEditing {
                Text(TimeAgoFormatter.format(session.lastSeen))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Rename...") {
                editText = session.displayName
                isEditing = true
            }
            if session.customName != nil {
                Button("Reset Name") {
                    store.renameSession(id: session.id, name: nil)
                }
            }
            Divider()
            Button("Open in Terminal") {
                TerminalBridge.focusTerminalTab(forCwd: session.cwd)
            }
        }
    }

    private func commitRename() {
        let name = editText.trimmingCharacters(in: .whitespaces)
        store.renameSession(id: session.id, name: name.isEmpty ? nil : name)
        isEditing = false
    }
}
