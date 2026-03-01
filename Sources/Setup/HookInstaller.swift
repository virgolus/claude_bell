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

        // Stop hook (agent finished)
        let stopHook: [String: Any] = [
            "matcher": "",
            "hooks": [[
                "type": "http",
                "url": "http://localhost:19485/hooks/stop",
                "timeout": 10
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

        settings["hooks"] = hooks
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

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
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
