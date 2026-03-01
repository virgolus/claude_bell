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
            let input = try JSONDecoder().decode(HookInput.self, from: body)

            let notificationType = input.notificationType ?? "unknown"
            let relevantTypes = ["permission_prompt", "idle_prompt", "elicitation_dialog"]

            if relevantTypes.contains(notificationType) {
                let entry = NotificationEntry(
                    sessionId: input.sessionId,
                    cwd: input.cwd,
                    notificationType: notificationType,
                    message: input.notificationMessage ?? "",
                    createdAt: Date()
                )
                Task { @MainActor in
                    store.addNotification(entry)
                    NotificationManager.sendNotification(
                        title: "Claude Code",
                        body: input.notificationMessage ?? notificationType
                    )
                }
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
