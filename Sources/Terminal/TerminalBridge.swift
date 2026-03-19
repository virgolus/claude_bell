import Foundation
import AppKit
enum TerminalBridge {

    /// Sends text to a Terminal.app tab whose process matches Claude Code.
    /// Uses clipboard paste (Cmd+V) + Return for reliability.
    static func sendText(_ text: String, toCwd cwd: String) {
        logToFile("sendText: \"\(text)\" → cwd: \(cwd)")
        // Save clipboard, put text, paste+enter, restore clipboard
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let sent = sendiTerm2Paste(cwd: cwd) || sendTerminalPaste(cwd: cwd) || sendWarpPaste()

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
    static func sendTextTwoStep(_ first: String, then second: String, toCwd cwd: String) {
        logToFile("sendTextTwoStep: first=\"\(first)\", then=\"\(second)\" → cwd: \(cwd)")
        sendText(first, toCwd: cwd)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            sendText(second, toCwd: cwd)
        }
    }

    /// Brings the terminal tab running Claude Code to the front.
    static func focusTerminalTab(forCwd cwd: String) {
        if focusiTerm2(cwd: cwd) { return }
        if focusTerminal(cwd: cwd) { return }
        activateTerminal()
    }

    // MARK: - Terminal.app

    /// Builds an AppleScript that finds the correct Terminal.app tab by checking each tab's
    /// tty via `lsof` to get the real cwd, instead of relying on window name (which only
    /// reflects the active tab's title).
    ///
    /// Pass 1: tab has "claude" in processes AND tty cwd matches → exact match
    /// Pass 2: tab has "claude" in processes → fallback (any claude tab)
    /// Pass 3: tty cwd matches (claude may have exited) → cwd-only fallback
    private static func terminalMatchScript(cwd: String, action: String) -> String {
        let escaped = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let onMatch = action == "focus"
            ? "set selected tab of w to t\n                                set index of w to 1\n                                return true"
            : "set selected tab of w to t\n                                set index of w to 1\n                                activate\n                                do script theText in t\n                                return true"
        return """
        tell application "Terminal"
            if not running then return false
            \(action == "focus" ? "activate" : "set theText to the clipboard as text")
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

    /// Focus the correct Terminal.app tab, send text via native `do script`.
    private static func sendTerminalPaste(cwd: String) -> Bool {
        logToFile("sendTerminalPaste: cwd=\(cwd)")
        logTerminalTabInfo(cwd: cwd)
        let script = terminalMatchScript(cwd: cwd, action: "paste")
        logToFile("sendTerminalPaste script:\n\(script)")
        let result = runAppleScript(script)
        logToFile("sendTerminalPaste: result=\(result)")
        return result
    }

    private static func focusTerminal(cwd: String) -> Bool {
        logToFile("focusTerminal: cwd=\(cwd)")
        logTerminalTabInfo(cwd: cwd)
        let script = terminalMatchScript(cwd: cwd, action: "focus")
        logToFile("focusTerminal script:\n\(script)")
        let result = runAppleScript(script)
        logToFile("focusTerminal: result=\(result)")
        return result
    }

    /// Diagnostic: log all Terminal.app tab info (tty, processes, lsof cwd) before matching.
    private static func logTerminalTabInfo(cwd: String) {
        let escaped = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let diagScript = """
        tell application "Terminal"
            if not running then return "Terminal not running"
            set info to ""
            repeat with wIdx from 1 to count of windows
                try
                set w to window wIdx
                repeat with tIdx from 1 to count of tabs of w
                    set t to tab tIdx of w
                    set info to info & "--- Window " & wIdx & " Tab " & tIdx & " ---" & linefeed
                    try
                        set procs to processes of t
                        set info to info & "  processes: " & (procs as text) & linefeed
                    on error errMsg
                        set info to info & "  processes error: " & errMsg & linefeed
                    end try
                    try
                        set tabTty to tty of t
                        set info to info & "  tty: " & tabTty & linefeed
                    on error errMsg
                        set info to info & "  tty error: " & errMsg & linefeed
                    end try
                    try
                        set tabTty to tty of t
                        set lsofCmd to "lsof -a -d cwd -Fn $(lsof -t " & quoted form of tabTty & " 2>/dev/null | sed 's/^/-p /') 2>/dev/null | grep '^n' | cut -c2-"
                        set cwdResult to do shell script lsofCmd
                        set info to info & "  lsof cwd: " & cwdResult & linefeed
                    on error errMsg
                        set info to info & "  lsof error: " & errMsg & linefeed
                    end try
                    try
                        set tabTty to tty of t
                        set cwdResult to do shell script "lsof -a -d cwd -Fn $(lsof -t " & quoted form of tabTty & " 2>/dev/null | sed 's/^/-p /') 2>/dev/null | grep '^n' | cut -c2-"
                        if cwdResult contains "\(escaped)" then
                            set info to info & "  contains check: MATCH for \(escaped)" & linefeed
                        else
                            set info to info & "  contains check: NO match (looking for \(escaped))" & linefeed
                        end if
                    on error errMsg
                        set info to info & "  contains check error: " & errMsg & linefeed
                    end try
                end repeat
                end try
            end repeat
            return info
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: diagScript)?.executeAndReturnError(&error)
        if let error {
            logToFile("logTerminalTabInfo error: \(error)")
        } else if let info = result?.stringValue {
            logToFile("Terminal tab diagnostic (looking for cwd: \(cwd)):\n\(info)")
        } else {
            logToFile("logTerminalTabInfo: no result returned")
        }
    }

    // MARK: - iTerm2

    /// Focus the correct iTerm2 session, send text via native `write text`.
    private static func sendiTerm2Paste(cwd: String) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) else {
            return false
        }
        let cwdFolder = (cwd as NSString).lastPathComponent
        let script = """
        tell application "iTerm2"
            set theText to the clipboard as text
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

    private static func focusiTerm2(cwd: String) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) else {
            return false
        }
        let cwdFolder = (cwd as NSString).lastPathComponent
        let script = """
        tell application "iTerm2"
            activate
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

    private static func runAppleScript(_ source: String) -> Bool {
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
