import Foundation
import Hummingbird

struct HookResponse: Sendable {
    let json: String

    static func permissionDecision(_ behavior: PermissionBehavior) -> HookResponse {
        HookResponse(json: #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"\#(behavior.rawValue)"}}}"#)
    }

    /// Allow and apply permission_suggestions as updatedPermissions (equivalent to "always allow")
    static func permissionDecisionAlways(permissionSuggestions: [AnyCodable]?, toolName: String) -> HookResponse {
        if let suggestions = permissionSuggestions,
           !suggestions.isEmpty {
            // Extract raw values from AnyCodable and serialize with JSONSerialization
            let rawValues = suggestions.map(\.value)
            if JSONSerialization.isValidJSONObject(rawValues),
               let data = try? JSONSerialization.data(withJSONObject: rawValues),
               let suggestionsJSON = String(data: data, encoding: .utf8) {
                return HookResponse(json: #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":\#(suggestionsJSON)}}}"#)
            }
        }
        // Fallback: construct a toolAlwaysAllow permission from the tool name
        return HookResponse(json: #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"type":"toolAlwaysAllow","tool":"\#(toolName)"}]}}}"#)
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
