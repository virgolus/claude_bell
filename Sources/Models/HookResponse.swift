import Foundation
import Hummingbird

struct HookResponse: Sendable {
    let json: String

    static func permissionDecision(_ behavior: PermissionBehavior) -> HookResponse {
        let json = """
        {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"\(behavior.rawValue)"}}}
        """
        return HookResponse(json: json)
    }

    static func permissionDecision(allow: Bool) -> HookResponse {
        permissionDecision(allow ? .allow : .deny)
    }

    func toHTTPResponse() -> Response {
        Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: json))
        )
    }
}

enum PermissionBehavior: String, Sendable {
    case allow = "allow"
    case allowForSession = "allowForSession"
    case deny = "deny"
}
