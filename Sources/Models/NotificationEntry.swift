import Foundation

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

    var displayTitle: String {
        if !title.isEmpty { return title }
        switch notificationType {
        case "permission_prompt": return "Permission Prompt"
        case "idle_prompt": return "Waiting for Input"
        case "elicitation_dialog": return "Question"
        default: return notificationType
        }
    }
}
