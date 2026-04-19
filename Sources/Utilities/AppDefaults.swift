import Foundation

/// Shared UserDefaults that works both via `swift run` and as a `.app` bundle.
/// Uses a group suite name (different from bundle ID) so it works in both contexts.
enum AppDefaults {
    static let shared: UserDefaults = {
        let defaults = UserDefaults(suiteName: "group.com.virgolus.claudebell")!
        defaults.register(defaults: [
            "toolErrorNotificationsEnabled": true
        ])
        return defaults
    }()
}
