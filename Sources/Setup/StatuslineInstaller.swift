import Foundation

enum StatuslineInstaller {
    private static var settingsPath: String {
        NSHomeDirectory() + "/.claude/settings.json"
    }

    private static var scriptPath: String {
        NSHomeDirectory() + "/.claude/statusline-command.sh"
    }

    static let script = """
        #!/usr/bin/env bash
        input=$(cat)
        MODEL=$(echo "$input" | jq -r '.model.display_name')
        DIR=$(echo "$input" | jq -r '.workspace.current_dir')
        PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
        DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
        IN_TOK=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
        OUT_TOK=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
        IN_K=$(awk "BEGIN{printf \\"%.0f\\", $IN_TOK/1000}")
        OUT_K=$(awk "BEGIN{printf \\"%.0f\\", $OUT_TOK/1000}")
        LAST_IN=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
        LAST_OUT=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // 0')
        LAST_IN_K=$(awk "BEGIN{printf \\"%.1f\\", $LAST_IN/1000}")
        LAST_OUT_K=$(awk "BEGIN{printf \\"%.1f\\", $LAST_OUT/1000}")
        CYAN=$(tput setaf 6)
        GREEN=$(tput setaf 2)
        YELLOW=$(tput setaf 3)
        RED=$(tput setaf 1)
        RESET=$(tput sgr0)
        if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
        elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
        else BAR_COLOR="$GREEN"; fi
        FILLED=$((PCT / 10)); EMPTY=$((10 - FILLED))
        BAR=$(printf "%${FILLED}s" | tr ' ' '█')$(printf "%${EMPTY}s" | tr ' ' '░')
        MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))
        BRANCH=""
        git rev-parse --git-dir > /dev/null 2>&1 && BRANCH=" | 🌿 $(git branch --show-current 2>/dev/null)"
        echo "${CYAN}[${MODEL}]${RESET} 📁 ${DIR##*/}${BRANCH}"
        echo "${BAR_COLOR}${BAR}${RESET} ${PCT}% | ⏱️  ${MINS}m ${SECS}s | Σ ↓${IN_K}k ↑${OUT_K}k | last ↓${LAST_IN_K}k ↑${LAST_OUT_K}k"
        """

    static var isInstalled: Bool {
        guard let settings = readSettings(),
              let statusLine = settings["statusLine"] as? [String: Any],
              let type = statusLine["type"] as? String,
              type == "command",
              let command = statusLine["command"] as? String else {
            return false
        }
        return command.contains("statusline-command.sh")
    }

    static func install() throws {
        // Write the script file
        let dir = (scriptPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath
        )

        // Update settings.json
        var settings = readSettings() ?? [:]
        settings["statusLine"] = [
            "type": "command",
            "command": "bash \(scriptPath)"
        ] as [String: Any]
        try writeSettings(settings)
    }

    static func uninstall() throws {
        var settings = readSettings() ?? [:]
        settings.removeValue(forKey: "statusLine")
        try writeSettings(settings)

        // Remove script file
        try? FileManager.default.removeItem(atPath: scriptPath)
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
