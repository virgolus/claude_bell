import Foundation
import Hummingbird

struct HookResponse: Sendable {
    let json: String

    static func permissionDecision(allow: Bool) -> HookResponse {
        let behavior = allow ? "allow" : "deny"
        let json = """
        {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"\(behavior)"}}}
        """
        return HookResponse(json: json)
    }

    func toHTTPResponse() -> Response {
        Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: json))
        )
    }
}
