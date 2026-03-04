import Foundation
import SwiftUI
import AppKit

@MainActor
final class RequestStore: ObservableObject {
    static let shared = RequestStore()

    @Published var pendingRequests: [PendingRequest] = []
    @Published var notifications: [NotificationEntry] = []
    @Published var sessions: [String: SessionInfo] = [:]
    @Published var isMuted: Bool = AppDefaults.shared.bool(forKey: "isMuted") {
        didSet { AppDefaults.shared.set(isMuted, forKey: "isMuted") }
    }

    /// Set by ClaudeBellApp to auto-show the panel on new requests
    var onNewRequest: (() -> Void)?
    /// Set by AppDelegate to dismiss the panel properly
    var onDismissPanel: (() -> Void)?

    var badgeCount: Int {
        pendingRequests.count + notifications.count
    }

    /// Called when a new hook event arrives for a session — dismiss stale items
    func sessionAdvanced(id: String) {
        // Dismiss stale interactive notifications (user already responded in terminal)
        dismissStaleNotifications(id: id)
        // Dismiss stale permission requests (user already responded in terminal)
        let staleRequests = pendingRequests.filter { $0.sessionId == id }
        for req in staleRequests {
            req.respond(allow: false) // release the HTTP connection
            pendingRequests.removeAll { $0.id == req.id }
        }
    }

    /// Dismiss stale notifications and permission requests for a session.
    /// Called from notification handler (excluding permission_prompt) when
    /// a new event indicates the session has moved on.
    func dismissStaleNotifications(id: String) {
        notifications.removeAll {
            $0.sessionId == id
        }
        let staleRequests = pendingRequests.filter { $0.sessionId == id }
        for req in staleRequests {
            req.respond(allow: false)
            pendingRequests.removeAll { $0.id == req.id }
        }
    }

    func addRequest(_ request: PendingRequest) {
        // New permission request means any previous items for this session are stale
        sessionAdvanced(id: request.sessionId)
        pendingRequests.append(request)
        trackSession(id: request.sessionId, cwd: request.cwd)
        playRequestSound()
        startTimeout(for: request)
        onNewRequest?()
    }

    func removeRequest(id: UUID) {
        pendingRequests.removeAll { $0.id == id }
        if pendingRequests.isEmpty && notifications.isEmpty {
            DispatchQueue.main.async { self.onDismissPanel?() }
        }
    }

    func addNotification(_ notification: NotificationEntry) {
        if !notification.meta.isPassive {
            // Skip if session already has a pending permission request (avoids duplicate)
            let sessionHasRequest = pendingRequests.contains {
                $0.sessionId == notification.sessionId
            }
            if sessionHasRequest { return }

        }
        // Passive notifications (stop, tool_error, session_end) replace stale
        // interactive notifications. They stay in the panel until the session
        // advances (cleared by PreToolUse/sessionAdvanced) or user dismisses.
        if notification.meta.isPassive {
            notifications.removeAll {
                $0.sessionId == notification.sessionId
            }
            playNotificationSound()
        }
        if notification.meta.deduplicate {
            notifications.removeAll {
                $0.sessionId == notification.sessionId && $0.notificationType == notification.notificationType
            }
        }
        notifications.append(notification)
        trackSession(id: notification.sessionId, cwd: notification.cwd)
    }

    func removeNotification(id: UUID) {
        notifications.removeAll { $0.id == id }
        if pendingRequests.isEmpty && notifications.isEmpty {
            DispatchQueue.main.async { self.onDismissPanel?() }
        }
    }

    func renameSession(id: String, name: String?) {
        sessions[id]?.customName = name
    }

    func removeSession(id: String) {
        sessions.removeValue(forKey: id)
    }

    func trackSessionPublic(id: String, cwd: String) {
        trackSession(id: id, cwd: cwd)
    }

    private func trackSession(id: String, cwd: String) {
        if sessions[id] != nil {
            sessions[id]?.lastSeen = Date()
        } else {
            sessions[id] = SessionInfo(id: id, cwd: cwd, lastSeen: Date())
        }
    }

    /// Remove sessions that haven't been seen for a while and have no active notifications/requests.
    func cleanupStaleSessions() {
        let cutoff = Date().addingTimeInterval(-30 * 60) // 30 minutes
        let staleIds = sessions.filter { _, info in
            info.lastSeen < cutoff
        }.map(\.key)

        for id in staleIds {
            // Only remove if no active notifications or requests for this session
            let hasNotifications = notifications.contains { $0.sessionId == id }
            let hasRequests = pendingRequests.contains { $0.sessionId == id }
            if !hasNotifications && !hasRequests {
                sessions.removeValue(forKey: id)
            }
        }
    }

    static let availableSounds = ["Purr", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Sosumi", "Submarine", "Tink"]

    static var selectedSound: String {
        get { AppDefaults.shared.string(forKey: "notificationSound") ?? "Purr" }
        set { AppDefaults.shared.set(newValue, forKey: "notificationSound") }
    }

    private func playRequestSound() {
        guard !isMuted else { return }
        NSSound(named: Self.selectedSound)?.play()
    }

    private func playNotificationSound() {
        guard !isMuted else { return }
        NSSound(named: "Glass")?.play()
    }

    private func startTimeout(for request: PendingRequest) {
        let requestId = request.id
        Task { @MainActor [weak self] in
            // 5 minute timeout
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            guard let self, pendingRequests.contains(where: { $0.id == requestId }) else { return }
            request.respond(allow: false)
            removeRequest(id: requestId)
        }
    }
}
