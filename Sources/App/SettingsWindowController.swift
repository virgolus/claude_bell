import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func showSettings() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if window == nil {
            let hostingView = NSHostingView(rootView: SettingsContainerView())
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.contentView = hostingView
            w.title = "Claude Bell Settings"
            w.level = .floating
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
