import Foundation

enum HookInstaller {
    private static var settingsPath: String {
        NSHomeDirectory() + "/.claude/settings.json"
    }

    static var isInstalled: Bool {
        guard let settings = readSettings(),
              let hooks = settings["hooks"] as? [String: Any],
              let permReq = hooks["PermissionRequest"] as? [[String: Any]] else {
            return false
        }
        return permReq.contains { entry in
            if let hooksList = entry["hooks"] as? [[String: Any]] {
                return hooksList.contains { h in
                    (h["url"] as? String)?.contains("19485") == true
                }
            }
            return false
        }
    }

    static func install() throws {
        var settings = readSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        // PermissionRequest hook
        let permHook: [String: Any] = [
            "matcher": "",
            "hooks": [[
                "type": "http",
                "url": "http://localhost:19485/hooks/permission-request",
                "timeout": 300
            ] as [String: Any]]
        ]

        var permArray = hooks["PermissionRequest"] as? [[String: Any]] ?? []
        // Remove existing Claude Bell entries
        permArray.removeAll { entry in
            if let hooksList = entry["hooks"] as? [[String: Any]] {
                return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
            }
            return false
        }
        permArray.append(permHook)
        hooks["PermissionRequest"] = permArray

        // Stop hook (agent finished) — long-poll for direct replies.
        // Timeout = hold duration + 60 s margin so ClaudeBell always
        // self-releases before Claude Code gives up on the hook.
        let stopHook: [String: Any] = [
            "matcher": "",
            "hooks": [[
                "type": "http",
                "url": "http://localhost:19485/hooks/stop",
                "timeout": DirectReplySettings.hookTimeoutSeconds
            ] as [String: Any]]
        ]

        var stopArray = hooks["Stop"] as? [[String: Any]] ?? []
        stopArray.removeAll { entry in
            if let hooksList = entry["hooks"] as? [[String: Any]] {
                return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
            }
            return false
        }
        stopArray.append(stopHook)
        hooks["Stop"] = stopArray

        // PostToolUseFailure hook
        let toolFailHook: [String: Any] = [
            "matcher": "",
            "hooks": [[
                "type": "http",
                "url": "http://localhost:19485/hooks/post-tool-use-failure",
                "timeout": 10
            ] as [String: Any]]
        ]

        var toolFailArray = hooks["PostToolUseFailure"] as? [[String: Any]] ?? []
        toolFailArray.removeAll { entry in
            if let hooksList = entry["hooks"] as? [[String: Any]] {
                return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
            }
            return false
        }
        toolFailArray.append(toolFailHook)
        hooks["PostToolUseFailure"] = toolFailArray

        // SessionEnd hook
        let sessionEndHook: [String: Any] = [
            "matcher": "",
            "hooks": [[
                "type": "http",
                "url": "http://localhost:19485/hooks/session-end",
                "timeout": 10
            ] as [String: Any]]
        ]

        var sessionEndArray = hooks["SessionEnd"] as? [[String: Any]] ?? []
        sessionEndArray.removeAll { entry in
            if let hooksList = entry["hooks"] as? [[String: Any]] {
                return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
            }
            return false
        }
        sessionEndArray.append(sessionEndHook)
        hooks["SessionEnd"] = sessionEndArray

        // PreToolUse hook (session advancement detection)
        let preToolHook: [String: Any] = [
            "matcher": "",
            "hooks": [[
                "type": "http",
                "url": "http://localhost:19485/hooks/pre-tool-use",
                "timeout": 10
            ] as [String: Any]]
        ]

        var preToolArray = hooks["PreToolUse"] as? [[String: Any]] ?? []
        preToolArray.removeAll { entry in
            if let hooksList = entry["hooks"] as? [[String: Any]] {
                return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
            }
            return false
        }
        preToolArray.append(preToolHook)
        hooks["PreToolUse"] = preToolArray

        // Notification hook
        let notifHook: [String: Any] = [
            "matcher": "permission_prompt|idle_prompt|elicitation_dialog",
            "hooks": [[
                "type": "http",
                "url": "http://localhost:19485/hooks/notification",
                "timeout": 10
            ] as [String: Any]]
        ]

        var notifArray = hooks["Notification"] as? [[String: Any]] ?? []
        notifArray.removeAll { entry in
            if let hooksList = entry["hooks"] as? [[String: Any]] {
                return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
            }
            return false
        }
        notifArray.append(notifHook)
        hooks["Notification"] = notifArray

        // UserPromptSubmit hook (user replied in terminal → dismiss stale notifications)
        let promptSubmitHook: [String: Any] = [
            "matcher": "",
            "hooks": [[
                "type": "http",
                "url": "http://localhost:19485/hooks/user-prompt-submit",
                "timeout": 10
            ] as [String: Any]]
        ]

        var promptSubmitArray = hooks["UserPromptSubmit"] as? [[String: Any]] ?? []
        promptSubmitArray.removeAll { entry in
            if let hooksList = entry["hooks"] as? [[String: Any]] {
                return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
            }
            return false
        }
        promptSubmitArray.append(promptSubmitHook)
        hooks["UserPromptSubmit"] = promptSubmitArray

        settings["hooks"] = hooks

        // Each panel reply is one Stop-hook "block". Claude Code's default cap
        // of 8 consecutive blocks would kill long question chains (e.g.
        // superpowers brainstorming). Only set it when the user hasn't.
        var env = settings["env"] as? [String: Any] ?? [:]
        if env["CLAUDE_CODE_STOP_HOOK_BLOCK_CAP"] == nil {
            env["CLAUDE_CODE_STOP_HOOK_BLOCK_CAP"] = "50"
        }
        settings["env"] = env

        try writeSettings(settings)
    }

