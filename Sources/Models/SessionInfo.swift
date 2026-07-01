import Foundation

struct SessionInfo: Identifiable, Sendable {
    let id: String  // session_id
    let cwd: String
    var lastSeen: Date
    var customName: String?
    var lastPrompt: String?
    /// Controlling terminal of the claude process (e.g. /dev/ttys003),
    /// resolved from the hook connection. Used for exact tab targeting.
    var tty: String?
    /// iTerm2's stable per-session id (GUID), captured while the hook
    /// connection was live. Used to target the exact iTerm2 session at reply
    /// time without polluting its title. nil for Terminal.app / Warp.
    var iTermSessionId: String?

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    var displayName: String {
        customName ?? projectName
    }
}
