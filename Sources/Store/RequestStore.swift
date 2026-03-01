import Foundation
import SwiftUI
import AppKit

@MainActor
final class RequestStore: ObservableObject {
    static let shared = RequestStore()

    @Published var pendingRequests: [PendingRequest] = []
    @Published var notifications: [NotificationEntry] = []
    @Published var sessions: [String: SessionInfo] = [:]

    var badgeCount: Int {
        pendingRequests.count + notifications.count
    }

    func addRequest(_ request: PendingRequest) {
        pendingRequests.append(request)
        trackSession(id: request.sessionId, cwd: request.cwd)
        playRequestSound()
        startTimeout(for: request)
    }

    func removeRequest(id: UUID) {
        pendingRequests.removeAll { $0.id == id }
    }

    func addNotification(_ notification: NotificationEntry) {
        notifications.append(notification)
        trackSession(id: notification.sessionId, cwd: notification.cwd)
    }

    func removeNotification(id: UUID) {
        notifications.removeAll { $0.id == id }
    }

    private func trackSession(id: String, cwd: String) {
        if sessions[id] != nil {
            sessions[id]?.lastSeen = Date()
        } else {
            sessions[id] = SessionInfo(id: id, cwd: cwd, lastSeen: Date())
        }
    }

    private func playRequestSound() {
        NSSound(named: "Purr")?.play()
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
