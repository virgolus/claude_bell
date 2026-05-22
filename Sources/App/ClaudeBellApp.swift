import SwiftUI
import Foundation
import AppKit

@main
struct ClaudeBellApp: App {
    @StateObject private var store = RequestStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        startServerIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            Label {
                Text("Claude Bell")
            } icon: {
                Image(systemName: store.isMuted ? "bell.slash.fill" : (store.badgeCount > 0 ? "bell.badge.fill" : "bell.fill"))
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsContainerView()
        }
    }

    private func startServerIfNeeded() {
        Task { @MainActor in
            let store = RequestStore.shared

            let portInUse = await Task.detached {
                do {
                    let url = URL(string: "http://127.0.0.1:19485/health")!
                    let (_, response) = try await URLSession.shared.data(from: url)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        return true
                    }
                } catch {}
                return false
            }.value

            if portInUse {
                print("Claude Bell is already running on port 19485")
                return
            }

            let server = HookServer(store: store)
            Task.detached {
                do {
                    try await server.start()
                } catch {
                    print("HookServer failed: \(error)")
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var panelWindow: NSWindow?

    private func isPanelWindow(_ window: NSWindow) -> Bool {
        if let known = panelWindow {
            return window === known
        }
        if window === SettingsWindowController.shared.windowRef {
            return false
        }
        if let button = findStatusButton(), window === button.window {
            return false
        }
        guard window.contentView != nil else { return false }
        panelWindow = window
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Esc to close panel, ⌘, to open settings
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 && !isTextFieldActive() {
                self?.dismissPanel()
                return nil
            }
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," {
                SettingsWindowController.shared.showSettings()
                return nil
            }
            return event
        }

        // Wire up dismiss callback
        RequestStore.shared.onDismissPanel = { [weak self] in
            self?.dismissPanel()
        }

        // Periodically clean up stale sessions (every 5 minutes)
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                RequestStore.shared.cleanupStaleSessions()
            }
        }

        // Check for updates on launch (5s delay) + every 30 min
        let updateChecker = UpdateChecker()
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if let update = await updateChecker.checkForUpdate() {
                RequestStore.shared.availableUpdate = update
            }
        }
        Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            Task { @MainActor in
                if let update = await updateChecker.checkForUpdate() {
                    RequestStore.shared.availableUpdate = update
                }
            }
        }

        // Global shortcut to toggle panel
        GlobalShortcut.shared.onTrigger = {
            self.togglePanel()
        }

        // Start global shortcut (uses Carbon RegisterEventHotKey — no Accessibility needed)
        GlobalShortcut.shared.start()

        // Add right-click menu to the status bar icon
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.setupStatusItemMenu()
        }

        // Adjust panel window level and position based on panel position setting
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let self, self.isPanelWindow(window) else { return }
                self.applyPanelPosition(window)
            }
        }

        // Also reposition on visibility changes (needed on macOS Tahoe)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow,
                  window.occlusionState.contains(.visible) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let self, self.isPanelWindow(window) else { return }
                self.applyPanelPosition(window)
            }
        }
    }

    private func applyPanelPosition(_ window: NSWindow) {
        window.level = .floating

        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let position = BodyStyleSettings.shared.panelPosition

        let targetOrigin: NSPoint?
        switch position {
        case .menuBar:
            var origin = window.frame.origin
            if window.frame.minX < visible.minX { origin.x = visible.minX }
            if window.frame.maxX > visible.maxX { origin.x = visible.maxX - window.frame.width }
            targetOrigin = (origin != window.frame.origin) ? origin : nil
        case .left:
            targetOrigin = NSPoint(x: visible.minX, y: visible.minY)
        case .right:
            targetOrigin = NSPoint(x: visible.maxX - window.frame.width, y: visible.minY)
        case .fullscreen:
            targetOrigin = NSPoint(x: visible.minX, y: visible.minY)
        }

        guard let target = targetOrigin else { return }

        // Try direct repositioning first; if blocked (macOS Tahoe),
        // hide the window, reposition, then show again.
        window.setFrameOrigin(target)
        if window.frame.origin != target {
            window.orderOut(nil)
            window.setFrameOrigin(target)
            window.orderFront(nil)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func setupStatusItemMenu() {
        // Find the NSStatusItem button created by MenuBarExtra
        guard let button = findStatusButton() else {
            print("Could not find status bar button")
            return
        }

        // Monitor right-click on the status bar button
        NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) { [weak self] event in
            guard let self else { return event }
            // Check if the click is on the status bar button area
            if let buttonWindow = button.window, event.window == buttonWindow {
                self.showContextMenu(near: button)
                return nil
            }
            return event
        }
    }

    private func showContextMenu(near button: NSStatusBarButton) {
        let menu = NSMenu()

        let muteTitle = RequestStore.shared.isMuted ? "Unmute" : "Mute"
        let muteItem = NSMenuItem(title: muteTitle, action: #selector(toggleMute), keyEquivalent: "")
        muteItem.target = self
        menu.addItem(muteItem)

        let recentEntries = RecentProjectsStore.shared.entries
        if !recentEntries.isEmpty {
            let recentsItem = NSMenuItem(title: "Recent Projects", action: nil, keyEquivalent: "")
            let recentsMenu = NSMenu()
            for entry in recentEntries {
                let item = NSMenuItem(
                    title: entry.displayLabel,
                    action: #selector(openRecentProject(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry.cwd
                item.toolTip = entry.cwd
                recentsMenu.addItem(item)
            }
            recentsItem.submenu = recentsMenu
            menu.addItem(recentsItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let whatsNewItem = NSMenuItem(title: "What's New", action: #selector(showWhatsNew), keyEquivalent: "")
        whatsNewItem.target = self
        menu.addItem(whatsNewItem)

        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let infoItem = NSMenuItem(title: "About Claude Bell", action: #selector(showAbout), keyEquivalent: "")
        infoItem.target = self
        menu.addItem(infoItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Claude Bell", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Position the menu below the status bar button
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func openRecentProject(_ sender: NSMenuItem) {
        guard let cwd = sender.representedObject as? String else { return }
        TerminalBridge.openNewSession(cwd: cwd, initialPrompt: "")
        Task { @MainActor in
            RecentProjectsStore.shared.recordUsage(cwd)
        }
    }

    @objc private func toggleMute() {
        RequestStore.shared.isMuted.toggle()
    }

    @objc private func showWhatsNew() {
        // Open the panel first, then trigger the overlay
        togglePanel()
        RequestStore.shared.showWhatsNewFromMenu = true
    }

    @objc private func checkForUpdates() {
        Task {
            // Clear dismissed build so manual check always shows available updates
            AppDefaults.shared.removeObject(forKey: "dismissedUpdateBuild")
            let checker = UpdateChecker()
            if let update = await checker.checkForUpdate() {
                RequestStore.shared.availableUpdate = update
                togglePanel()
            } else {
                let alert = NSAlert()
                alert.messageText = "No Updates Available"
                alert.informativeText = "You're running the latest version of Claude Bell (v\(AppVersion.current))."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Claude Bell"
        alert.informativeText = "Menu bar app for Claude Code permission requests and notifications.\n\nVersion \(AppVersion.current) (\(AppVersion.build))\nShortcut: \(GlobalShortcut.shared.shortcutDescription)\nServer: localhost:19485"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func togglePanel() {
        if let button = findStatusButton() {
            button.performClick(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func dismissPanel() {
        guard let panel = panelWindow, panel.isVisible else { return }
        if let button = findStatusButton() {
            button.performClick(nil)
        }
    }

    func findStatusButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            if let contentView = window.contentView,
               let button = findButtonInView(contentView) {
                return button
            }
        }
        return nil
    }

    private func findButtonInView(_ view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton {
            return button
        }
        for subview in view.subviews {
            if let found = findButtonInView(subview) {
                return found
            }
        }
        return nil
    }
}
