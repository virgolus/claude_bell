import Foundation
import SwiftUI
import AppKit

@MainActor
final class RequestStore: ObservableObject {
    static let shared = RequestStore()

    @Published var pendingRequests: [PendingRequest] = []
    @Published var notifications: [NotificationEntry] = []
    @Published var sessions: [String: SessionInfo] = [:]
    /// Held Stop hooks keyed by sessionId. Views observe this to decide
    /// whether a reply travels through the hook (direct) or TerminalBridge.
    @Published var pendingStops: [String: PendingStop] = [:]
    @Published var isMuted: Bool = AppDefaults.shared.bool(forKey: "isMuted") {
        didSet { AppDefaults.shared.set(isMuted, forKey: "isMuted") }
    }
    @Published var showWhatsNewFromMenu = false
    @Published var availableUpdate: UpdateChecker.UpdateInfo? = nil

    /// Set by ClaudeBellApp to auto-show the panel on new requests
    var onNewRequest: (() -> Void)?
    /// Set by AppDelegate to dismiss the panel properly
    var onDismissPanel: (() -> Void)?

    var badgeCount: Int {
        pendingRequests.count + notifications.count
    }

    /// Called when a new hook event arrives for a session — dismiss stale notifications only.
    /// Does NOT auto-deny pending permission requests, since concurrent hook events
    /// (e.g. PreToolUse from subagents) should not cancel a user's pending Allow action.
    func sessionAdvanced(id: String) {
        notifications.removeAll { $0.sessionId == id }
    }

    /// Auto-deny pending permission requests for a session.
    /// Only called when we're certain the request is stale:
    /// - A new PermissionRequest arrived (user responded in terminal)
    /// - Session ended
    func denyStaleRequests(id: String) {
        let staleRequests = pendingRequests.filter { $0.sessionId == id }
        for req in staleRequests {
            print("[RequestStore] Auto-denying stale request for session \(id), tool: \(req.toolName)")
            req.respond(allow: false)
            pendingRequests.removeAll { $0.id == req.id }
        }
    }

    func addRequest(_ request: PendingRequest) {
        // A new permission request means Claude is running again — any hold for that session is stale
        releaseStopHold(sessionId: request.sessionId)
        // A new permission request means the user responded in terminal — deny stale ones
        denyStaleRequests(id: request.sessionId)
        // Also clear stale notifications
        notifications.removeAll { $0.sessionId == request.sessionId }
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
        if notification.notificationType == "tool_error"
            && !AppDefaults.shared.bool(forKey: "toolErrorNotificationsEnabled") {
            return
        }
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

    /// Register a held Stop hook. Any previous hold for the same session is
    /// stale (Claude stopped again) — release it first.
    func registerStopHold(_ stop: PendingStop) {
        pendingStops[stop.sessionId]?.release()
        pendingStops[stop.sessionId] = stop
        startStopHoldTimer(for: stop)
    }

    /// Deliver a panel reply through the held Stop hook.
    /// Returns false when no live hold exists (caller falls back to TerminalBridge).
    func answerStopHold(sessionId: String, text: String) -> Bool {
        guard let stop = pendingStops.removeValue(forKey: sessionId) else { return false }
        stop.answer(text)
        return true
    }

    /// Release one session's hold: the stop completes normally.
    /// The notification (if any) stays in the panel.
    func releaseStopHold(sessionId: String) {
        pendingStops.removeValue(forKey: sessionId)?.release()
    }

    /// Focus-release: a terminal app became frontmost — release every hold so
    /// the console is immediately responsive. Notifications stay.
    func releaseAllStopHolds() {
        guard !pendingStops.isEmpty else { return }
        print("[RequestStore] Focus-release: releasing \(pendingStops.count) held stop(s)")
        for (_, stop) in pendingStops { stop.release() }
        pendingStops.removeAll()
    }

    private func startStopHoldTimer(for stop: PendingStop) {
        let stopId = stop.id
        let sessionId = stop.sessionId
        Task { @MainActor [weak self] in
            let interval = stop.expiresAt.timeIntervalSinceNow
            if interval > 0 {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            guard let self, let current = self.pendingStops[sessionId], current.id == stopId else { return }
            self.releaseStopHold(sessionId: sessionId)
        }
    }

    func renameSession(id: String, name: String?) {
        sessions[id]?.customName = name
    }

    func removeSession(id: String) {
        releaseStopHold(sessionId: id)
        denyStaleRequests(id: id)
        sessions.removeValue(forKey: id)
    }

    func trackSessionPublic(id: String, cwd: String, lastPrompt: String? = nil) {
        trackSession(id: id, cwd: cwd, lastPrompt: lastPrompt)
    }

    /// Queue of (cwd, name) waiting to be applied to the next freshly-tracked session.
    /// Populated when the user launches a session via NewSessionView with a name set.
    /// Consumed by `trackSession` when a new session arrives for a matching cwd.
    private var pendingSessionNames: [(cwd: String, name: String, queuedAt: Date)] = []

    /// Reserve a name to be applied to the next new session matching `cwd`. First-come,
    /// first-served per cwd; expires after 5 minutes to avoid mis-attribution if the
    /// launched terminal never produced a session.
    func reserveSessionName(cwd: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !cwd.isEmpty else { return }
        pendingSessionNames.removeAll { $0.cwd == cwd }
        pendingSessionNames.append((cwd, trimmed, Date()))
    }

    private func consumePendingName(for cwd: String) -> String? {
        let cutoff = Date().addingTimeInterval(-5 * 60)
        pendingSessionNames.removeAll { $0.queuedAt < cutoff }
        guard let idx = pendingSessionNames.firstIndex(where: { $0.cwd == cwd }) else { return nil }
        let name = pendingSessionNames[idx].name
        pendingSessionNames.remove(at: idx)
        return name
    }

    private func trackSession(id: String, cwd: String, lastPrompt: String? = nil) {
        if sessions[id] != nil {
            sessions[id]?.lastSeen = Date()
            if let lastPrompt { sessions[id]?.lastPrompt = lastPrompt }
        } else {
            var info = SessionInfo(id: id, cwd: cwd, lastSeen: Date(), lastPrompt: lastPrompt)
            if let pending = consumePendingName(for: cwd) {
                info.customName = pending
            }
            sessions[id] = info
            RecentProjectsStore.shared.recordUsage(cwd)
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
