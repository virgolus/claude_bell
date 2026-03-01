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

    /// Allow and apply permission_suggestions as updatedPermissions (equivalent to "always allow")
    static func permissionDecisionAlways(permissionSuggestions: [AnyCodable]?) -> HookResponse {
        if let suggestions = permissionSuggestions,
           let data = try? JSONEncoder().encode(suggestions),
           let suggestionsJSON = String(data: data, encoding: .utf8) {
            let json = """
            {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":\(suggestionsJSON)}}}
            """
            return HookResponse(json: json)
        }
        // Fallback to simple allow if no suggestions available
        return permissionDecision(.allow)
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
    case allowAlways = "allowAlways" // internal only, handled specially
    case deny = "deny"
}
