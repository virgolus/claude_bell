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
                Image(systemName: store.badgeCount > 0 ? "bell.badge.fill" : "bell.fill")
            }
        }
        .menuBarExtraStyle(.window)
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Esc to close panel (simulate status button click for proper dismiss)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                if let button = self?.findStatusButton() {
                    button.performClick(nil)
                    return nil
                }
            }
            return event
        }

        // Wire up dismiss callback
        RequestStore.shared.onDismissPanel = { [weak self] in
            self?.dismissPanel()
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

        // Lower the panel window level so system dialogs appear on top
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                let name = String(describing: type(of: window))
                if name.contains("MenuBarExtra") || name.contains("StatusItemWindow") || name.contains("_NSPopoverWindow") {
                    window.level = .floating
                }
            }
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

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Claude Bell"
        alert.informativeText = "Menu bar app for Claude Code permission requests and notifications.\n\nVersion 1.0\nShortcut: \(GlobalShortcut.shared.shortcutDescription)\nServer: localhost:19485"
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

    private func dismissPanel() {
        if let button = findStatusButton() {
            button.performClick(nil)
        }
    }

    func findStatusButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            let name = String(describing: type(of: window))
            if name.contains("StatusBar") || name.contains("NSStatusBar") {
                if let contentView = window.contentView {
                    return findButtonInView(contentView)
                }
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
