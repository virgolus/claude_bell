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
            let rawValues = suggestions.map(\.value)
            if JSONSerialization.isValidJSONObject(rawValues),
               let data = try? JSONSerialization.data(withJSONObject: rawValues),
               let suggestionsJSON = String(data: data, encoding: .utf8) {
                return HookResponse(json: #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":\#(suggestionsJSON)}}}"#)
            }
            print("[HookResponse] WARNING: permissionSuggestions serialization failed, falling back")
        }
        // Fallback: JSON-escape the tool name properly
        let escapedTool: String
        if let data = try? JSONSerialization.data(withJSONObject: toolName),
           let s = String(data: data, encoding: .utf8) {
            escapedTool = s
        } else {
            escapedTool = "\"\(toolName)\""
        }
        return HookResponse(json: "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\",\"updatedPermissions\":[{\"type\":\"toolAlwaysAllow\",\"tool\":\(escapedTool)}]}}}")
    }

    static func permissionDecision(allow: Bool) -> HookResponse {
        permissionDecision(allow ? .allow : .deny)
    }

    /// Allow the tool and inject the user's answers into the tool input.
    /// Used for AskUserQuestion: Claude Code ≥ 2.1.150 no longer shows a TUI picker,
    /// so the hook must populate `answers` (and optionally `annotations`) via
    /// `decision.updatedInput`. Parser in the CLI: `decision.updatedInput` becomes
    /// the new tool input, and AskUserQuestion.call() echoes it back as the result.
    static func permissionDecisionAllowWithUpdatedInput(
        originalInput: [String: AnyCodable],
        answers: [String: String],
        annotations: [String: [String: String]]? = nil
    ) -> HookResponse {
        var updatedInput: [String: Any] = originalInput.mapValues { $0.value }
        updatedInput["answers"] = answers
        if let annotations, !annotations.isEmpty {
            updatedInput["annotations"] = annotations
        }

        let payload: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": [
                    "behavior": "allow",
                    "updatedInput": updatedInput
                ]
            ]
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            print("[HookResponse] WARNING: updatedInput serialization failed, falling back to plain allow")
            return permissionDecision(.allow)
        }
        return HookResponse(json: json)
    }

    /// Stop hook: block the stop and deliver the user's panel reply as the
    /// reason. Claude Code injects it into the conversation as
    /// "Stop hook feedback: <reason>" and resumes working on it.
    static func stopBlock(reason userText: String) -> HookResponse {
        let payload: [String: Any] = [
            "decision": "block",
            "reason": "L'utente ha risposto da ClaudeBell: \(userText)"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            print("[HookResponse] WARNING: stopBlock serialization failed, falling back")
            return HookResponse(json: #"{"decision":"block","reason":"L'utente ha risposto da ClaudeBell (testo non serializzabile)."}"#)
        }
        return HookResponse(json: json)
    }

    /// Stop hook: let the stop complete normally (release without blocking).
    static func stopAllow() -> HookResponse {
        HookResponse(json: "{}")
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
