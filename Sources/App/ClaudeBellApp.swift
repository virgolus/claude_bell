import SwiftUI
import Foundation

@main
struct ClaudeBellApp: App {
    @StateObject private var store = RequestStore.shared

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

    init() {
        startServerIfNeeded()
    }

    private func startServerIfNeeded() {
        Task { @MainActor in
            let store = RequestStore.shared

            // Single instance check (off main actor)
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
