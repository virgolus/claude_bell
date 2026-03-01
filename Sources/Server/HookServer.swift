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
                    print("[HookServer] Creating PendingRequest on MainActor")
                    let pending = PendingRequest(
                        sessionId: input.sessionId,
                        cwd: input.cwd,
                        toolName: input.toolName ?? "Unknown",
                        toolInput: input.toolInput ?? [:],
                        transcriptPath: input.transcriptPath ?? "",
                        continuation: continuation
                    )
                    store.addRequest(pending)
                    print("[HookServer] Added to store, count=\(store.pendingRequests.count)")
                }
            }

            print("[HookServer] Got response, sending back")
            return response.toHTTPResponse()
        }

        router.post("/hooks/notification") { request, context -> Response in
            let body = try await request.body.collect(upTo: 1_048_576)
            if let raw = String(buffer: body) as String? {
                print("[HookServer] Notification raw body: \(raw)")
            }
            let input = try JSONDecoder().decode(HookInput.self, from: body)

            let notificationType = input.notificationType ?? "unknown"
            let relevantTypes = ["permission_prompt", "idle_prompt", "elicitation_dialog"]

            if relevantTypes.contains(notificationType) {
                let rawMessage = input.notificationMessage ?? input.message ?? input.question ?? ""
                // Filter out generic/redundant messages from Claude Code
                let genericMessages = [
                    "claude is waiting for your input",
                    "claude needs your input",
                    "waiting for input",
                    "claude code needs your permission",
                    "permission required",
                ]
                let displayMessage = genericMessages.contains(where: { rawMessage.lowercased().contains($0) }) ? "" : rawMessage
                let rawTitle = input.title ?? ""
                let displayTitle = genericMessages.contains(where: { rawTitle.lowercased().contains($0) }) ? "" : rawTitle
                let entry = NotificationEntry(
                    sessionId: input.sessionId,
                    cwd: input.cwd,
                    notificationType: notificationType,
                    message: displayMessage,
                    title: displayTitle,
                    transcriptPath: input.transcriptPath ?? "",
                    createdAt: Date()
                )
                Task { @MainActor in
                    store.addNotification(entry)
                    let nativeBody: String
                    switch notificationType {
                    case "idle_prompt": nativeBody = "Waiting for your input"
                    case "elicitation_dialog": nativeBody = "Has a question for you"
                    case "permission_prompt": nativeBody = "Needs permission"
                    default: nativeBody = notificationType
                    }
                    NotificationManager.sendNotification(
                        title: "Claude Code — \(entry.projectName)",
                        body: nativeBody
                    )
                }
            }

            return Response(status: .ok)
        }

        router.post("/hooks/stop") { request, context -> Response in
            let body = try await request.body.collect(upTo: 1_048_576)
            if let raw = String(buffer: body) as String? {
                print("[HookServer] Stop raw body: \(raw)")
            }
            let input = try JSONDecoder().decode(HookInput.self, from: body)

            let stopMessage = input.lastAssistantMessage ?? ""
            let entry = NotificationEntry(
                sessionId: input.sessionId,
                cwd: input.cwd,
                notificationType: "stop",
                message: stopMessage,
                title: "Task Completed",
                transcriptPath: input.transcriptPath ?? "",
                createdAt: Date()
            )
            Task { @MainActor in
                store.addNotification(entry)
                NotificationManager.sendNotification(
                    title: "Claude Code — \(entry.projectName)",
                    body: "Task completed"
                )
            }

            return Response(status: .ok)
        }

        router.post("/hooks/post-tool-use-failure") { request, context -> Response in
            let body = try await request.body.collect(upTo: 1_048_576)
            if let raw = String(buffer: body) as String? {
                print("[HookServer] PostToolUseFailure raw body: \(raw)")
            }
            let input = try JSONDecoder().decode(HookInput.self, from: body)

            let toolName = input.toolName ?? "Unknown"
            let errorMsg = input.error ?? input.toolResult ?? "Unknown error"
            let entry = NotificationEntry(
                sessionId: input.sessionId,
                cwd: input.cwd,
                notificationType: "tool_error",
                message: "**\(toolName)** failed:\n\n\(errorMsg)",
                title: "Tool Error",
                transcriptPath: input.transcriptPath ?? "",
                createdAt: Date()
            )
            Task { @MainActor in
                store.addNotification(entry)
                NotificationManager.sendNotification(
                    title: "Claude Code — \(entry.projectName)",
                    body: "\(toolName) failed"
                )
            }

            return Response(status: .ok)
        }

        router.post("/hooks/session-end") { request, context -> Response in
            let body = try await request.body.collect(upTo: 1_048_576)
            if let raw = String(buffer: body) as String? {
                print("[HookServer] SessionEnd raw body: \(raw)")
            }
            let input = try JSONDecoder().decode(HookInput.self, from: body)

            Task { @MainActor in
                // Remove session from tracked sessions
                store.sessions.removeValue(forKey: input.sessionId)
                // Add notification
                let entry = NotificationEntry(
                    sessionId: input.sessionId,
                    cwd: input.cwd,
                    notificationType: "session_end",
                    message: "",
                    title: "Session Ended",
                    transcriptPath: input.transcriptPath ?? "",
                    createdAt: Date()
                )
                store.addNotification(entry)
                NotificationManager.sendNotification(
                    title: "Claude Code — \(entry.projectName)",
                    body: "Session ended"
                )
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
}
