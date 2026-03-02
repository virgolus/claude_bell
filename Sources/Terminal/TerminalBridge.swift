import Foundation
import AppKit

enum TerminalBridge {

    /// Sends text to a Terminal.app tab whose process matches Claude Code.
    static func sendText(_ text: String, toCwd cwd: String) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        if sendiTerm2Text(escaped, cwd: cwd) { return }
        if sendTerminalText(escaped, cwd: cwd) { return }
        activateTerminal()
    }

    /// Brings the terminal tab running Claude Code to the front.
    static func focusTerminalTab(forCwd cwd: String) {
        if focusiTerm2(cwd: cwd) { return }
        if focusTerminal(cwd: cwd) { return }
        activateTerminal()
    }

    // MARK: - Terminal.app

    private static func sendTerminalText(_ escaped: String, cwd: String) -> Bool {
        let script = """
        tell application "Terminal"
            if not running then return false
            repeat with w in windows
                repeat with i from 1 to count of tabs of w
                    set t to tab i of w
                    set procs to processes of t
                    repeat with p in procs
                        if p contains "claude" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            delay 0.1
                            tell application "System Events"
                                tell process "Terminal"
                                    keystroke "\(escaped)"
                                    keystroke return
                                end tell
                            end tell
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

    private static func focusTerminal(cwd: String) -> Bool {
        let script = """
        tell application "Terminal"
            if not running then return false
            activate
            repeat with w in windows
                repeat with i from 1 to count of tabs of w
                    set t to tab i of w
                    set procs to processes of t
                    repeat with p in procs
                        if p contains "claude" then
                            set selected tab of w to t
                            set index of w to 1
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

    // MARK: - iTerm2

    private static func sendiTerm2Text(_ escaped: String, cwd: String) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) else {
            return false
        }
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionName to name of s
                        if sessionName contains "claude" then
                            tell s to write text "\(escaped)"
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
        let script = """
        tell application "iTerm2"
            activate
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
        end tell
        return false
        """
        return runAppleScript(script)
    }

    // MARK: - Helpers

    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            print("AppleScript error: \(error)")
            return false
        }
        return result?.booleanValue ?? false
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
