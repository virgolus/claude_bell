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

            if !store.sessions.isEmpty {
                Section("Active Sessions") {
                    ForEach(Array(store.sessions.values).sorted(by: { $0.lastSeen > $1.lastSeen })) { session in
                        SessionRowView(session: session)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: store.pendingRequests.count) { old, new in
            if new > old {
                // New request arrived — always select the latest
                if let last = store.pendingRequests.last {
                    selectedItem = .request(last.id)
                }
            } else {
                autoSelectIfNone()
            }
        }
        .onChange(of: store.notifications.count) { old, new in
            if new > old {
                // New notification arrived — select it if nothing else selected or current is stale
                if let last = store.notifications.last {
                    if selectedItem == nil || !isSelectedItemValid {
                        selectedItem = .notification(last.id)
                    }
                }
            } else {
                autoSelectIfNone()
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

                    // Question options from transcript
                    if !notification.transcriptPath.isEmpty,
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

            Divider()

            HStack {
                Button("Dismiss") {
                    store.removeNotification(id: notification.id)
                    selectedItem = nil
                }
                .if(notification.meta.isPassive) {
                    $0.keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                }

                Spacer()

                Button {
                    TerminalBridge.focusTerminalTab(forCwd: notification.cwd)
                } label: {
                    Label("Open in Terminal", systemImage: "terminal")
                }
            }
            .padding()
        }
    }

    private var isSelectedItemValid: Bool {
        switch selectedItem {
        case .request(let id): return store.pendingRequests.contains { $0.id == id }
        case .notification(let id): return store.notifications.contains { $0.id == id }
        case nil: return false
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
