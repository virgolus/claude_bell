import Foundation
import AppKit

enum TerminalBridge {

    /// Sends text to a Terminal.app tab whose process matches Claude Code in the given cwd.
    static func sendText(_ text: String, toCwd cwd: String) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    set procs to processes of t
                    repeat with p in procs
                        if p contains "claude" then
                            do script "\(escaped)" in t
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                print("AppleScript error: \(error)")
            }
        }
    }

    /// Brings the Terminal.app tab with Claude Code to the front.
    static func focusTerminalTab(forCwd cwd: String) {
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with i from 1 to count of tabs of w
                    set t to tab i of w
                    set procs to processes of t
                    repeat with p in procs
                        if p contains "claude" then
                            set selected tab of w to t
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                print("AppleScript error: \(error)")
            }
        }
    }
}
