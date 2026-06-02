import Foundation
import Hummingbird
import NIOCore

final class HookServer: Sendable {
    let store: RequestStore
    let hostname = "127.0.0.1"
    let port = 19485

    init(store: RequestStore) {
        self.store = store
    }

    func start() async throws {
        let store = self.store

        let router = Router()

        router.post("/hooks/permission-request") { request, context -> Response in
            print("[HookServer] Received permission request")
            let body = try await request.body.collect(upTo: 1_048_576)
            let input = try JSONDecoder().decode(HookInput.self, from: body)
            print("[HookServer] Decoded: tool=\(input.toolName ?? "nil"), session=\(input.sessionId)")
            if let raw = String(buffer: body) as String? {
                print("[HookServer] PermissionRequest raw body: \(raw)")
            }

            let lastPrompt = Self.lastUserPrompt(from: input.transcriptPath ?? "")

            let response = await withCheckedContinuation { (continuation: CheckedContinuation<HookResponse, Never>) in
                Task { @MainActor in
                    store.trackSessionPublic(id: input.sessionId, cwd: input.cwd, lastPrompt: lastPrompt)
                    let pending = PendingRequest(
                        sessionId: input.sessionId,
                        cwd: input.cwd,
                        toolName: input.toolName ?? "Unknown",
                        toolInput: input.toolInput ?? [:],
                        transcriptPath: input.transcriptPath ?? "",
                        permissionSuggestions: input.permissionSuggestions,
                        continuation: continuation
                    )
                    store.addRequest(pending)
                }
            }

            return response.toHTTPResponse()
        }

        router.post("/hooks/notification") { request, context -> Response in
            let input = try await Self.decodeInput(request, label: "Notification")

            let notificationType = input.notificationType ?? "unknown"
            let relevantTypes = ["permission_prompt", "idle_prompt", "elicitation_dialog"]

            if relevantTypes.contains(notificationType) {
                let message = Self.filterGenericMessage(
                    input.notificationMessage ?? input.message ?? input.question ?? ""
                )
                let title = Self.filterGenericMessage(input.title ?? "")

                // For idle_prompt: check transcript to see if Claude is genuinely asking
                // something or just finished a task. If no question pending, treat as "stop".
                let effectiveType: String
                let effectiveMessage: String
                if notificationType == "idle_prompt" {
                    let hasQuestion = Self.transcriptHasPendingQuestion(path: input.transcriptPath ?? "")
                    if hasQuestion {
                        effectiveType = notificationType
                        effectiveMessage = message
                    } else {
                        effectiveType = "stop"
                        // Use last assistant message from transcript as body
                        effectiveMessage = message.isEmpty
                            ? Self.lastAssistantMessage(from: input.transcriptPath ?? "")
                            : message
                    }
                } else {
                    effectiveType = notificationType
                    effectiveMessage = message
                }

                let entry = NotificationEntry(
                    sessionId: input.sessionId,
                    cwd: input.cwd,
                    notificationType: effectiveType,
                    message: effectiveMessage,
                    title: title,
                    transcriptPath: input.transcriptPath ?? "",
                    createdAt: Date()
                )
                Task { @MainActor in
                    // Clean stale notifications (but NOT permission requests)
                    if notificationType != "permission_prompt" {
                        store.sessionAdvanced(id: input.sessionId)
                    }
                    store.addNotification(entry)
                }
            }

            return Response(status: .ok)
        }

        router.post("/hooks/stop") { request, context -> Response in
            let input = try await Self.decodeInput(request, label: "Stop")

            // Check if the last assistant message is actually a question —
            // if so, show as interactive idle_prompt instead of passive stop.
            let hasQuestion = Self.transcriptHasPendingQuestion(path: input.transcriptPath ?? "")
            let effectiveType = hasQuestion ? "idle_prompt" : "stop"

            let entry = NotificationEntry(
                sessionId: input.sessionId,
                cwd: input.cwd,
                notificationType: effectiveType,
                message: input.lastAssistantMessage ?? "",
                title: "",
                transcriptPath: input.transcriptPath ?? "",
                createdAt: Date()
            )

            let sessionId = input.sessionId
            let cwd = input.cwd
            let transcriptPath = input.transcriptPath ?? ""
            let holdSeconds = TimeInterval(DirectReplySettings.holdSeconds)

            // Hold the request open: a panel reply resumes it with
            // {"decision":"block","reason":…}; timeout/dismiss/focus/SessionEnd
            // resume it with {} (normal stop). Esc in the terminal aborts the
            // connection → onCancel releases the hold.
            let response = await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<HookResponse, Never>) in
                    Task { @MainActor in
                        let pending = PendingStop(
                            sessionId: sessionId,
                            cwd: cwd,
                            transcriptPath: transcriptPath,
                            holdSeconds: holdSeconds,
                            continuation: continuation
                        )
                        store.registerStopHold(pending)
                        store.sessionAdvanced(id: sessionId)
                        store.addNotification(entry)
                    }
                }
            } onCancel: {
                // Connection aborted (Esc / Claude exited). If this races the
                // registration task and finds nothing, the hold timer is the
                // backstop: it resumes the orphan continuation at expiry and
                // the response is discarded on the dead connection.
                Task { @MainActor in
                    store.releaseStopHold(sessionId: sessionId)
                }
            }

            return response.toHTTPResponse()
        }

        router.post("/hooks/post-tool-use-failure") { request, context -> Response in
            let input = try await Self.decodeInput(request, label: "PostToolUseFailure")

            let toolName = input.toolName ?? "Unknown"
            let errorMsg = input.error ?? input.toolResult ?? "Unknown error"
            let entry = NotificationEntry(
                sessionId: input.sessionId,
                cwd: input.cwd,
                notificationType: "tool_error",
                message: "**\(toolName)** failed:\n\n\(errorMsg)",
                title: "",
                transcriptPath: input.transcriptPath ?? "",
                createdAt: Date()
            )
            Task { @MainActor in
                store.sessionAdvanced(id: input.sessionId)
                store.addNotification(entry)
            }

            return Response(status: .ok)
        }

        router.post("/hooks/session-end") { request, context -> Response in
            let input = try await Self.decodeInput(request, label: "SessionEnd")

            Task { @MainActor in
                // Only remove interactive notifications (they can't be answered after session ends).
                // Keep passive ones (stop, tool_error) so the user can still see them.
                store.notifications.removeAll {
                    $0.sessionId == input.sessionId && !$0.meta.isPassive
                }
                store.removeSession(id: input.sessionId)
            }

            return Response(status: .ok)
        }

        router.post("/hooks/pre-tool-use") { request, context -> Response in
            let input = try await Self.decodeInput(request, label: "PreToolUse")
            // Check if session already has a prompt before doing I/O
            let needsPrompt = await MainActor.run { store.sessions[input.sessionId]?.lastPrompt == nil }
            let lastPrompt = needsPrompt ? Self.lastUserPrompt(from: input.transcriptPath ?? "") : nil
            Task { @MainActor in
                store.sessionAdvanced(id: input.sessionId)
                store.trackSessionPublic(id: input.sessionId, cwd: input.cwd, lastPrompt: lastPrompt)
            }
            return Response(status: .ok)
        }

        router.post("/hooks/user-prompt-submit") { request, context -> Response in
            let input = try await Self.decodeInput(request, label: "UserPromptSubmit")
            Task { @MainActor in
                // The user replied in the terminal: release any hold for the
                // session (defensive — a live hold can't normally coexist with
                // a prompt submission) and dismiss its stale notifications.
                store.releaseStopHold(sessionId: input.sessionId)
                store.sessionAdvanced(id: input.sessionId)
                store.trackSessionPublic(id: input.sessionId, cwd: input.cwd)
            }
            return Response(status: .ok)
        }

        router.get("/health") { _, _ -> Response in
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: "{\"status\":\"ok\"}"))
            )
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname(hostname, port: port))
        )
        try await app.run()
    }

    // MARK: - Helpers

    private static func decodeInput(_ request: Request, label: String) async throws -> HookInput {
        let body = try await request.body.collect(upTo: 1_048_576)
        if let raw = String(buffer: body) as String? {
            print("[HookServer] \(label) raw body: \(raw)")
        }
        return try JSONDecoder().decode(HookInput.self, from: body)
    }

    private static let genericMessages = [
        "claude is waiting for your input",
        "claude needs your input",
        "waiting for input",
        "claude code needs your permission",
        "claude needs your permission",
        "permission required",
        "needs your permission to use",
    ]

    private static func filterGenericMessage(_ text: String) -> String {
        let lower = text.lowercased()
        return genericMessages.contains(where: { lower.contains($0) }) ? "" : text
    }

    /// Extract the last user prompt from the transcript.
    static func lastUserPrompt(from path: String) -> String? {
        guard !path.isEmpty,
              let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String, type == "user",
                  let message = json["message"] as? [String: Any] else {
                continue
            }

            var textParts: [String] = []
            if let contentArray = message["content"] as? [[String: Any]] {
                for block in contentArray {
                    if let blockType = block["type"] as? String, blockType == "text",
                       let text = block["text"] as? String {
                        textParts.append(text)
                    }
                }
            } else if let contentString = message["content"] as? String {
                textParts.append(contentString)
            }

            let combined = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip system messages like "[Request interrupted by user...]"
            if !combined.isEmpty && !combined.hasPrefix("[") {
                return combined
            }
        }

        return nil
    }

    /// Extract the last assistant text message from the transcript.
    private static func lastAssistantMessage(from path: String) -> String {
        guard !path.isEmpty,
              let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return ""
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String, type == "assistant",
                  let message = json["message"] as? [String: Any] else {
                continue
            }

            var textParts: [String] = []
            if let contentArray = message["content"] as? [[String: Any]] {
                for block in contentArray {
                    if let blockType = block["type"] as? String, blockType == "text",
                       let text = block["text"] as? String {
                        textParts.append(text)
                    }
                }
            } else if let contentString = message["content"] as? String {
                textParts.append(contentString)
            }

            let combined = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !combined.isEmpty { return combined }
        }

        return ""
    }

    /// Check if the transcript's last assistant message contains a pending question
    /// (AskUserQuestion tool call, or text ending with '?'). If not, the idle_prompt
    /// is really a task completion.
    private static func transcriptHasPendingQuestion(path: String) -> Bool {
        guard !path.isEmpty,
              let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return false
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Scan backwards for the last assistant message
        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String, type == "assistant",
                  let message = json["message"] as? [String: Any] else {
                continue
            }

            // Check for AskUserQuestion tool use
            if let contentArray = message["content"] as? [[String: Any]] {
                for block in contentArray {
                    if let blockType = block["type"] as? String,
                       blockType == "tool_use",
                       let name = block["name"] as? String,
                       name == "AskUserQuestion" {
                        return true
                    }
                }

                // Check if the last text block ends with a question
                let textBlocks = contentArray.compactMap { block -> String? in
                    guard let t = block["type"] as? String, t == "text",
                          let text = block["text"] as? String else { return nil }
                    return text
                }
                if let lastText = textBlocks.last?.trimmingCharacters(in: .whitespacesAndNewlines),
                   lastText.hasSuffix("?") {
                    return true
                }
            }

            return false
        }

        return false
    }
}
