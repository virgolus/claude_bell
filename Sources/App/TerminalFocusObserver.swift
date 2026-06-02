import AppKit

/// Releases all held Stop hooks when a terminal app becomes frontmost
/// (focus-release): if the user goes to the terminal, the console must be
/// immediately responsive. Notifications stay in the panel — only the
/// direct-reply channel for those turns downgrades to the terminal fallback.
@MainActor
final class TerminalFocusObserver {
    static let shared = TerminalFocusObserver()

    static let terminalBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
    ]

    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        let bundleIds = Self.terminalBundleIds
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier,
                  bundleIds.contains(bundleId) else { return }
            Task { @MainActor in
                RequestStore.shared.releaseAllStopHolds()
            }
        }
    }
}
