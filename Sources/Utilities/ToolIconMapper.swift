import Foundation

enum ToolIconMapper {
    static func icon(for toolName: String) -> String {
        switch toolName {
        case "Bash":
            return "terminal"
        case "Edit":
            return "pencil"
        case "Write":
            return "doc.badge.plus"
        case "Read":
            return "doc.text"
        case "Glob":
            return "magnifyingglass"
        case "Grep":
            return "text.magnifyingglass"
        case "Agent":
            return "person.2"
        case "WebFetch":
            return "globe"
        case "WebSearch":
            return "globe.badge.chevron.backward"
        case "NotebookEdit":
            return "book"
        default:
            return "gearshape"
        }
    }
}
