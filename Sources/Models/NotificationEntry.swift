import Foundation
import SwiftUI

struct NotificationEntry: Identifiable, Sendable {
    let id = UUID()
    let sessionId: String
    let cwd: String
    let notificationType: String
    let message: String
    let title: String
    let transcriptPath: String
    let createdAt: Date

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    var meta: NotificationMeta {
        NotificationMeta.for(notificationType)
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        return meta.displayTitle
    }
}

/// Centralizes all per-notification-type metadata in one place.
struct NotificationMeta: Sendable {
    let displayTitle: String
    let icon: String          // SF Symbol for detail view
    let rowIcon: String       // SF Symbol for sidebar row
    let iconColor: Color
    let nativeBody: String    // macOS notification body text
    let isPassive: Bool       // No user input needed (dismiss with Enter, no text field, no transcript)
    let deduplicate: Bool     // Replace existing notification from same session

    static let allTypes: [String: NotificationMeta] = [
        "permission_prompt": NotificationMeta(
            displayTitle: "Permission Prompt",
            icon: "lock.shield.fill", rowIcon: "lock.shield",
            iconColor: .blue,
            nativeBody: "Needs permission",
            isPassive: false, deduplicate: false
        ),
        "idle_prompt": NotificationMeta(
            displayTitle: "Waiting for Input",
            icon: "questionmark.circle.fill", rowIcon: "questionmark.circle",
            iconColor: .blue,
            nativeBody: "Waiting for your input",
            isPassive: false, deduplicate: false
        ),
        "elicitation_dialog": NotificationMeta(
            displayTitle: "Question",
            icon: "text.bubble.fill", rowIcon: "text.bubble",
            iconColor: .blue,
            nativeBody: "Has a question for you",
            isPassive: false, deduplicate: false
        ),
        "stop": NotificationMeta(
            displayTitle: "Task Completed",
            icon: "checkmark.circle.fill", rowIcon: "checkmark.circle",
            iconColor: .green,
            nativeBody: "Task completed",
            isPassive: true, deduplicate: true
        ),
        "tool_error": NotificationMeta(
            displayTitle: "Tool Error",
            icon: "exclamationmark.triangle.fill", rowIcon: "exclamationmark.triangle",
            iconColor: .orange,
            nativeBody: "Tool failed",
            isPassive: true, deduplicate: true
        ),
        "session_end": NotificationMeta(
            displayTitle: "Session Ended",
            icon: "xmark.circle.fill", rowIcon: "xmark.circle",
            iconColor: .secondary,
            nativeBody: "Session ended",
            isPassive: true, deduplicate: true
        ),
    ]

    static let fallback = NotificationMeta(
        displayTitle: "Notification",
        icon: "bell.fill", rowIcon: "bell",
        iconColor: .blue,
        nativeBody: "Notification",
        isPassive: false, deduplicate: false
    )

    static func `for`(_ type: String) -> NotificationMeta {
        allTypes[type] ?? fallback
    }
}
