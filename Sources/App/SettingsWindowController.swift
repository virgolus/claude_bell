import AppKit
import SwiftUI

/// Thin bridge around the native SwiftUI `Settings` scene.
///
/// The actual window is owned and sized by SwiftUI — this controller only:
///   1. Opens it via the standard `showSettingsWindow:` action, so the
///      user gets the native ⌘, shortcut, toolbar tabs, and per-tab sizing.
///   2. Holds a weak reference to the hosting NSWindow (registered by
///      `SettingsWindowAccessor` inside the view) so `AppDelegate` can tell
///      it apart from the menu bar panel window.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private weak var trackedWindow: NSWindow?
    var windowRef: NSWindow? { trackedWindow }

    /// Set by `OpenSettingsBridge` at app startup. Invokes the official
    /// SwiftUI `openSettings` environment action, which works reliably for
    /// `.accessory` (menu-bar only) apps where the AppKit `sendAction`
    /// responder-chain routing is unreliable.
    var openAction: (() -> Void)?

    private init() {}

    /// Opens the Settings window using the native SwiftUI action.
    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)

        // Close the menu-bar panel so it doesn't obscure the Settings window.
        // The captured `openAction` closure still works after dismissal — it
        // lives at the App scene level, not inside the panel's view tree.
        RequestStore.shared.onDismissPanel?()

        // If we already have a live window, just bring it forward.
        if let window = trackedWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Preferred path: the SwiftUI `openSettings` environment action,
        // captured at startup by `OpenSettingsBridge`. This is the supported
        // API and works for menu-bar-only `.accessory` apps.
        if let openAction {
            openAction()
        } else {
            // Fallback for edge cases where the bridge hasn't mounted yet.
            _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) ||
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }

        // The scene instantiates its window lazily on first call; give
        // SwiftUI a tick to mount it, then promote it to key.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.trackedWindow?.makeKeyAndOrderFront(nil)
        }
    }

    /// Called by `SettingsWindowAccessor` when the SwiftUI hierarchy mounts.
    func register(_ window: NSWindow?) {
        trackedWindow = window
    }
}
