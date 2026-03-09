import Foundation
import AppKit

enum TerminalBridge {

    /// Sends text to a Terminal.app tab whose process matches Claude Code.
    /// Uses clipboard paste (Cmd+V) + Return for reliability.
    static func sendText(_ text: String, toCwd cwd: String) {
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

    /// Focus the correct Terminal.app tab, paste from clipboard, press Return.
    private static func sendTerminalPaste(cwd: String) -> Bool {
        let cwdFolder = (cwd as NSString).lastPathComponent
        let script = """
        tell application "Terminal"
            if not running then return false
            -- First pass: match by cwd folder
            repeat with w in windows
                repeat with i from 1 to count of tabs of w
                    set t to tab i of w
                    set procs to processes of t
                    set winName to name of w
                    repeat with p in procs
                        if p contains "claude" and winName contains "\(cwdFolder)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            delay 0.15
                            tell application "System Events"
                                tell process "Terminal"
                                    keystroke "v" using command down
                                    delay 0.05
                                    keystroke return
                                end tell
                            end tell
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            -- Second pass: any claude tab
            repeat with w in windows
                repeat with i from 1 to count of tabs of w
                    set t to tab i of w
                    set procs to processes of t
                    repeat with p in procs
                        if p contains "claude" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            delay 0.15
                            tell application "System Events"
                                tell process "Terminal"
                                    keystroke "v" using command down
                                    delay 0.05
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
        let cwdFolder = (cwd as NSString).lastPathComponent
        let script = """
        tell application "Terminal"
            if not running then return false
            activate
            -- First pass: match tab whose window name contains the cwd folder
            repeat with w in windows
                repeat with i from 1 to count of tabs of w
                    set t to tab i of w
                    set procs to processes of t
                    set winName to name of w
                    repeat with p in procs
                        if p contains "claude" then
                            if winName contains "\(cwdFolder)" then
                                set selected tab of w to t
                                set index of w to 1
                                return true
                            end if
                        end if
                    end repeat
                end repeat
            end repeat
            -- Second pass: fallback to any tab with claude
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

    /// Focus the correct iTerm2 session, paste from clipboard, press Return.
    private static func sendiTerm2Paste(cwd: String) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) else {
            return false
        }
        let cwdFolder = (cwd as NSString).lastPathComponent
        let script = """
        tell application "iTerm2"
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
                            delay 0.15
                            tell application "System Events"
                                tell process "iTerm2"
                                    keystroke "v" using command down
                                    delay 0.05
                                    keystroke return
                                end tell
                            end tell
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
                            delay 0.15
                            tell application "System Events"
                                tell process "iTerm2"
                                    keystroke "v" using command down
                                    delay 0.05
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
