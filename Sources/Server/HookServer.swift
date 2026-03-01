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

            let response = await withCheckedContinuation { (continuation: CheckedContinuation<HookResponse, Never>) in
                Task { @MainActor in
                    let pending = PendingRequest(
                        sessionId: input.sessionId,
                        cwd: input.cwd,
                        toolName: input.toolName ?? "Unknown",
                        toolInput: input.toolInput ?? [:],
                        transcriptPath: input.transcriptPath ?? "",
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

                let entry = NotificationEntry(
                    sessionId: input.sessionId,
                    cwd: input.cwd,
                    notificationType: notificationType,
                    message: message,
                    title: title,
                    transcriptPath: input.transcriptPath ?? "",
                    createdAt: Date()
                )
                Task { @MainActor in
                    store.addNotification(entry)
                    Self.sendNativeNotification(for: entry)
                }
            }

            return Response(status: .ok)
        }

        router.post("/hooks/stop") { request, context -> Response in
            let input = try await Self.decodeInput(request, label: "Stop")

            let entry = NotificationEntry(
                sessionId: input.sessionId,
                cwd: input.cwd,
                notificationType: "stop",
                message: input.lastAssistantMessage ?? "",
                title: "",
                transcriptPath: input.transcriptPath ?? "",
                createdAt: Date()
            )
            Task { @MainActor in
                store.addNotification(entry)
                Self.sendNativeNotification(for: entry)
            }

            return Response(status: .ok)
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
                store.addNotification(entry)
                Self.sendNativeNotification(for: entry, body: "\(toolName) failed")
            }

            return Response(status: .ok)
        }

        router.post("/hooks/session-end") { request, context -> Response in
            let input = try await Self.decodeInput(request, label: "SessionEnd")

            Task { @MainActor in
                store.sessions.removeValue(forKey: input.sessionId)

                let entry = NotificationEntry(
                    sessionId: input.sessionId,
                    cwd: input.cwd,
                    notificationType: "session_end",
                    message: "",
                    title: "",
                    transcriptPath: input.transcriptPath ?? "",
                    createdAt: Date()
                )
                store.addNotification(entry)
                Self.sendNativeNotification(for: entry)
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

    private static func sendNativeNotification(for entry: NotificationEntry, body: String? = nil) {
        NotificationManager.sendNotification(
            title: "Claude Code — \(entry.projectName)",
            body: body ?? entry.meta.nativeBody
        )
    }
}
