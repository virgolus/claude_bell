import Foundation

@MainActor
final class PendingRequest: Identifiable, ObservableObject {
    let id = UUID()
    let sessionId: String
    let cwd: String
    let toolName: String
    let toolInput: [String: AnyCodable]
    let transcriptPath: String
    let createdAt: Date
    private let continuation: CheckedContinuation<HookResponse, Never>
    private var hasResponded = false

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    init(
        sessionId: String,
        cwd: String,
        toolName: String,
        toolInput: [String: AnyCodable],
        transcriptPath: String,
        continuation: CheckedContinuation<HookResponse, Never>
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolName = toolName
        self.toolInput = toolInput
        self.transcriptPath = transcriptPath
        self.createdAt = Date()
        self.continuation = continuation
    }

    func respond(_ behavior: PermissionBehavior) {
        guard !hasResponded else { return }
        hasResponded = true
        let response = HookResponse.permissionDecision(behavior)
        continuation.resume(returning: response)
    }

    func respond(allow: Bool) {
        respond(allow ? .allow : .deny)
    }
}
