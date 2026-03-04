import SwiftUI

struct RenameableTitleView: View {
    let text: String
    let sessionId: String
    @EnvironmentObject private var store: RequestStore
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        if isEditing {
            TextField("Session name", text: $editText)
                .textFieldStyle(.roundedBorder)
                .font(.title.weight(.bold))
                .onSubmit { commit() }
                .onExitCommand { isEditing = false }
        } else {
            Text(text)
                .font(.title.weight(.bold))
                .onTapGesture {
                    editText = text
                    isEditing = true
                }
                .help("Click to rename session")
        }
    }

    private func commit() {
        let name = editText.trimmingCharacters(in: .whitespaces)
        store.renameSession(id: sessionId, name: name.isEmpty ? nil : name)
        isEditing = false
    }
}
