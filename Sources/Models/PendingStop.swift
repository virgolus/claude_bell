import Foundation

/// A held Stop hook: the HTTP request from Claude Code stays open until the
/// user replies from the panel (block+reason) or the hold is released
/// (timeout, dismiss, terminal focus, Esc, SessionEnd) — in which case the
/// stop completes normally.
@MainActor
final class PendingStop: Identifiable, ObservableObject {
    let id = UUID()
    let sessionId: String
    let cwd: String
    let transcriptPath: String
    let createdAt: Date
    let expiresAt: Date
    private let continuation: CheckedContinuation<HookResponse, Never>
    private var hasResponded = false

    init(
        sessionId: String,
        cwd: String,
        transcriptPath: String,
        holdSeconds: TimeInterval,
        continuation: CheckedContinuation<HookResponse, Never>
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(holdSeconds)
        self.continuation = continuation
    }

    /// Deliver the user's reply: Claude resumes with the reason text.
    func answer(_ text: String) {
        guard !hasResponded else { return }
        hasResponded = true
        let response = HookResponse.stopBlock(reason: text)
        print("[PendingStop] Answering session \(sessionId): \(response.json)")
        continuation.resume(returning: response)
    }

    /// Release without blocking: the stop completes normally.
    func release() {
        guard !hasResponded else { return }
        hasResponded = true
        print("[PendingStop] Releasing session \(sessionId)")
        continuation.resume(returning: HookResponse.stopAllow())
    }
}