    static func uninstall() throws {
        guard var settings = readSettings(),
              var hooks = settings["hooks"] as? [String: Any] else {
            return
        }

        // Remove Claude Bell entries from PermissionRequest
        if var permArray = hooks["PermissionRequest"] as? [[String: Any]] {
            permArray.removeAll { entry in
                if let hooksList = entry["hooks"] as? [[String: Any]] {
                    return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
                }
                return false
            }
            if permArray.isEmpty {
                hooks.removeValue(forKey: "PermissionRequest")
            } else {
                hooks["PermissionRequest"] = permArray
            }
        }

        // Remove Claude Bell entries from Stop
        if var stopArray = hooks["Stop"] as? [[String: Any]] {
            stopArray.removeAll { entry in
                if let hooksList = entry["hooks"] as? [[String: Any]] {
                    return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
                }
                return false
            }
            if stopArray.isEmpty {
                hooks.removeValue(forKey: "Stop")
            } else {
                hooks["Stop"] = stopArray
            }
        }

        // Remove Claude Bell entries from PostToolUseFailure
        if var toolFailArray = hooks["PostToolUseFailure"] as? [[String: Any]] {
            toolFailArray.removeAll { entry in
                if let hooksList = entry["hooks"] as? [[String: Any]] {
                    return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
                }
                return false
            }
            if toolFailArray.isEmpty {
                hooks.removeValue(forKey: "PostToolUseFailure")
            } else {
                hooks["PostToolUseFailure"] = toolFailArray
            }
        }

        // Remove Claude Bell entries from SessionEnd
        if var sessionEndArray = hooks["SessionEnd"] as? [[String: Any]] {
            sessionEndArray.removeAll { entry in
                if let hooksList = entry["hooks"] as? [[String: Any]] {
                    return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
                }
                return false
            }
            if sessionEndArray.isEmpty {
                hooks.removeValue(forKey: "SessionEnd")
            } else {
                hooks["SessionEnd"] = sessionEndArray
            }
        }

        // Remove Claude Bell entries from PreToolUse
        if var preToolArray = hooks["PreToolUse"] as? [[String: Any]] {
            preToolArray.removeAll { entry in
                if let hooksList = entry["hooks"] as? [[String: Any]] {
                    return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
                }
                return false
            }
            if preToolArray.isEmpty {
                hooks.removeValue(forKey: "PreToolUse")
            } else {
                hooks["PreToolUse"] = preToolArray
            }
        }

        // Remove Claude Bell entries from Notification
        if var notifArray = hooks["Notification"] as? [[String: Any]] {
            notifArray.removeAll { entry in
                if let hooksList = entry["hooks"] as? [[String: Any]] {
                    return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
                }
                return false
            }
            if notifArray.isEmpty {
                hooks.removeValue(forKey: "Notification")
            } else {
                hooks["Notification"] = notifArray
            }
        }

        // Remove Claude Bell entries from UserPromptSubmit
        if var promptSubmitArray = hooks["UserPromptSubmit"] as? [[String: Any]] {
            promptSubmitArray.removeAll { entry in
                if let hooksList = entry["hooks"] as? [[String: Any]] {
                    return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
                }
                return false
            }
            if promptSubmitArray.isEmpty {
                hooks.removeValue(forKey: "UserPromptSubmit")
            } else {
                hooks["UserPromptSubmit"] = promptSubmitArray
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        // Remove the block cap only if it is still our value
        if var env = settings["env"] as? [String: Any],
           env["CLAUDE_CODE_STOP_HOOK_BLOCK_CAP"] as? String == "50" {
            env.removeValue(forKey: "CLAUDE_CODE_STOP_HOOK_BLOCK_CAP")
            if env.isEmpty {
                settings.removeValue(forKey: "env")
            } else {
                settings["env"] = env
            }
        }

        try writeSettings(settings)
    }

    // MARK: - Private

    private static func readSettings() -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let dir = (settingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: settingsPath))
    }
}
