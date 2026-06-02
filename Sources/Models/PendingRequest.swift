import Foundation

@MainActor
final class PendingRequest: Identifiable, ObservableObject {
    let id: UUID
    let sessionId: String
    let cwd: String
    let toolName: String
    let toolInput: [String: AnyCodable]
    let transcriptPath: String
    let permissionSuggestions: [AnyCodable]?
    let createdAt: Date
    private let continuation: CheckedContinuation<HookResponse, Never>
    private var hasResponded = false

    var projectName: String {
        RequestStore.shared.sessions[sessionId]?.displayName ?? (cwd as NSString).lastPathComponent
    }

    init(
        id: UUID = UUID(),
        sessionId: String,
        cwd: String,
        toolName: String,
        toolInput: [String: AnyCodable],
        transcriptPath: String,
        permissionSuggestions: [AnyCodable]? = nil,
        continuation: CheckedContinuation<HookResponse, Never>
    ) {
        self.id = id
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolName = toolName
        self.toolInput = toolInput
        self.transcriptPath = transcriptPath
        self.permissionSuggestions = permissionSuggestions
        self.createdAt = Date()
        self.continuation = continuation
    }

    func respond(_ behavior: PermissionBehavior) {
        guard !hasResponded else { return }
        hasResponded = true
        let response: HookResponse
        if behavior == .allowAlways {
            print("[PendingRequest] Always clicked — permissionSuggestions: \(String(describing: permissionSuggestions)), toolName: \(toolName)")
            response = HookResponse.permissionDecisionAlways(permissionSuggestions: permissionSuggestions, toolName: toolName)
        } else {
            response = HookResponse.permissionDecision(behavior)
        }
        print("[PendingRequest] Responding with: \(response.json)")
        continuation.resume(returning: response)
    }

    func respond(allow: Bool) {
        respond(allow ? .allow : .deny)
    }

    /// Allow the tool and provide structured answers (for AskUserQuestion).
    /// Builds a hook response with `decision.updatedInput` containing the original
    /// tool input plus the `answers` (and optional `annotations`) dictionaries.
    func respond(answers: [String: String], annotations: [String: [String: String]]? = nil) {
        guard !hasResponded else { return }
        hasResponded = true
        let response = HookResponse.permissionDecisionAllowWithUpdatedInput(
            originalInput: toolInput,
            answers: answers,
            annotations: annotations
        )
        print("[PendingRequest] Responding with answers: \(response.json)")
        continuation.resume(returning: response)
    }
}
