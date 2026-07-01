# Session Tab Marker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tag each Claude Code session's terminal tab with a stable unique marker while the tty is reliably known, then match panel replies on that marker so delivery to the correct tab no longer depends on fragile tty/cwd/fuzzy inference.

**Architecture:** When a Stop or Notification hook arrives, ClaudeBell resolves the live tty (already done by `refreshSessionTty`) and then *stamps* a marker into the tab: on Terminal.app it appends `⟨cb:<code>⟩` to the `custom title` (verified to pin over Claude's OSC title writes); on iTerm2 it captures the stable `id of session` instead (no title pollution). At reply time `TerminalBridge` tries a new highest-priority match pass keyed on the marker/id, falling back to the existing tty → cwd → fuzzy passes when absent.

**Tech Stack:** Swift 5.10, SwiftUI, Hummingbird, AppleScript via `NSAppleScript`, SwiftPM (`swift build`). No automated test target exists in this repo; verification is `swift build` + isolated AppleScript probe harnesses run through `osascript` + manual end-to-end checks with a real `claude` session.

## Global Constraints

- Platform: macOS 14+ (`Package.swift` declares `.macOS(.v14)`).
- Marker format lives in exactly one place: `TerminalBridge.markerString(code:)` returns `"⟨cb:\(code)⟩"`. Never hard-code the literal elsewhere.
- Marker code = first 8 characters of the session id with dashes removed (`RequestStore.markerCode(from:)`). Do not lengthen without a detected collision (YAGNI).
- Stamping is best-effort: every failure is logged via `TerminalBridge.logToFile` and MUST NOT block or fail a hook handler.
- The feature is strictly additive: when no marker is found, matching MUST fall through to the existing passes so behavior equals today's.
- Restart/test cycle per `CLAUDE.md`: `swift build` → `cp .build/debug/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell` → `pkill -x ClaudeBell; sleep 1; open ClaudeBell.app`. Rebuilds may invalidate Accessibility permission (re-add `ClaudeBell.app` under System Settings → Privacy → Accessibility if AppleScript returns error 1002).
- Commit after each task.

---

### Task 1: Marker code + iTerm-id storage in RequestStore

**Files:**
- Modify: `Sources/Models/SessionInfo.swift` (add `iTermSessionId`)
- Modify: `Sources/Store/RequestStore.swift` (extend `TtyRecord`, add accessors/setter)
- Test: inline `osascript`/build checks (no unit test target)

**Interfaces:**
- Produces:
  - `RequestStore.markerCode(from sessionId: String) -> String` (static)
  - `RequestStore.sessionMarkerCode(for sessionId: String) -> String` (instance; convenience over the static)
  - `RequestStore.iTermSessionId(for sessionId: String) -> String?`
  - `RequestStore.setITermSessionId(id: String, iTermSessionId: String)`
  - `SessionInfo.iTermSessionId: String?`

- [ ] **Step 1: Add `iTermSessionId` to `SessionInfo`**

In `Sources/Models/SessionInfo.swift`, after the `tty` property:

```swift
    /// Controlling terminal of the claude process (e.g. /dev/ttys003),
    /// resolved from the hook connection. Used for exact tab targeting.
    var tty: String?
    /// iTerm2's stable per-session id (GUID), captured while the hook
    /// connection was live. Used to target the exact iTerm2 session at reply
    /// time without polluting its title. nil for Terminal.app / Warp.
    var iTermSessionId: String?
```

- [ ] **Step 2: Extend `TtyRecord` and its writers in `RequestStore`**

In `Sources/Store/RequestStore.swift`, change the `TtyRecord` definition (line ~30). Making the new field optional keeps existing persisted caches decodable (missing key → nil):

```swift
    private struct TtyRecord: Codable {
        let tty: String
        let cwd: String
        let iTermSessionId: String?
        let updatedAt: Date
    }
```

Update `setSessionTty` (line ~213) to preserve any existing iTerm id:

```swift
    func setSessionTty(id: String, tty: String) {
        sessions[id]?.tty = tty
        let cwd = sessions[id]?.cwd ?? ttyCache[id]?.cwd ?? ""
        let existingITerm = sessions[id]?.iTermSessionId ?? ttyCache[id]?.iTermSessionId
        ttyCache[id] = TtyRecord(tty: tty, cwd: cwd, iTermSessionId: existingITerm, updatedAt: Date())
        saveTtyCache()
    }
```

- [ ] **Step 3: Add the marker-code helpers, iTerm-id accessor, and setter**

In `Sources/Store/RequestStore.swift`, next to `resolvedTty(for:)` (line ~223):

```swift
    /// Short, unique-enough code identifying a session's terminal tab. First 8
    /// characters of the session id (dashes stripped) — the tab marker embeds
    /// this so replies can target the exact tab. Recomputable from the session
    /// id, so Terminal.app needs no extra persistence.
    static func markerCode(from sessionId: String) -> String {
        String(sessionId.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    func sessionMarkerCode(for sessionId: String) -> String {
        Self.markerCode(from: sessionId)
    }

    /// Best-known iTerm2 session id: live value if the session is in memory,
    /// else the value persisted from a previous launch.
    func iTermSessionId(for sessionId: String) -> String? {
        sessions[sessionId]?.iTermSessionId ?? ttyCache[sessionId]?.iTermSessionId
    }

    /// Persist the iTerm2 session id captured during a live hook connection.
    func setITermSessionId(id: String, iTermSessionId: String) {
        sessions[id]?.iTermSessionId = iTermSessionId
        let tty = sessions[id]?.tty ?? ttyCache[id]?.tty ?? ""
        let cwd = sessions[id]?.cwd ?? ttyCache[id]?.cwd ?? ""
        ttyCache[id] = TtyRecord(tty: tty, cwd: cwd, iTermSessionId: iTermSessionId, updatedAt: Date())
        saveTtyCache()
    }
```

`removeSession` (line ~227) already `ttyCache.removeValue(forKey: id)` — the iTerm id lives in that record, so it is dropped automatically. No change needed there.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!` with no errors. (A pre-existing persisted `sessionTtyCache` without `iTermSessionId` still decodes because the field is optional.)

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/SessionInfo.swift Sources/Store/RequestStore.swift
git commit -m "Add session marker code + iTerm-id storage to RequestStore"
```

---

### Task 2: `TerminalBridge.stampSessionMarker`

**Files:**
- Modify: `Sources/Terminal/TerminalBridge.swift` (add marker string + stamp)
- Test: `osascript` probe harness (throwaway Terminal.app window)

**Interfaces:**
- Consumes: `RequestStore.markerCode(from:)` output (an 8-char string) — passed in as `code`.
- Produces:
  - `TerminalBridge.markerString(code: String) -> String`  (returns `"⟨cb:\(code)⟩"`)
  - `TerminalBridge.stampSessionMarker(code: String, tty: String) -> String?`
    (returns the captured iTerm2 session id when iTerm2 owns the tty, else nil)

- [ ] **Step 1: Write the failing probe test**

Create the probe at `/private/tmp/claude-503/-Users-evergine-Projects-PerkyPath-claude-bell/8bf22116-e325-4c25-a83e-20e849b88910/scratchpad/stamp_probe.sh` (scratchpad, not committed):

```bash
#!/bin/bash
# Opens a throwaway Terminal.app window, discovers its tty, then exercises the
# Terminal.app stamping AppleScript the way stampSessionMarker will. Asserts the
# marker is appended to the custom title and survives a process OSC title write.
set -e
CODE="deadbeef"
MARKER="⟨cb:${CODE}⟩"

TTY=$(osascript <<EOF
tell application "Terminal"
  set w to do script "printf '\\\\033]2;PRE-STAMP-SUMMARY\\\\007'; sleep 20"
  delay 0.6
  return tty of (selected tab of w)
end tell
EOF
)
echo "probe tty=$TTY"

# --- behavior under test: append marker to custom title of the tab on TTY ---
osascript <<EOF
tell application "Terminal"
  repeat with w in windows
    repeat with t in tabs of w
      try
        if tty of t is "$TTY" then
          set ct to custom title of t
          if ct does not contain "$MARKER" then set custom title of t to ct & "  $MARKER"
        end if
      end try
    end repeat
  end repeat
end tell
EOF

# process now rewrites its OSC title; marker must survive (pin verified in spec)
osascript -e "tell application \"Terminal\" to do script \"printf '\\033]2;POST-STAMP-SUMMARY\\007'\" in (first tab of (first window whose tabs contains (some tab whose tty is \"$TTY\")))" >/dev/null 2>&1 || true
sleep 1

FINAL=$(osascript <<EOF
tell application "Terminal"
  repeat with w in windows
    repeat with t in tabs of w
      try
        if tty of t is "$TTY" then return custom title of t
      end try
    end repeat
  end repeat
  return "<not found>"
end tell
EOF
)
echo "final custom title=[$FINAL]"

# cleanup
osascript <<EOF
tell application "Terminal"
  repeat with w in windows
    try
      if custom title of w contains "$MARKER" then close w saving no
    end try
  end repeat
end tell
EOF

case "$FINAL" in
  *"$MARKER"*) echo "PROBE PASS: marker present and pinned" ;;
  *) echo "PROBE FAIL: marker missing"; exit 1 ;;
esac
```

- [ ] **Step 2: Run the probe to confirm the AppleScript approach works standalone**

Run: `bash "$SCRATCH/stamp_probe.sh"` (substitute the scratchpad path)
Expected: `PROBE PASS: marker present and pinned`
(This validates the AppleScript logic before it is ported into Swift.)

- [ ] **Step 3: Add `markerString` and `stampSessionMarker` to `TerminalBridge`**

In `Sources/Terminal/TerminalBridge.swift`, after `sendTextTwoStep` (around line 78):

```swift
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
```

- [ ] **Step 4: Add a string-returning AppleScript runner**

`runAppleScript` returns `Bool`; the iTerm stamp needs the returned id string. Add next to `runAppleScript` (around line 579):

```swift
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
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/Terminal/TerminalBridge.swift
git commit -m "Add stampSessionMarker (Terminal custom title + iTerm session id)"
```

---

### Task 3: Stamp on the Stop and Notification hooks

**Files:**
- Modify: `Sources/Server/HookServer.swift` (make `refreshSessionTty` return the tty; stamp after refresh in Stop + Notification)

**Interfaces:**
- Consumes: `TerminalBridge.stampSessionMarker(code:tty:)`, `RequestStore.markerCode(from:)`, `RequestStore.setITermSessionId(id:iTermSessionId:)`.
- Produces: `HookServer.refreshSessionTty(sessionId:context:) async -> String?` (now returns the resolved tty), and a private `stampMarker(sessionId:tty:)` helper.

- [ ] **Step 1: Make `refreshSessionTty` return the resolved tty**

In `Sources/Server/HookServer.swift`, change `refreshSessionTty` (line ~330):

```swift
    @discardableResult
    func refreshSessionTty(sessionId: String, context: HookRequestContext) async -> String? {
        guard let port = context.remoteAddress?.port else { return nil }
        let resolved = await Task.detached(priority: .userInitiated) {
            Self.resolveTty(fromPeerPort: port)
        }.value
        guard let tty = resolved else { return nil }
        await MainActor.run { self.store.setSessionTty(id: sessionId, tty: tty) }
        return tty
    }
```

- [ ] **Step 2: Add the `stampMarker` helper**

In `Sources/Server/HookServer.swift`, right after `refreshSessionTty`:

```swift
    /// Stamp the session's tab marker off the main thread. Best-effort: logs
    /// and swallows any failure so it can never affect the hook response.
    /// Persists a captured iTerm2 session id back into the store.
    func stampMarker(sessionId: String, tty: String) async {
        let code = await MainActor.run { self.store.sessionMarkerCode(for: sessionId) }
        let iTermId = await Task.detached(priority: .userInitiated) {
            TerminalBridge.stampSessionMarker(code: code, tty: tty)
        }.value
        if let iTermId {
            await MainActor.run { self.store.setITermSessionId(id: sessionId, iTermSessionId: iTermId) }
        }
    }
```

- [ ] **Step 3: Call stamp in the Stop handler**

In the `/hooks/stop` handler, replace the tty-refresh line (line ~152):

```swift
            await self.refreshSessionTty(sessionId: input.sessionId, context: context)
```

with:

```swift
            if let tty = await self.refreshSessionTty(sessionId: input.sessionId, context: context) {
                await self.stampMarker(sessionId: input.sessionId, tty: tty)
            }
```

- [ ] **Step 4: Call stamp in the Notification handler**

In the `/hooks/notification` handler, replace the tty-refresh line (line ~88) with the identical two-line form:

```swift
            if let tty = await self.refreshSessionTty(sessionId: input.sessionId, context: context) {
                await self.stampMarker(sessionId: input.sessionId, tty: tty)
            }
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 6: Manual verification (Terminal.app)**

Restart the app: `cp .build/debug/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell && pkill -x ClaudeBell; sleep 1; open ClaudeBell.app`.
In a Terminal.app tab, run a `claude` session and let it finish a turn (fires Stop). Then inspect the tab:

```bash
osascript -e 'tell application "Terminal" to get custom title of every tab of front window'
```

Expected: the claude tab's custom title now ends with `  ⟨cb:XXXXXXXX⟩` (8 hex chars matching the first 8 of the session id, dashes removed). Confirm `/tmp/claudebell.log` shows a `stampSessionMarker:` line.

- [ ] **Step 7: Commit**

```bash
git add Sources/Server/HookServer.swift
git commit -m "Stamp session tab marker on Stop and Notification hooks"
```

---

### Task 4: Match on the marker at reply time

**Files:**
- Modify: `Sources/Terminal/TerminalBridge.swift` (`sendText`, `focusTerminalTab`, `terminalMatchScript`, `sendiTerm2Paste`, `focusiTerm2`)

**Interfaces:**
- Consumes: `markerString(code:)`; the caller-supplied `marker` (Terminal.app) and `iTermSessionId` (iTerm2).
- Produces: `sendText` / `focusTerminalTab` gain `marker: String? = nil` and `iTermSessionId: String? = nil` parameters; the match scripts gain a highest-priority marker pass.

- [ ] **Step 1: Thread `marker` / `iTermSessionId` through `sendText`**

In `Sources/Terminal/TerminalBridge.swift`, change the `sendText` signature and the routed calls. New signature:

```swift
    @discardableResult
    static func sendText(_ text: String, toCwd cwd: String, transcriptPath: String = "", knownTty: String? = nil, activateOnFailure: Bool = true, marker: String? = nil, iTermSessionId: String? = nil) -> Bool {
```

Inside `sendText`, the exact-tty block currently calls `sendiTerm2Paste`/`sendTerminalPaste` with `exactTtyOnly: true`. Before that block, add a marker pass that wins outright when it lands:

```swift
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
```

(The existing `if let tty = trustedTty {` becomes `if let tty = trustedTty, !sent {` so the tty passes are skipped once the marker pass succeeded. The rest of the method — fuzzy fallback, clipboard handling, `return sent` — is unchanged.)

- [ ] **Step 2: Add the marker pass to `terminalMatchScript`**

In `terminalMatchScript`, add a `marker` parameter and a Pass −1 before the existing Pass 0. New signature:

```swift
    private static func terminalMatchScript(cwd: String, action: String, tty: String? = nil, exactTtyOnly: Bool = false, marker: String = "") -> String {
```

Immediately after the `\(action == "focus" ? "activate" : "set theText to the clipboard as text")` line and before the `-- Pass 0` comment, insert:

```swift
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
```

Update `sendTerminalPaste` and `focusTerminal` to accept and forward `marker`:

```swift
    private static func sendTerminalPaste(cwd: String, tty: String? = nil, exactTtyOnly: Bool = false, marker: String = "") -> Bool {
        let script = terminalMatchScript(cwd: cwd, action: "paste", tty: tty, exactTtyOnly: exactTtyOnly, marker: marker)
        return runAppleScript(script)
    }

    private static func focusTerminal(cwd: String, tty: String? = nil, marker: String = "") -> Bool {
        let script = terminalMatchScript(cwd: cwd, action: "focus", tty: tty, marker: marker)
        return runAppleScript(script)
    }
```

- [ ] **Step 3: Add the id pass to `sendiTerm2Paste` and `focusiTerm2`**

Add an `iTermSessionId` parameter to `sendiTerm2Paste`:

```swift
    private static func sendiTerm2Paste(cwd: String, tty: String? = nil, exactTtyOnly: Bool = false, iTermSessionId: String? = nil) -> Bool {
```

Inside its script, before the `-- Pass 0: exact tty match` block, insert a marker-id pass:

```swift
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
```

Do the same for `focusiTerm2` (add the parameter; in its Pass −1 use `select t` / `select s` / `return true` without the `write text`).

- [ ] **Step 4: Forward the new args from the exact-tty routing block**

In `sendText`, the owning-app `switch terminalBundleForTty(tty)` block calls `sendiTerm2Paste(... exactTtyOnly: true)` / `sendTerminalPaste(... exactTtyOnly: true)`. Those calls do NOT need the marker (Pass −1 already ran above), so leave them. But `focusTerminalTab` must forward the marker/id — update it:

```swift
    static func focusTerminalTab(forCwd cwd: String, transcriptPath: String = "", knownTty: String? = nil, marker: String? = nil, iTermSessionId: String? = nil) {
        let resolvedTty = knownTty ?? resolveTty(fromTranscriptPath: transcriptPath)
        DispatchQueue.global(qos: .userInitiated).async {
            if focusiTerm2(cwd: cwd, tty: resolvedTty, iTermSessionId: iTermSessionId) { return }
            if focusTerminal(cwd: cwd, tty: resolvedTty, marker: marker ?? "") { return }
            DispatchQueue.main.async { activateTerminal() }
        }
    }
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/Terminal/TerminalBridge.swift
git commit -m "Match replies on the session tab marker before tty/cwd/fuzzy"
```

---

### Task 5: Pass the marker from the reply call sites

**Files:**
- Modify: `Sources/Views/ContentView.swift` (`sendReply`, session "open in terminal" focus, notification focus buttons)
- Modify: `Sources/Views/QuestionOptionsView.swift` (`sendTextTwoStep` call)
- Modify: `Sources/Views/ExitPlanModeView.swift` (`send`)

**Interfaces:**
- Consumes: `RequestStore.sessionMarkerCode(for:)`, `RequestStore.iTermSessionId(for:)`, `TerminalBridge.markerString(code:)`, updated `sendText` / `focusTerminalTab`.

- [ ] **Step 1: Pass marker + iTerm id from `ContentView.sendReply`**

In `Sources/Views/ContentView.swift`, in `sendReply`, update the `TerminalBridge.sendText` call:

```swift
        let sid = notification.sessionId
        let sent = TerminalBridge.sendText(
            text,
            toCwd: notification.cwd,
            transcriptPath: notification.transcriptPath,
            knownTty: store.resolvedTty(for: sid),
            activateOnFailure: false,
            marker: TerminalBridge.markerString(code: store.sessionMarkerCode(for: sid)),
            iTermSessionId: store.iTermSessionId(for: sid)
        )
```

- [ ] **Step 2: Pass marker/id from the focus buttons**

In `Sources/Views/ContentView.swift`, update the three `focusTerminalTab` calls (session row "open in terminal" at line ~404, and the two notification focus buttons at lines ~257 and ~330) to include marker + id. Example for the session row (`session.id`):

```swift
                            TerminalBridge.focusTerminalTab(
                                forCwd: session.cwd,
                                knownTty: store.resolvedTty(for: session.id),
                                marker: TerminalBridge.markerString(code: store.sessionMarkerCode(for: session.id)),
                                iTermSessionId: store.iTermSessionId(for: session.id)
                            )
```

For the two notification focus buttons use `notification.sessionId` in place of `session.id` and `notification.cwd` / `notification.transcriptPath` as already present.

- [ ] **Step 3: Pass marker/id from `QuestionOptionsView` two-step paste**

In `Sources/Views/QuestionOptionsView.swift`, the view already has `knownTty`, `cwd`, `transcriptPath`. Add two stored properties so the parent can supply the marker/id:

```swift
    var knownTty: String? = nil
    var markerCode: String? = nil
    var iTermSessionId: String? = nil
    var cwd: String = ""
```

Update the `sendTextTwoStep` call in `sendFreeText`:

```swift
            let sent = TerminalBridge.sendTextTwoStep(option.token ?? "\(option.index)", then: text, toCwd: cwd, transcriptPath: transcriptPath, knownTty: knownTty)
```

`sendTextTwoStep` → `sendText` must forward the marker. Update `sendTextTwoStep` in `TerminalBridge` to accept `marker`/`iTermSessionId` and pass them to its `sendText(first,…)` call, then pass them here:

```swift
            let markerStr = markerCode.map { TerminalBridge.markerString(code: $0) }
            let sent = TerminalBridge.sendTextTwoStep(option.token ?? "\(option.index)", then: text, toCwd: cwd, transcriptPath: transcriptPath, knownTty: knownTty, marker: markerStr, iTermSessionId: iTermSessionId)
```

And in `TerminalBridge.sendTextTwoStep`:

```swift
    @discardableResult
    static func sendTextTwoStep(_ first: String, then second: String, toCwd cwd: String, transcriptPath: String = "", knownTty: String? = nil, marker: String? = nil, iTermSessionId: String? = nil) -> Bool {
        logToFile("sendTextTwoStep: first=\"\(first)\", then=\"\(second)\" → cwd: \(cwd)")
        let sent = sendText(first, toCwd: cwd, transcriptPath: transcriptPath, knownTty: knownTty, marker: marker, iTermSessionId: iTermSessionId)
        if sent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                sendText(second, toCwd: cwd, transcriptPath: transcriptPath, knownTty: knownTty, marker: marker, iTermSessionId: iTermSessionId)
            }
        }
        return sent
    }
```

Finally, in `Sources/Views/ContentView.swift` where `QuestionOptionsView(...)` is constructed (line ~308), pass the new args:

```swift
                            knownTty: store.resolvedTty(for: notification.sessionId),
                            markerCode: store.sessionMarkerCode(for: notification.sessionId),
                            iTermSessionId: store.iTermSessionId(for: notification.sessionId),
                            cwd: notification.cwd,
```

- [ ] **Step 4: Pass marker/id from `ExitPlanModeView.send`**

In `Sources/Views/ExitPlanModeView.swift`, `send` uses `request.cwd` / `request.transcriptPath`. `PendingRequest` carries `sessionId` (confirm the property name; it is used elsewhere as `request.sessionId`). Update the `sendText` call:

```swift
        let sent = TerminalBridge.sendText(
            text,
            toCwd: request.cwd,
            transcriptPath: request.transcriptPath,
            marker: TerminalBridge.markerString(code: RequestStore.markerCode(from: request.sessionId)),
            iTermSessionId: store.iTermSessionId(for: request.sessionId)
        )
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: `Build complete!` with no errors. (`PendingRequest.sessionId` and the `store` reference are both already present in `ExitPlanModeView`.)

- [ ] **Step 6: End-to-end manual verification**

Restart the app (`cp … && pkill -x ClaudeBell; sleep 1; open ClaudeBell.app`). Reproduce the original bug and confirm the fix:

1. Open **two** Terminal.app tabs, run `claude` in the *same* project directory in both.
2. Keep a terminal frontmost and let ONE session finish a turn (so no Stop hold is taken — `HookServer.swift:204`).
3. Verify both tabs got distinct `⟨cb:…⟩` markers (`osascript -e 'tell application "Terminal" to get custom title of every tab of every window'`).
4. From the ClaudeBell panel, type a follow-up reply to that session's stop card.
5. Expected: the text lands in the **correct** tab (the one whose marker matches), even though both share a cwd. Confirm `/tmp/claudebell.log` shows `sendText: delivered=true`.
6. Churn test: close/reopen tabs to recycle ttys, repeat step 4, confirm still-correct targeting.

- [ ] **Step 7: Commit**

```bash
git add Sources/Views/ContentView.swift Sources/Views/QuestionOptionsView.swift Sources/Views/ExitPlanModeView.swift Sources/Terminal/TerminalBridge.swift
git commit -m "Pass session marker/iTerm-id from reply call sites"
```

---

## Notes for the implementer

- **iTerm2 `id of session`**: verify Task 2/3 on a running iTerm2. If `id of s as text` comes back empty or unusable, the `stampITerm2` fallback already writes the marker into the session `name`; in that case also add a `name contains marker` branch to the iTerm2 Pass −1 (mirroring the Terminal.app custom-title pass) and match on `markerString` instead of the id. Prefer the id path when it works (no title pollution).
- **AppleScript string escaping**: the marker contains only `⟨cb:` + hex + `⟩` (no quotes/backslashes), so it is safe to interpolate into the double-quoted AppleScript literals. Do not pass user text through these scripts.
- **Idempotency**: `stampTerminalApp` early-exits when the marker is already present, so re-stamping on every Stop is cheap and never duplicates the suffix.
- **No behavioral regression**: every match script keeps its original passes below the new Pass −1; when `marker`/`iTermSessionId` are empty the new pass is skipped entirely.
