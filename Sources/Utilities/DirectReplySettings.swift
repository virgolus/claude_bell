import Foundation

/// Hold duration for the Stop-hook direct-reply channel.
/// The hook `timeout` written to ~/.claude/settings.json gets a 60 s margin
/// on top so ClaudeBell always self-releases before Claude Code gives up.
enum DirectReplySettings {
    static let presets: [(label: String, seconds: Int)] = [
        ("5 minutes", 300),
        ("30 minutes", 1800),
        ("4 hours", 14400),
        ("24 hours", 86400),
    ]

    static let defaultHoldSeconds = 300

    static var holdSeconds: Int {
        get {
            let value = AppDefaults.shared.integer(forKey: "directReplyHoldSeconds")
            return value > 0 ? value : defaultHoldSeconds
        }
        set { AppDefaults.shared.set(newValue, forKey: "directReplyHoldSeconds") }
    }

    /// Hook timeout written to settings.json: hold + 60 s margin.
    static var hookTimeoutSeconds: Int { holdSeconds + 60 }
}
