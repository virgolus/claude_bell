import Foundation
import AppKit
enum TerminalBridge {

    /// Whether ClaudeBell currently holds an *effective* Accessibility grant.
    /// The System-Settings toggle can read "on" while this is false: an ad-hoc
    /// signed binary rebinds its code identity (cdhash) on every rebuild, so a
    /// prior grant no longer matches the running binary. Terminal.app text
    /// injection needs a real keystroke (Cmd+V + Return), which silently no-ops
    /// without this — so callers check it to explain the failure instead of
    /// leaving the user staring at an un-delivered reply.
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Sends text to a Terminal.app tab whose process matches Claude Code.
    /// Uses clipboard paste (Cmd+V) + Return for reliability.
    ///
    /// Returns `true` when the text was delivered to a tab. On failure the
    /// caller is responsible for the user-visible recovery; `text` is left on
    /// the clipboard so the user can paste it manually. Set
    /// `activateOnFailure` to `false` to keep the current frontmost app (so a
    /// panel showing an error stays visible instead of being pushed behind a
    /// terminal we couldn't target anyway).
    @discardableResult
    static func sendText(_ text: String, toCwd cwd: String, transcriptPath: String = "", knownTty: String? = nil, activateOnFailure: Bool = true, marker: String? = nil, iTermSessionId: String? = nil) -> Bool {
        logToFile("sendText: \"\(text)\" → cwd: \(cwd), transcript: \(transcriptPath), knownTty: \(knownTty ?? "nil"), axTrusted: \(AXIsProcessTrusted())")
        let candidateTty = knownTty ?? resolveTty(fromTranscriptPath: transcriptPath)
        // Trust the tty for exact targeting only if a live process on it still
        // sits in the session's cwd. macOS recycles ttysNNN numbers when tabs
        // close, so a persisted/stale tty could otherwise point at an unrelated
        // tab (wrong-session paste). Empty cwd → can't validate → trust it.
        let trustedTty: String? = {
            guard let t = candidateTty else { return nil }
            return ttyBelongsToSession(t, cwd: cwd) ? t : nil
        }()
        logToFile("sendText: trustedTty=\(trustedTty ?? "nil")")

        // Save clipboard, put text, paste+enter, restore clipboard
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        var sent = false
        // Pass −1: exact marker / iTerm-id match (set while the tty was live).
        // Immune to tty recycling and cwd ambiguity.
        if let marker, !marker.isEmpty {
            sent = sendTerminalPaste(cwd: cwd, tty: trustedTty, exactTtyOnly: true, marker: marker)
        }
        if !sent, let iTermSessionId, !iTermSessionId.isEmpty {
            sent = sendiTerm2Paste(cwd: cwd, tty: trustedTty, exactTtyOnly: true, iTermSessionId: iTermSessionId)
        }
        if let tty = trustedTty, !sent {
            // Route to the terminal app that actually owns this tty and paste
            // into that exact tab — no fuzzy / cross-app passes, so two sessions
            // sharing a cwd (or another app's claude tab) can't be mis-hit.
            switch terminalBundleForTty(tty) {
            case "com.googlecode.iterm2":
                sent = sendiTerm2Paste(cwd: cwd, tty: tty, exactTtyOnly: true)
            case "com.apple.Terminal":
                sent = sendTerminalPaste(cwd: cwd, tty: tty, exactTtyOnly: true)
            case "dev.warp.Warp-Stable":
                // Warp's AppleScript exposes no per-tab/tty handle, so we can't
                // select the tab — paste into Warp's focused tab. Routing here
                // (instead of the fuzzy chain) still prevents pasting into a
                // Terminal.app / iTerm2 tab by mistake.
                sent = sendWarpPaste()
            default:
                // Owner unknown — still safe to try exact-tty in both AppleScript
                // terminals; the unique tty can only match the right tab.
                sent = sendiTerm2Paste(cwd: cwd, tty: tty, exactTtyOnly: true)
                    || sendTerminalPaste(cwd: cwd, tty: tty, exactTtyOnly: true)
            }
        }
        if !sent {
            // No trusted tty (or its tab is gone): best-effort fuzzy fallback.
            sent = sendiTerm2Paste(cwd: cwd, tty: trustedTty) || sendTerminalPaste(cwd: cwd, tty: trustedTty) || sendWarpPaste()
        }

        logToFile("sendText: delivered=\(sent)")

        if sent {
            // Restore the prior clipboard after the paste has landed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                if let old = oldContents {
                    pasteboard.setString(old, forType: .string)
                }
            }
        }
        // On failure we deliberately leave `text` on the clipboard so the user
        // can paste it into the right tab themselves — the caller surfaces this.

        if !sent && activateOnFailure { activateTerminal() }
        return sent
    }

    /// Sends two texts sequentially: first text + Enter, then after a delay, second text + Enter.
    /// Used for "type something else" options where Claude Code expects the option number first,
    /// then the actual text after it prompts.
    @discardableResult
    static func sendTextTwoStep(_ first: String, then second: String, toCwd cwd: String, transcriptPath: String = "", knownTty: String? = nil, marker: String? = nil, iTermSessionId: String? = nil) -> Bool {
        logToFile("sendTextTwoStep: first=\"\(first)\", then=\"\(second)\" → cwd: \(cwd)")
        // The first send resolves and targets the tab; if it can't, the second
        // would mis-fire too, so its success determines delivery.
        let sent = sendText(first, toCwd: cwd, transcriptPath: transcriptPath, knownTty: knownTty, marker: marker, iTermSessionId: iTermSessionId)
        if sent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                sendText(second, toCwd: cwd, transcriptPath: transcriptPath, knownTty: knownTty, marker: marker, iTermSessionId: iTermSessionId)
            }
        }
        return sent
    }

    /// The tab-title marker string for a session code. Single source of truth
    /// for the marker format — matching and stamping both go through here.
    static func markerString(code: String) -> String { "⟨cb:\(code)⟩" }

    /// Stamp a session marker into its terminal tab so replies can later target
    /// the exact tab without relying on the (recyclable) tty. Call this while
    /// the hook connection is live, so `tty` is reliable. Returns the captured
    /// iTerm2 session id when iTerm2 owns the tty (so the caller can persist
    /// it); nil otherwise. Best-effort: never throws.
    @discardableResult
    static func stampSessionMarker(code: String, tty: String) -> String? {
        logToFile("stampSessionMarker: code=\(code) tty=\(tty)")
        switch terminalBundleForTty(tty) {
        case "com.apple.Terminal":
            stampTerminalApp(code: code, tty: tty)
            return nil
        case "com.googlecode.iterm2":
            return stampITerm2(code: code, tty: tty)
        case "dev.warp.Warp-Stable":
            return nil // Warp exposes no per-tab handle.
        default:
            // Owner unknown — try Terminal.app first (title pin is harmless if
            // the tty isn't a Terminal tab), then iTerm2.
            stampTerminalApp(code: code, tty: tty)
            return stampITerm2(code: code, tty: tty)
        }
    }

    /// Terminal.app: append the marker to the tab's custom title (idempotent).
    /// An AppleScript-set custom title pins over the process's OSC title writes.
    private static func stampTerminalApp(code: String, tty: String) {
        let marker = markerString(code: code)
        let script = """
        tell application "Terminal"
            if not running then return false
            repeat with w in windows
                try
                    repeat with i from 1 to count of tabs of w
                        try
                            set t to tab i of w
                            if tty of t is "\(tty)" then
                                set ct to custom title of t
                                if ct does not contain "\(marker)" then
                                    set custom title of t to ct & "  \(marker)"
                                end if
                                return true
                            end if
                        end try
                    end repeat
                end try
            end repeat
            return false
        end tell
        """
        _ = runAppleScript(script)
    }

    /// iTerm2: capture the session's stable id for the tty (no title change).
    /// Returns the id string, or nil if none found. If the id is empty, falls
    /// back to writing the marker into the session name.
    private static func stampITerm2(code: String, tty: String) -> String? {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) else {
            return nil
        }
        let marker = markerString(code: code)
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            set sid to (id of s) as text
                            if sid is "" then
                                set name of s to (name of s) & "  \(marker)"
                            end if
                            return sid
                        end if
                    end repeat
                end repeat
            end repeat
            return ""
        end tell
        """
        let out = runAppleScriptString(script)
        let trimmed = out?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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
        // Terminal.app's AppleScript has no "make new tab" verb, and a bare
        // `do script` always spawns a NEW WINDOW. To reuse the already-open
        // terminal, open a tab with Cmd+T in the front window (via System
        // Events), then run the command in that now-frontmost tab. Only when
        // no window exists do we let `do script` create the first window.
        //
        // The Cmd+T keystroke needs Accessibility permission. When it's denied
        // (AppleScript error 1002) the tab script fails before the command
        // runs, so we fall back to `do script` — a new WINDOW, which needs only
        // Automation permission. The session still launches instead of the app
        // silently doing nothing.
        let tabScript = """
        tell application "Terminal"
            activate
            if (count of windows) is 0 then
                do script "\(escaped)"
            else
                tell application "System Events" to keystroke "t" using command down
                delay 0.3
                do script "\(escaped)" in front window
            end if
            return true
        end tell
        """
        if runAppleScript(tabScript) { return true }

        // Fallback: new window (no Accessibility required).
        logToFile("openTerminalAppNewSession: tab keystroke blocked, falling back to new window")
        let windowScript = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
            return true
        end tell
        """
        return runAppleScript(windowScript)
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
    static func focusTerminalTab(forCwd cwd: String, transcriptPath: String = "", knownTty: String? = nil, marker: String? = nil, iTermSessionId: String? = nil) {
        let resolvedTty = knownTty ?? resolveTty(fromTranscriptPath: transcriptPath)
        DispatchQueue.global(qos: .userInitiated).async {
            if focusiTerm2(cwd: cwd, tty: resolvedTty, iTermSessionId: iTermSessionId) { return }
            if focusTerminal(cwd: cwd, tty: resolvedTty, marker: marker ?? "") { return }
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

    /// Whether `tty` currently hosts a process whose cwd is `cwd` — i.e. the
    /// tab still belongs to this session. Guards against trusting a tty number
    /// that macOS recycled to an unrelated tab after the original closed.
    private static func ttyBelongsToSession(_ tty: String, cwd: String) -> Bool {
        let target = cwd.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return true } // nothing to validate against
        let dev = tty.replacingOccurrences(of: "/dev/", with: "")
        guard let out = shell("ps -t \(dev) -o pid= 2>/dev/null"), !out.isEmpty else { return false }
        let pids = out.split(whereSeparator: { $0 == "\n" || $0 == " " }).compactMap { Int($0) }
        for pid in pids {
            guard let c = shell("lsof -a -d cwd -Fn -p \(pid) 2>/dev/null | grep '^n' | cut -c2-"),
                  !c.isEmpty else { continue }
            // Accept exact match OR a parent/child path relationship: Claude's
            // hook `cwd` is often a subdirectory of the shell's launch cwd that
            // `lsof` reports (e.g. hook cwd .../rulemate/packages/ui/src/styles
            // vs process cwd .../rulemate). A recycled tty pointing at an
            // unrelated project shares no path prefix, so this still guards
            // against stale ttys.
            if c == target || target.hasPrefix(c + "/") || c.hasPrefix(target + "/") {
                return true
            }
        }
        return false
    }

    /// Resolve which terminal emulator owns a tty by walking the process-parent
    /// chain from a process on that tty up to a known terminal app. Returns the
    /// app's bundle id, or nil if none matched.
    private static func terminalBundleForTty(_ tty: String) -> String? {
        let dev = tty.replacingOccurrences(of: "/dev/", with: "")
        guard let out = shell("ps -t \(dev) -o pid= 2>/dev/null"),
              var pid = out.split(whereSeparator: { $0 == "\n" || $0 == " " }).compactMap({ Int($0) }).first else {
            return nil
        }
        for _ in 0..<16 {
            guard let line = shell("ps -o ppid=,comm= -p \(pid) 2>/dev/null"), !line.isEmpty else { break }
            let lower = line.lowercased()
            if lower.contains("iterm") { return "com.googlecode.iterm2" }
            if lower.contains("warp") { return "dev.warp.Warp-Stable" }
            if lower.contains("terminal") { return "com.apple.Terminal" }
            // First whitespace-delimited token is the ppid.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let ppid = trimmed.split(separator: " ", maxSplits: 1).first.flatMap({ Int($0) }),
                  ppid > 1, ppid != pid else { break }
            pid = ppid
        }
        return nil
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
    private static func terminalMatchScript(cwd: String, action: String, tty: String? = nil, exactTtyOnly: Bool = false, marker: String = "") -> String {
        let escaped = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let onMatch = action == "focus"
            ? "set selected tab of w to t\n                                set index of w to 1\n                                return true"
            // Paste via Cmd+V (bracketed paste = text only, no submit), then send a
            // SEPARATE Return after a short delay. Bundling the newline with the text
            // (as `do script` does) makes Claude Code's TUI intermittently treat it as a
            // literal newline instead of a submit — the "text appears but no Enter" bug.
            : "set selected tab of w to t\n                                set index of w to 1\n                                activate\n                                delay 0.2\n                                tell application \"System Events\"\n                                    keystroke \"v\" using command down\n                                    delay 0.35\n                                    key code 36\n                                end tell\n                                return true"
        let ttyLiteral = tty ?? ""
        // Fuzzy passes (claude+cwd, any-claude, cwd-only). Skipped when
        // exactTtyOnly is set — the caller has a validated tty and wants no
        // chance of matching a sibling tab in the same cwd.
        let fuzzyPasses = exactTtyOnly ? "" : """
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
        """
        return """
        tell application "Terminal"
            if not running then return false
            \(action == "focus" ? "activate" : "set theText to the clipboard as text")
            -- Pass -1: exact marker match (survives tty recycling)
            if "\(marker)" is not "" then
                repeat with w in windows
                    try
                        repeat with i from 1 to count of tabs of w
                            try
                                set t to tab i of w
                                if (custom title of t) contains "\(marker)" then
                                    \(onMatch)
                                end if
                            end try
                        end repeat
                    end try
                end repeat
            end if
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
        \(fuzzyPasses)
        end tell
        return false
        """
    }

    private static func sendTerminalPaste(cwd: String, tty: String? = nil, exactTtyOnly: Bool = false, marker: String = "") -> Bool {
        let script = terminalMatchScript(cwd: cwd, action: "paste", tty: tty, exactTtyOnly: exactTtyOnly, marker: marker)
        return runAppleScript(script)
    }

    private static func focusTerminal(cwd: String, tty: String? = nil, marker: String = "") -> Bool {
        let script = terminalMatchScript(cwd: cwd, action: "focus", tty: tty, marker: marker)
        return runAppleScript(script)
    }

    // MARK: - iTerm2

    /// Focus the correct iTerm2 session, send text via native `write text`.
    private static func sendiTerm2Paste(cwd: String, tty: String? = nil, exactTtyOnly: Bool = false, iTermSessionId: String? = nil) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) else {
            return false
        }
        let cwdFolder = (cwd as NSString).lastPathComponent
        let ttyLiteral = tty ?? ""
        // Fuzzy passes are skipped when the caller has a validated tty
        // (exactTtyOnly) so a sibling claude session can't be mis-hit.
        let fuzzyPasses = exactTtyOnly ? "" : """
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
        """
        let script = """
        tell application "iTerm2"
            set theText to the clipboard as text
            -- Pass -1: exact stable session-id match
            if "\(iTermSessionId ?? "")" is not "" then
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if (id of s as text) is "\(iTermSessionId ?? "")" then
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
        \(fuzzyPasses)
        end tell
        return false
        """
        return runAppleScript(script)
    }

    private static func focusiTerm2(cwd: String, tty: String? = nil, iTermSessionId: String? = nil) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) else {
            return false
        }
        let cwdFolder = (cwd as NSString).lastPathComponent
        let ttyLiteral = tty ?? ""
        let script = """
        tell application "iTerm2"
            activate
            -- Pass -1: exact stable session-id match
            if "\(iTermSessionId ?? "")" is not "" then
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if (id of s as text) is "\(iTermSessionId ?? "")" then
                                select t
                                select s
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end if
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

    /// Like `runAppleScript` but returns the script's string result (or nil).
    private static func runAppleScriptString(_ source: String) -> String? {
        ensureAccessibility()
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            logToFile("AppleScript error: \(error)")
            return nil
        }
        return result?.stringValue
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
