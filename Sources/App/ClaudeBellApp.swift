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
        // Esc to close panel
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                if let window = NSApp.keyWindow {
                    window.orderOut(nil)
                    return nil
                }
            }
            return event
        }

        // Center panel whenever it becomes visible (delay to override MenuBarExtra positioning)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            let name = String(describing: type(of: window))
            if name.contains("MenuBarExtra") || name.contains("StatusBar") {
                // MenuBarExtra positions the window after didBecomeKey, so we need a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.centerWindow(window)
                }
            }
        }

        // Global shortcut to toggle panel
        GlobalShortcut.shared.onTrigger = {
            self.togglePanel()
        }

        // Request Accessibility if not granted (opens system dialog)
        let trusted = AXIsProcessTrusted()
        print("AXIsProcessTrusted: \(trusted)")
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        GlobalShortcut.shared.start()

        // Poll for accessibility grant
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
            if AXIsProcessTrusted() {
                GlobalShortcut.shared.restart()
                timer.invalidate()
                print("Accessibility granted, shortcut active")
            }
        }
    }

    private func togglePanel() {
        guard let window = findPanelWindow() else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            centerWindow(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func findPanelWindow() -> NSWindow? {
        for window in NSApp.windows {
            let name = String(describing: type(of: window))
            if name.contains("MenuBarExtra") || name.contains("StatusBar") {
                return window
            }
        }
        return nil
    }

    private func centerWindow(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let x = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
