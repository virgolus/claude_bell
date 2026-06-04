import Foundation

struct HookInput: Codable, Sendable {
    let sessionId: String
    let cwd: String
    let toolName: String?
    let toolInput: [String: AnyCodable]?
    let transcriptPath: String?
    let hookEventName: String?
    let notificationType: String?
    let notificationMessage: String?
    let permissionMode: String?
    // Additional fields Claude Code may send
    let title: String?
    let message: String?
    let question: String?
    // PostToolUseFailure fields
    let error: String?
    let toolResult: String?
    // Stop/session fields
    let lastAssistantMessage: String?
    let stopHookActive: Bool?
    // PermissionRequest fields
    let permissionSuggestions: [AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case transcriptPath = "transcript_path"
        case hookEventName = "hook_event_name"
        case notificationType = "notification_type"
        case notificationMessage = "notification_message"
        case permissionMode = "permission_mode"
        case title
        case message
        case question
        case error
        case toolResult = "tool_result"
        case lastAssistantMessage = "last_assistant_message"
        case stopHookActive = "stop_hook_active"
        case permissionSuggestions = "permission_suggestions"
    }
}
