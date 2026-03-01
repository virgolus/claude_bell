import Foundation
import SwiftUI
import AppKit

@MainActor
final class RequestStore: ObservableObject {
    static let shared = RequestStore()

    @Published var pendingRequests: [PendingRequest] = []
    @Published var notifications: [NotificationEntry] = []
    @Published var sessions: [String: SessionInfo] = [:]

    /// Set by ClaudeBellApp to auto-show the panel on new requests
    var onNewRequest: (() -> Void)?
    /// Set by AppDelegate to dismiss the panel properly
    var onDismissPanel: (() -> Void)?

    var badgeCount: Int {
        pendingRequests.count + notifications.count
    }

    func addRequest(_ request: PendingRequest) {
        pendingRequests.append(request)
        trackSession(id: request.sessionId, cwd: request.cwd)
        playRequestSound()
        startTimeout(for: request)
        onNewRequest?()
    }

    func removeRequest(id: UUID) {
        let willBeEmpty = pendingRequests.count <= 1 && notifications.isEmpty
        if willBeEmpty { onDismissPanel?() }
        pendingRequests.removeAll { $0.id == id }
    }

    func addNotification(_ notification: NotificationEntry) {
        if !notification.meta.isPassive {
            // Skip if session already has a pending permission request (avoids duplicate)
            let sessionHasRequest = pendingRequests.contains {
                $0.sessionId == notification.sessionId
            }
            if sessionHasRequest { return }

            // Skip if session already has a "stop" notification (task finished)
            let sessionHasStop = notifications.contains {
                $0.sessionId == notification.sessionId && $0.notificationType == "stop"
            }
            if sessionHasStop { return }
        }

        if notification.meta.deduplicate {
            notifications.removeAll {
                $0.sessionId == notification.sessionId && $0.notificationType == notification.notificationType
            }
        }
        // When a session completes (stop) or ends, dismiss stale interactive notifications for that session
        if notification.meta.isPassive {
            notifications.removeAll {
                $0.sessionId == notification.sessionId && !$0.meta.isPassive
            }
        }
        notifications.append(notification)
        trackSession(id: notification.sessionId, cwd: notification.cwd)
    }

    func removeNotification(id: UUID) {
        let willBeEmpty = notifications.count <= 1 && pendingRequests.isEmpty
        if willBeEmpty { onDismissPanel?() }
        notifications.removeAll { $0.id == id }
    }

    func renameSession(id: String, name: String?) {
        sessions[id]?.customName = name
    }

    func removeSession(id: String) {
        sessions.removeValue(forKey: id)
    }

    private func trackSession(id: String, cwd: String) {
        if sessions[id] != nil {
            sessions[id]?.lastSeen = Date()
        } else {
            sessions[id] = SessionInfo(id: id, cwd: cwd, lastSeen: Date())
        }
    }

    static let availableSounds = ["Purr", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Sosumi", "Submarine", "Tink"]

    static var selectedSound: String {
        get { UserDefaults.standard.string(forKey: "notificationSound") ?? "Purr" }
        set { UserDefaults.standard.set(newValue, forKey: "notificationSound") }
    }

    private func playRequestSound() {
        NSSound(named: Self.selectedSound)?.play()
    }

    private func startTimeout(for request: PendingRequest) {
        let requestId = request.id
        Task {
            // 5 minute timeout
            try? await Task.sleep(for: .seconds(300))
            if pendingRequests.contains(where: { $0.id == requestId }) {
                request.respond(allow: false)
                removeRequest(id: requestId)
            }
        }
    }
}
