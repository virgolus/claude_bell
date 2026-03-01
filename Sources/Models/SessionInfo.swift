import Foundation

struct SessionInfo: Identifiable, Sendable {
    let id: String  // session_id
    let cwd: String
    var lastSeen: Date

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }
}
