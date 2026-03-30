import Foundation

enum AutoModeInstaller {
    private static var settingsPath: String {
        NSHomeDirectory() + "/.claude/settings.local.json"
    }

    static var isEnabled: Bool {
        guard let settings = readSettings(),
              let permissions = settings["permissions"] as? [String: Any],
              let mode = permissions["defaultMode"] as? String else {
            return false
        }
        return mode == "auto"
    }

    static func enable() throws {
        var settings = readSettings() ?? [:]
        var permissions = settings["permissions"] as? [String: Any] ?? [:]
        permissions["defaultMode"] = "auto"
        settings["permissions"] = permissions
        try writeSettings(settings)
    }

    static func disable() throws {
        guard var settings = readSettings(),
              var permissions = settings["permissions"] as? [String: Any] else {
            return
        }
        permissions.removeValue(forKey: "defaultMode")
        if permissions.isEmpty {
            settings.removeValue(forKey: "permissions")
        } else {
            settings["permissions"] = permissions
        }
        if settings.isEmpty {
            // Remove the file entirely if nothing left
            try? FileManager.default.removeItem(atPath: settingsPath)
        } else {
            try writeSettings(settings)
        }
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
