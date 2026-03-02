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

        let sent = sendiTerm2Paste(cwd: cwd) || sendTerminalPaste(cwd: cwd)

        // Restore clipboard after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let old = oldContents {
                pasteboard.setString(old, forType: .string)
            }
        }

        if !sent { activateTerminal() }
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
                    set tabHistory to history of t
                    set tabTitle to custom title of t
                    repeat with p in procs
                        if p contains "claude" and (tabTitle contains "\(cwdFolder)" or tabHistory contains "\(cwdFolder)") then
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
        // First try to match by cwd (tty's working directory via lsof)
        let cwdFolder = (cwd as NSString).lastPathComponent
        let script = """
        tell application "Terminal"
            if not running then return false
            activate
            -- First pass: match tab whose custom title or history contains the cwd folder
            repeat with w in windows
                repeat with i from 1 to count of tabs of w
                    set t to tab i of w
                    set procs to processes of t
                    set tabHistory to history of t
                    set tabTitle to custom title of t
                    repeat with p in procs
                        if p contains "claude" then
                            if tabTitle contains "\(cwdFolder)" or tabHistory contains "\(cwdFolder)" then
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
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionName to name of s
                        if sessionName contains "claude" then
                            tell s
                                select s
                            end tell
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
