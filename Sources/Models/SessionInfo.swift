import Foundation

struct SessionInfo: Identifiable, Sendable {
    let id: String  // session_id
    let cwd: String
    var lastSeen: Date
    var customName: String?

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    var displayName: String {
        customName ?? projectName
    }
}
