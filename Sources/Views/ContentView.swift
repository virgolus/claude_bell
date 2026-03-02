import SwiftUI

enum SidebarItem: Hashable {
    case request(UUID)
    case notification(UUID)
}

struct ContentView: View {
    @EnvironmentObject var store: RequestStore
    @State private var selectedItem: SidebarItem?
    @State private var showSetup = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(showSetup: $showSetup)

            Divider()

            if showSetup {
                SetupView()
            } else if store.pendingRequests.isEmpty && store.notifications.isEmpty {
                EmptyStateView()
            } else {
                HStack(spacing: 0) {
                    sidebarList
                        .frame(width: 220)

                    Divider()

                    detailPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 900, height: NSScreen.main.map { $0.visibleFrame.height } ?? 650)
        .onAppear {
            NotificationManager.requestPermission()
            autoSelectLatest()
        }
    }

    private var sidebarList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedItem) {
                if !store.pendingRequests.isEmpty {
                    Section("Pending Requests") {
                        ForEach(store.pendingRequests) { request in
                            HStack {
                                RequestRowView(request: request)
                                Button {
                                    request.respond(allow: false)
                                    store.removeRequest(id: request.id)
                                    if selectedItem == .request(request.id) {
                                        selectedItem = nil
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            .tag(SidebarItem.request(request.id))
                        }
                    }
                }

                if !store.notifications.isEmpty {
                    Section("Notifications") {
                        ForEach(store.notifications) { notification in
                            HStack {
                                NotificationRowView(notification: notification)
                                Button {
                                    store.removeNotification(id: notification.id)
                                    if selectedItem == .notification(notification.id) {
                                        selectedItem = nil
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            .tag(SidebarItem.notification(notification.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            if !store.sessions.isEmpty {
                Divider()
                sessionsSection
            }
        }
        .onChange(of: store.pendingRequests.count) { old, new in
            if new > old {
                // Only auto-select if nothing is currently selected
                if selectedItem == nil || !isSelectedItemValid {
                    if let last = store.pendingRequests.last {
                        selectedItem = .request(last.id)
                    }
                }
            } else {
                autoSelectIfNone()
            }
        }
        .onChange(of: store.notifications.count) { old, new in
            if new > old {
                if selectedItem == nil || !isSelectedItemValid {
                    if let last = store.notifications.last {
                        selectedItem = .notification(last.id)
                    }
                }
            } else {
                autoSelectIfNone()
            }
        }
        .onChange(of: selectedItem) { _, newValue in
            if newValue == nil {
                autoSelectLatest()
            }
        }
        .onChange(of: store.pendingRequests.map(\.id)) { _, _ in
            if let sel = selectedItem, !isItemValid(sel) {
                autoSelectLatest()
            }
        }
        .onChange(of: store.notifications.map(\.id)) { _, _ in
            if let sel = selectedItem, !isItemValid(sel) {
                autoSelectLatest()
            }
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        switch selectedItem {
        case .request(let id):
            if let request = store.pendingRequests.first(where: { $0.id == id }) {
                RequestDetailView(request: request)
            } else {
                placeholder
            }
        case .notification(let id):
            if let notification = store.notifications.first(where: { $0.id == id }) {
                notificationDetail(notification)
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        Text("Select an item")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notificationDetail(_ notification: NotificationEntry) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    HStack {
                        Image(systemName: notification.meta.icon)
                            .font(.title2)
                            .foregroundStyle(notification.meta.iconColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(notification.displayProjectName)
                                .font(.title.weight(.bold))
                            HStack(spacing: 4) {
                                Text(notification.displayTitle)
                                Text("·")
                                Text(TimeAgoFormatter.format(notification.createdAt))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Message
                    if !notification.message.isEmpty {
                        MarkdownText(notification.message, font: .title3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Transcript context (expanded by default, skip for passive types since message already shown above)
                    if !notification.transcriptPath.isEmpty && !notification.meta.isPassive {
                        ConversationContextView(transcriptPath: notification.transcriptPath, startExpanded: true)
                    }

                    // Question options from transcript (skip for passive types like task completed)
                    if !notification.meta.isPassive,
                       !notification.transcriptPath.isEmpty,
                       let questions = transcriptQuestions(for: notification),
                       !questions.isEmpty {
                        QuestionOptionsView(
                            questions: questions,
                            onSend: { text in
                                TerminalBridge.sendText(text, toCwd: notification.cwd)
                                store.removeNotification(id: notification.id)
                                selectedItem = nil
                            }
                        )
                    } else if !notification.meta.isPassive {
                        // Fallback: free text input
                        TextInputView(
                            notification: notification,
                            onSend: { text in
                                TerminalBridge.sendText(text, toCwd: notification.cwd)
                                store.removeNotification(id: notification.id)
                                selectedItem = nil
                            },
                            onOpenTerminal: {
                                TerminalBridge.focusTerminalTab(forCwd: notification.cwd)
                            }
                        )
                    }
                }
                .padding()
            }

            DetailFooterView(cwd: notification.cwd, isPassive: notification.meta.isPassive) {
                store.removeNotification(id: notification.id)
                selectedItem = nil
            }
        }
    }

    @State private var renamingSessionId: String?
    @State private var renameText = ""

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sessions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(Array(store.sessions.values).sorted(by: { $0.lastSeen > $1.lastSeen })) { session in
                if renamingSessionId == session.id {
                    HStack(spacing: 8) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        TextField("Session name", text: $renameText)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.weight(.medium))
                            .onSubmit { commitRename(session.id) }
                            .onExitCommand { renamingSessionId = nil }
                        Button {
                            renamingSessionId = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                } else {
                    HStack(spacing: 4) {
                        SessionRowView(session: session)

                        Button {
                            renameText = session.displayName
                            renamingSessionId = session.id
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.removeSession(id: session.id)
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }

            Spacer().frame(height: 4)
        }
    }

    private func commitRename(_ sessionId: String) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        store.renameSession(id: sessionId, name: name.isEmpty ? nil : name)
        renamingSessionId = nil
    }

    private var isSelectedItemValid: Bool {
        guard let item = selectedItem else { return false }
        return isItemValid(item)
    }

    private func isItemValid(_ item: SidebarItem) -> Bool {
        switch item {
        case .request(let id): return store.pendingRequests.contains { $0.id == id }
        case .notification(let id): return store.notifications.contains { $0.id == id }
        }
    }

    /// Try AskUserQuestion first, then fall back to numbered options in text
    private func transcriptQuestions(for notification: NotificationEntry) -> [ParsedQuestion]? {
        let path = notification.transcriptPath
        if let questions = TranscriptParser.parseLastQuestions(from: path), !questions.isEmpty {
            return questions
        }
        return TranscriptParser.parseNumberedOptions(from: path)
    }

    private func autoSelectLatest() {
        if let last = store.pendingRequests.last {
            selectedItem = .request(last.id)
        } else if let last = store.notifications.last {
            selectedItem = .notification(last.id)
        }
    }

    private func autoSelectIfNone() {
        guard selectedItem == nil else { return }
        autoSelectLatest()
    }
}
