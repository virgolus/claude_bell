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

    func respond(allow: Bool) {
        let response = HookResponse.permissionDecision(allow: allow)
        continuation.resume(returning: response)
    }
}
