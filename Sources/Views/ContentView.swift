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
        .frame(width: 900, height: 650)
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
        .onChange(of: store.pendingRequests.count) { _, _ in
            autoSelectLatest()
        }
        .onChange(of: store.notifications.count) { _, _ in
            autoSelectLatest()
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
                        Image(systemName: notificationDetailIcon(notification))
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(notification.displayTitle)
                                .font(.title3.weight(.semibold))
                            HStack(spacing: 4) {
                                Text(notification.projectName)
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

                    // Transcript context (expanded by default, but skip for stop/session_end since message already shown above)
                    if !notification.transcriptPath.isEmpty && !["stop", "session_end"].contains(notification.notificationType) {
                        ConversationContextView(transcriptPath: notification.transcriptPath, startExpanded: true)
                    }

                    // Question options from transcript
                    if !notification.transcriptPath.isEmpty,
                       let questions = TranscriptParser.parseLastQuestions(from: notification.transcriptPath),
                       !questions.isEmpty {
                        QuestionOptionsView(
                            questions: questions,
                            onSend: { text in
                                TerminalBridge.sendText(text, toCwd: notification.cwd)
                                store.removeNotification(id: notification.id)
                                selectedItem = nil
                            }
                        )
                    } else if needsTextInput(notification) {
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
                if !needsTextInput(notification) {
                    Button("Dismiss") {
                        store.removeNotification(id: notification.id)
                        selectedItem = nil
                    }
                    .keyboardShortcut(.return, modifiers: [])
                } else {
                    Button("Dismiss") {
                        store.removeNotification(id: notification.id)
                        selectedItem = nil
                    }
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

    private func notificationDetailIcon(_ notification: NotificationEntry) -> String {
        switch notification.notificationType {
        case "permission_prompt": return "lock.shield.fill"
        case "idle_prompt": return "questionmark.circle.fill"
        case "elicitation_dialog": return "text.bubble.fill"
        case "stop": return "checkmark.circle.fill"
        case "tool_error": return "exclamationmark.triangle.fill"
        case "session_end": return "xmark.circle.fill"
        default: return "bell.fill"
        }
    }

    private func needsTextInput(_ notification: NotificationEntry) -> Bool {
        !["stop", "session_end", "tool_error"].contains(notification.notificationType)
    }

    private func autoSelectLatest() {
        if let last = store.pendingRequests.last {
            selectedItem = .request(last.id)
        } else if let last = store.notifications.last {
            selectedItem = .notification(last.id)
        }
    }
}
