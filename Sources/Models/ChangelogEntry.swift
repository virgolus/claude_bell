import Foundation

struct ChangelogRelease: Codable {
    let version: String
    let build: Int
    let date: String
    let highlights: String
    let changes: [ChangelogChange]
}

struct ChangelogChange: Codable, Identifiable {
    let type: ChangeType
    let text: String

    var id: String { "\(type.rawValue)-\(text)" }

    enum ChangeType: String, Codable {
        case new
        case changed
        case fixed
        case removed
    }
}
