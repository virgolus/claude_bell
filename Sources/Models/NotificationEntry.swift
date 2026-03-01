import Foundation

struct NotificationEntry: Identifiable, Sendable {
    let id = UUID()
    let sessionId: String
    let cwd: String
    let notificationType: String
    let message: String
    let createdAt: Date

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }
}
