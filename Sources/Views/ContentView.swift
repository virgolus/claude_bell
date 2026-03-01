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
                HSplitView {
                    sidebarList
                        .frame(minWidth: 200, maxWidth: 280)

                    detailPanel
                        .frame(minWidth: 300)
                }
            }
        }
        .frame(width: 640, height: 480)
        .onAppear {
            NotificationManager.requestPermission()
        }
    }

    private var sidebarList: some View {
        List(selection: $selectedItem) {
            if !store.pendingRequests.isEmpty {
                Section("Pending Requests") {
                    ForEach(store.pendingRequests) { request in
                        RequestRowView(request: request)
                            .tag(SidebarItem.request(request.id))
                    }
                }
            }

            if !store.notifications.isEmpty {
                Section("Notifications") {
                    ForEach(store.notifications) { notification in
                        NotificationRowView(notification: notification)
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
            autoSelectFirst()
        }
        .onChange(of: store.notifications.count) { _, _ in
            autoSelectFirst()
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
                    HStack {
                        Image(systemName: "bell.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(notification.notificationType)
                                .font(.title3.weight(.semibold))
                            Text(notification.projectName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    if needsTextInput(notification) {
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
                    } else {
                        Text(notification.message)
                            .textSelection(.enabled)
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
                .keyboardShortcut(.escape, modifiers: [])

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

    private func needsTextInput(_ notification: NotificationEntry) -> Bool {
        notification.notificationType == "idle_prompt" || notification.notificationType == "elicitation_dialog"
    }

    private func autoSelectFirst() {
        if selectedItem == nil {
            if let first = store.pendingRequests.first {
                selectedItem = .request(first.id)
            } else if let first = store.notifications.first {
                selectedItem = .notification(first.id)
            }
        }
    }
}
