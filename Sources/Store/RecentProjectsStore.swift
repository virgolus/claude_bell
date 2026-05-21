import Foundation
import SwiftUI

/// Persistent list of cwds recently used to launch Claude sessions, either
/// explicitly via "+ New Session" or passively from observed hook events.
@MainActor
final class RecentProjectsStore: ObservableObject {
    static let shared = RecentProjectsStore()

    struct Entry: Identifiable, Codable, Equatable {
        let cwd: String
        let lastUsed: Date
        var id: String { cwd }
    }

    @Published private(set) var entries: [Entry] = []

    private let maxEntries = 10
    private let storageKey = "recentProjects"

    private init() {
        load()
    }

    /// Record a usage of `cwd`. Deduplicates by absolute path, prepends, and trims to `maxEntries`.
    func recordUsage(_ cwd: String) {
        let trimmed = cwd.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var next = entries.filter { $0.cwd != trimmed }
        next.insert(Entry(cwd: trimmed, lastUsed: Date()), at: 0)
        if next.count > maxEntries { next = Array(next.prefix(maxEntries)) }
        entries = next
        save()
    }

    /// Remove an entry (e.g. user asked to forget a project). Currently unused by the UI but
    /// kept so the store stays a self-contained owner of the list.
    func remove(cwd: String) {
        entries.removeAll { $0.cwd == cwd }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = AppDefaults.shared.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = Array(decoded.prefix(maxEntries))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        AppDefaults.shared.set(data, forKey: storageKey)
    }
}
