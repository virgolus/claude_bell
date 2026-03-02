import Foundation

/// Shared UserDefaults that always uses the app's bundle identifier,
/// regardless of whether the binary is launched via `swift run` or as a `.app` bundle.
enum AppDefaults {
    static let shared = UserDefaults(suiteName: "com.posatapelosa.claudebell")!
}
