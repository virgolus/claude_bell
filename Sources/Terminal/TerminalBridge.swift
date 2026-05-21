import Foundation
import AppKit
enum TerminalBridge {

    /// Sends text to a Terminal.app tab whose process matches Claude Code.
    /// Uses clipboard paste (Cmd+V) + Return for reliability.
    static func sendText(_ text: String, toCwd cwd: String, transcriptPath: String = "") {
        logToFile("sendText: \"\(text)\" → cwd: \(cwd), transcript: \(transcriptPath)")
        let resolvedTty = resolveTty(fromTranscriptPath: transcriptPath)

        // Save clipboard, put text, paste+enter, restore clipboard
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let sent = sendiTerm2Paste(cwd: cwd, tty: resolvedTty) || sendTerminalPaste(cwd: cwd, tty: resolvedTty) || sendWarpPaste()

        // Restore clipboard after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let old = oldContents {
                pasteboard.setString(old, forType: .string)
            }
        }

        if !sent { activateTerminal() }
    }

    /// Sends two texts sequentially: first text + Enter, then after a delay, second text + Enter.
    /// Used for "type something else" options where Claude Code expects the option number first,
    /// then the actual text after it prompts.
    static func sendTextTwoStep(_ first: String, then second: String, toCwd cwd: String, transcriptPath: String = "") {
        logToFile("sendTextTwoStep: first=\"\(first)\", then=\"\(second)\" → cwd: \(cwd)")
        sendText(first, toCwd: cwd, transcriptPath: transcriptPath)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            sendText(second, toCwd: cwd, transcriptPath: transcriptPath)
        }
    }

    /// Opens a new terminal tab/window at `cwd` and launches `claude` (optionally with an initial prompt).
    /// Picks Terminal.app or iTerm2 based on which is frontmost; falls back to Terminal.app otherwise.
    static func openNewSession(cwd: String, initialPrompt: String = "") {
        let trimmedCwd = cwd.trimmingCharacters(in: .whitespaces)
        guard !trimmedCwd.isEmpty else { return }
        logToFile("openNewSession: cwd=\(trimmedCwd), prompt=\"\(initialPrompt)\"")

        let cwdLit = shellEscape(trimmedCwd)
        let promptTrimmed = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = promptTrimmed.isEmpty
            ? "cd \(cwdLit) && claude"
            : "cd \(cwdLit) && claude \(shellEscape(promptTrimmed))"

        DispatchQueue.global(qos: .userInitiated).async {
            let target = resolveLaunchTarget()
            switch target {
            case .iterm2:
                if openIterm2NewSession(command: command) { return }
                if openTerminalAppNewSession(command: command) { return }
            case .terminalApp:
                if openTerminalAppNewSession(command: command) { return }
            }
            DispatchQueue.main.async { activateTerminal() }
        }
    }

    private enum LaunchTarget { case terminalApp, iterm2 }

    /// Pick the terminal app to use for a brand-new session. Prefers frontmost,
    /// otherwise any running supported terminal, otherwise Terminal.app.
    private static func resolveLaunchTarget() -> LaunchTarget {
        if let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            if frontmost == "com.googlecode.iterm2" { return .iterm2 }
            if frontmost == "com.apple.Terminal" { return .terminalApp }
        }
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        if running.contains("com.googlecode.iterm2") { return .iterm2 }
        return .terminalApp
    }

    private static func openTerminalAppNewSession(command: String) -> Bool {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
            return true
        end tell
        """
        return runAppleScript(script)
    }

    private static func openIterm2NewSession(command: String) -> Bool {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm2"
            activate
            if (count of windows) = 0 then
                set newWindow to (create window with default profile)
                tell current session of newWindow to write text "\(escaped)"
            else
                tell current window
                    set newTab to (create tab with default profile)
                    tell current session of newTab to write text "\(escaped)"
                end tell
            end if
            return true
        end tell
        """
        return runAppleScript(script)
    }

    /// Brings the terminal tab running Claude Code to the front.
    /// Runs AppleScript matching off the main thread to avoid blocking the UI.
    static func focusTerminalTab(forCwd cwd: String, transcriptPath: String = "") {
        let resolvedTty = resolveTty(fromTranscriptPath: transcriptPath)
        DispatchQueue.global(qos: .userInitiated).async {
            if focusiTerm2(cwd: cwd, tty: resolvedTty) { return }
            if focusTerminal(cwd: cwd, tty: resolvedTty) { return }
            DispatchQueue.main.async { activateTerminal() }
        }
    }

    // MARK: - TTY Resolution

    /// Resolve the tty of the Claude process that owns a transcript file.
    /// Chain: lsof <transcriptPath> → PID → ps -o tty= -p <PID> → /dev/ttysXXX
    private static func resolveTty(fromTranscriptPath path: String) -> String? {
        guard !path.isEmpty else { return nil }
        logToFile("resolveTty: looking up transcript \(path)")
        // Find PID of process with this file open
        guard let pid = shell("lsof -t \(shellEscape(path)) 2>/dev/null | head -1"),
              !pid.isEmpty else {
            logToFile("resolveTty: no PID found for transcript")
            return nil
        }
        logToFile("resolveTty: PID=\(pid)")
        // Get tty for that PID
        guard let ttyRaw = shell("ps -o tty= -p \(pid) 2>/dev/null"),
              !ttyRaw.isEmpty else {
            logToFile("resolveTty: no tty found for PID \(pid)")
            return nil
        }
        let tty = "/dev/\(ttyRaw)"
        logToFile("resolveTty: resolved tty=\(tty)")
        return tty
    }

    /// Run a shell command and return trimmed stdout, or nil on failure.
    private static func shell(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shell-escape a path for use in shell commands.
    private static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Terminal.app

    /// Builds an AppleScript that finds the correct Terminal.app tab by checking each tab's
    /// tty via `lsof` to get the real cwd, instead of relying on window name (which only
    /// reflects the active tab's title).
    ///
    /// Pass 0: exact tty match (resolved from transcript) → most reliable
    /// Pass 1: tab has "claude" in processes AND tty cwd matches → exact match
    /// Pass 2: tab has "claude" in processes → fallback (any claude tab)
    /// Pass 3: tty cwd matches (claude may have exited) → cwd-only fallback
    private static func terminalMatchScript(cwd: String, action: String, tty: String? = nil) -> String {
        let escaped = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let onMatch = action == "focus"
            ? "set selected tab of w to t\n                                set index of w to 1\n                                return true"
            : "set selected tab of w to t\n                                set index of w to 1\n                                activate\n                                do script theText in t\n                                return true"
        let ttyLiteral = tty ?? ""
        return """
        tell application "Terminal"
            if not running then return false
            \(action == "focus" ? "activate" : "set theText to the clipboard as text")
            -- Pass 0: exact tty match (resolved from transcript)
            if "\(ttyLiteral)" is not "" then
                repeat with w in windows
                    try
                        repeat with i from 1 to count of tabs of w
                            try
                                set t to tab i of w
                                if tty of t is "\(ttyLiteral)" then
                                    \(onMatch)
                                end if
                            end try
                        end repeat
                    end try
                end repeat
            end if
            -- Pass 1: claude process + cwd match via tty lsof
            repeat with w in windows
                try
                    repeat with i from 1 to count of tabs of w
                        try
                            set t to tab i of w
                            set procs to processes of t
                            set hasClaude to false
                            repeat with p in procs
                                if p contains "claude" then
                                    set hasClaude to true
                                    exit repeat
                                end if
                            end repeat
                            if hasClaude then
                                set tabTty to tty of t
                                set cwdCheck to do shell script "lsof -a -d cwd -Fn $(lsof -t " & quoted form of tabTty & " 2>/dev/null | sed 's/^/-p /') 2>/dev/null | grep '^n' | cut -c2-"
                                if cwdCheck contains "\(escaped)" then
                                    \(onMatch)
                                end if
                            end if
                        end try
                    end repeat
                end try
            end repeat
            -- Pass 2: any tab with claude process
            repeat with w in windows
                try
                    repeat with i from 1 to count of tabs of w
                        try
                            set t to tab i of w
                            set procs to processes of t
                            repeat with p in procs
                                if p contains "claude" then
                                    \(onMatch)
                                end if
                            end repeat
                        end try
                    end repeat
                end try
            end repeat
            -- Pass 3: cwd match only (claude process may have exited)
            repeat with w in windows
                try
                    repeat with i from 1 to count of tabs of w
                        try
                            set t to tab i of w
                            set tabTty to tty of t
                            set cwdCheck to do shell script "lsof -a -d cwd -Fn $(lsof -t " & quoted form of tabTty & " 2>/dev/null | sed 's/^/-p /') 2>/dev/null | grep '^n' | cut -c2-"
                            if cwdCheck contains "\(escaped)" then
                                \(onMatch)
                            end if
                        end try
                    end repeat
                end try
            end repeat
        end tell
        return false
        """
    }

    private static func sendTerminalPaste(cwd: String, tty: String? = nil) -> Bool {
        let script = terminalMatchScript(cwd: cwd, action: "paste", tty: tty)
        return runAppleScript(script)
    }

    private static func focusTerminal(cwd: String, tty: String? = nil) -> Bool {
        let script = terminalMatchScript(cwd: cwd, action: "focus", tty: tty)
        return runAppleScript(script)
    }

    // MARK: - iTerm2

    /// Focus the correct iTerm2 session, send text via native `write text`.
    private static func sendiTerm2Paste(cwd: String, tty: String? = nil) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) else {
            return false
        }
        let cwdFolder = (cwd as NSString).lastPathComponent
        let ttyLiteral = tty ?? ""
        let script = """
        tell application "iTerm2"
            set theText to the clipboard as text
            -- Pass 0: exact tty match (resolved from transcript)
            if "\(ttyLiteral)" is not "" then
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(ttyLiteral)" then
                                select t
                                select s
                                activate
                                tell s to write text theText
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end if
            -- First pass: match by cwd path in session
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionName to name of s
                        set sessionPath to path of s
                        if sessionName contains "claude" and (sessionPath contains "\(cwdFolder)" or sessionName contains "\(cwdFolder)") then
                            select t
                            select s
                            activate
                            tell s to write text theText
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            -- Second pass: any claude session
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionName to name of s
                        if sessionName contains "claude" then
                            select t
                            select s
                            activate
                            tell s to write text theText
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            -- Third pass: cwd folder only (claude process may have exited)
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionPath to path of s
                        if sessionPath contains "\(cwdFolder)" then
                            select t
                            select s
                            activate
                            tell s to write text theText
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        return runAppleScript(script)
    }

    private static func focusiTerm2(cwd: String, tty: String? = nil) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) else {
            return false
        }
        let cwdFolder = (cwd as NSString).lastPathComponent
        let ttyLiteral = tty ?? ""
        let script = """
        tell application "iTerm2"
            activate
            -- Pass 0: exact tty match (resolved from transcript)
            if "\(ttyLiteral)" is not "" then
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(ttyLiteral)" then
                                select t
                                select s
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end if
            -- First pass: match by cwd path
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionName to name of s
                        set sessionPath to path of s
                        if sessionName contains "claude" and (sessionPath contains "\(cwdFolder)" or sessionName contains "\(cwdFolder)") then
                            select t
                            select s
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            -- Second pass: any claude session
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionName to name of s
                        if sessionName contains "claude" then
                            select t
                            select s
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            -- Third pass: cwd folder only (claude process may have exited)
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionPath to path of s
                        if sessionPath contains "\(cwdFolder)" then
                            select t
                            select s
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        return runAppleScript(script)
    }

    // MARK: - Warp

    /// Paste into Warp's active window (limited AppleScript support — no tab matching).
    private static func sendWarpPaste() -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "dev.warp.Warp-Stable" }) else {
            return false
        }
        let script = """
        tell application "Warp"
            activate
            delay 0.15
        end tell
        tell application "System Events"
            tell process "Warp"
                keystroke "v" using command down
                delay 0.05
                keystroke return
            end tell
        end tell
        return true
        """
        return runAppleScript(script)
    }

    // MARK: - Helpers

    /// Whether we've already prompted for Accessibility permission this session.
    private static var hasPromptedAccessibility = false

    /// Prompt for Accessibility permission once per app session; check silently afterward.
    private static func ensureAccessibility() {
        if AXIsProcessTrusted() { return }
        if !hasPromptedAccessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            hasPromptedAccessibility = true
        }
    }

    private static func runAppleScript(_ source: String) -> Bool {
        ensureAccessibility()
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            logToFile("AppleScript error: \(error)")
            return false
        }
        return result?.booleanValue ?? false
    }

    private static func logToFile(_ message: String) {
        let logPath = "/tmp/claudebell.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [TerminalBridge] \(message)\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
        }
    }

    private static func activateTerminal() {
        let terminalBundles = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable"
        ]
        for bundleId in terminalBundles {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
                app.activate()
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }
}
