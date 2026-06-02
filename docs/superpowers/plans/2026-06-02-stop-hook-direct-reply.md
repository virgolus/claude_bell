# Stop-Hook Direct Reply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver ClaudeBell panel replies to text questions and follow-ups through a held Stop hook (`{"decision":"block","reason":…}`) instead of AppleScript keystroke injection.

**Architecture:** The `/hooks/stop` endpoint becomes a long-poll (continuation held in `RequestStore`, same pattern as `/hooks/permission-request`). A panel reply resumes the continuation with a block+reason JSON; timeout, panel dismiss, terminal-app focus, Esc (connection abort), and SessionEnd release it with `{}` so the stop completes normally. A new `UserPromptSubmit` hook dismisses stale notifications when the user replies in the terminal. The existing `TerminalBridge` path is the unchanged fallback for replies after the hold expires.

**Tech Stack:** Swift 5.10/6.3 toolchain (CLT only — **no XCTest/Swift Testing available; `swift test` does not work in this environment**), SwiftUI, Hummingbird 2. Verification = `swift build` + curl smoke tests against the running app + manual E2E (per CLAUDE.md testing workflow).

**Spec:** `docs/superpowers/specs/2026-06-02-stop-hook-direct-reply-design.md`

**Branch:** `feature/stop-hook-direct-reply`

---

### Task 1: Branch setup + HookResponse stop builders

**Files:**
- Modify: `Sources/Models/HookResponse.swift`

- [ ] **Step 1: Create the feature branch and commit pre-existing WIP**

There are uncommitted pre-existing changes (`Sources/Terminal/TerminalBridge.swift` paste fix, `Sources/Views/ContentView.swift` dismiss-on-focus, `ClaudeBell.app/Contents/_CodeSignature/CodeResources`). Commit them first as their own commit so feature commits stay clean.

```bash
git checkout -b feature/stop-hook-direct-reply
git add Sources/Terminal/TerminalBridge.swift Sources/Views/ContentView.swift ClaudeBell.app/Contents/_CodeSignature/CodeResources
git commit -m "Carry over v1.12.2 paste + panel-dismiss WIP"
```

- [ ] **Step 2: Add stop-hook response builders**

In `Sources/Models/HookResponse.swift`, add inside `struct HookResponse` (after `permissionDecisionAllowWithUpdatedInput`, before `toHTTPResponse()`):

```swift
    /// Stop hook: block the stop and deliver the user's panel reply as the
    /// reason. Claude Code injects it into the conversation as
    /// "Stop hook feedback: <reason>" and resumes working on it.
    static func stopBlock(reason userText: String) -> HookResponse {
        let payload: [String: Any] = [
            "decision": "block",
            "reason": "L'utente ha risposto da ClaudeBell: \(userText)"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            print("[HookResponse] WARNING: stopBlock serialization failed, falling back")
            return HookResponse(json: #"{"decision":"block","reason":"L'utente ha risposto da ClaudeBell (testo non serializzabile)."}"#)
        }
        return HookResponse(json: json)
    }

    /// Stop hook: let the stop complete normally (release without blocking).
    static func stopAllow() -> HookResponse {
        HookResponse(json: "{}")
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/Models/HookResponse.swift
git commit -m "Add Stop-hook block/allow response builders"
```

---

### Task 2: PendingStop model

**Files:**
- Create: `Sources/Models/PendingStop.swift`

- [ ] **Step 1: Create the model**

Create `Sources/Models/PendingStop.swift` (mirrors `PendingRequest`):

```swift
import Foundation

/// A held Stop hook: the HTTP request from Claude Code stays open until the
/// user replies from the panel (block+reason) or the hold is released
/// (timeout, dismiss, terminal focus, Esc, SessionEnd) — in which case the
/// stop completes normally.
@MainActor
final class PendingStop: Identifiable, ObservableObject {
    let id = UUID()
    let sessionId: String
    let cwd: String
    let transcriptPath: String
    let createdAt: Date
    let expiresAt: Date
    private let continuation: CheckedContinuation<HookResponse, Never>
    private var hasResponded = false

    init(
        sessionId: String,
        cwd: String,
        transcriptPath: String,
        holdSeconds: TimeInterval,
        continuation: CheckedContinuation<HookResponse, Never>
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(holdSeconds)
        self.continuation = continuation
    }

    /// Deliver the user's reply: Claude resumes with the reason text.
    func answer(_ text: String) {
        guard !hasResponded else { return }
        hasResponded = true
        let response = HookResponse.stopBlock(reason: text)
        print("[PendingStop] Answering session \(sessionId): \(response.json)")
        continuation.resume(returning: response)
    }

    /// Release without blocking: the stop completes normally.
    func release() {
        guard !hasResponded else { return }
        hasResponded = true
        print("[PendingStop] Releasing session \(sessionId)")
        continuation.resume(returning: HookResponse.stopAllow())
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Models/PendingStop.swift
git commit -m "Add PendingStop model for held Stop hooks"
```

---

### Task 3: DirectReplySettings

**Files:**
- Create: `Sources/Utilities/DirectReplySettings.swift`

- [ ] **Step 1: Create the settings accessor**

```swift
import Foundation

/// Hold duration for the Stop-hook direct-reply channel.
/// The hook `timeout` written to ~/.claude/settings.json gets a 60 s margin
/// on top so ClaudeBell always self-releases before Claude Code gives up.
enum DirectReplySettings {
    static let presets: [(label: String, seconds: Int)] = [
        ("5 minutes", 300),
        ("30 minutes", 1800),
        ("4 hours", 14400),
        ("24 hours", 86400),
    ]

    static let defaultHoldSeconds = 300

    static var holdSeconds: Int {
        get {
            let value = AppDefaults.shared.integer(forKey: "directReplyHoldSeconds")
            return value > 0 ? value : defaultHoldSeconds
        }
        set { AppDefaults.shared.set(newValue, forKey: "directReplyHoldSeconds") }
    }

    /// Hook timeout written to settings.json: hold + 60 s margin.
    static var hookTimeoutSeconds: Int { holdSeconds + 60 }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Utilities/DirectReplySettings.swift
git commit -m "Add DirectReplySettings hold-duration accessor"
```

---

### Task 4: RequestStore hold registry

**Files:**
- Modify: `Sources/Store/RequestStore.swift`

- [ ] **Step 1: Add the pendingStops registry**

In `Sources/Store/RequestStore.swift`, add after the `@Published var sessions` property (line 11):

```swift
    /// Held Stop hooks keyed by sessionId. Views observe this to decide
    /// whether a reply travels through the hook (direct) or TerminalBridge.
    @Published var pendingStops: [String: PendingStop] = [:]
```

Add these methods after `removeNotification(id:)` (line 102):

```swift
    /// Register a held Stop hook. Any previous hold for the same session is
    /// stale (Claude stopped again) — release it first.
    func registerStopHold(_ stop: PendingStop) {
        pendingStops[stop.sessionId]?.release()
        pendingStops[stop.sessionId] = stop
        startStopHoldTimer(for: stop)
    }

    /// Deliver a panel reply through the held Stop hook.
    /// Returns false when no live hold exists (caller falls back to TerminalBridge).
    func answerStopHold(sessionId: String, text: String) -> Bool {
        guard let stop = pendingStops.removeValue(forKey: sessionId) else { return false }
        stop.answer(text)
        return true
    }

    /// Release one session's hold: the stop completes normally.
    /// The notification (if any) stays in the panel.
    func releaseStopHold(sessionId: String) {
        pendingStops.removeValue(forKey: sessionId)?.release()
    }

    /// Focus-release: a terminal app became frontmost — release every hold so
    /// the console is immediately responsive. Notifications stay.
    func releaseAllStopHolds() {
        guard !pendingStops.isEmpty else { return }
        print("[RequestStore] Focus-release: releasing \(pendingStops.count) held stop(s)")
        for (_, stop) in pendingStops { stop.release() }
        pendingStops.removeAll()
    }

    private func startStopHoldTimer(for stop: PendingStop) {
        let stopId = stop.id
        let sessionId = stop.sessionId
        Task { @MainActor [weak self] in
            let interval = stop.expiresAt.timeIntervalSinceNow
            if interval > 0 {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            guard let self, let current = self.pendingStops[sessionId], current.id == stopId else { return }
            self.releaseStopHold(sessionId: sessionId)
        }
    }
```

- [ ] **Step 2: Release holds on session end and on new permission requests**

In `removeSession(id:)` (line 108), add the release before `denyStaleRequests`:

```swift
    func removeSession(id: String) {
        releaseStopHold(sessionId: id)
        denyStaleRequests(id: id)
        sessions.removeValue(forKey: id)
    }
```

In `addRequest(_:)` (line 47), a new permission request means Claude is running again — any hold for that session is stale. Add as the first line of the method body:

```swift
        releaseStopHold(sessionId: request.sessionId)
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/Store/RequestStore.swift
git commit -m "Add held Stop hook registry to RequestStore"
```

---

### Task 5: HookServer long-poll + UserPromptSubmit endpoint

**Files:**
- Modify: `Sources/Server/HookServer.swift:103-126` (the `/hooks/stop` route) and add a new route after `/hooks/pre-tool-use`

- [ ] **Step 1: Replace the `/hooks/stop` route**

Replace the entire existing `router.post("/hooks/stop")` block (lines 103–126) with:

```swift
        router.post("/hooks/stop") { request, context -> Response in
            let input = try await Self.decodeInput(request, label: "Stop")

            // Check if the last assistant message is actually a question —
            // if so, show as interactive idle_prompt instead of passive stop.
            let hasQuestion = Self.transcriptHasPendingQuestion(path: input.transcriptPath ?? "")
            let effectiveType = hasQuestion ? "idle_prompt" : "stop"

            let entry = NotificationEntry(
                sessionId: input.sessionId,
                cwd: input.cwd,
                notificationType: effectiveType,
                message: input.lastAssistantMessage ?? "",
                title: "",
                transcriptPath: input.transcriptPath ?? "",
                createdAt: Date()
            )

            let sessionId = input.sessionId
            let cwd = input.cwd
            let transcriptPath = input.transcriptPath ?? ""
            let holdSeconds = TimeInterval(DirectReplySettings.holdSeconds)

            // Hold the request open: a panel reply resumes it with
            // {"decision":"block","reason":…}; timeout/dismiss/focus/SessionEnd
            // resume it with {} (normal stop). Esc in the terminal aborts the
            // connection → onCancel releases the hold.
            let response = await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<HookResponse, Never>) in
                    Task { @MainActor in
                        let pending = PendingStop(
                            sessionId: sessionId,
                            cwd: cwd,
                            transcriptPath: transcriptPath,
                            holdSeconds: holdSeconds,
                            continuation: continuation
                        )
                        store.registerStopHold(pending)
                        store.sessionAdvanced(id: sessionId)
                        store.addNotification(entry)
                    }
                }
            } onCancel: {
                // Connection aborted (Esc / Claude exited). If this races the
                // registration task and finds nothing, the hold timer is the
                // backstop: it resumes the orphan continuation at expiry and
                // the response is discarded on the dead connection.
                Task { @MainActor in
                    store.releaseStopHold(sessionId: sessionId)
                }
            }

            return response.toHTTPResponse()
        }
```

- [ ] **Step 2: Add the `/hooks/user-prompt-submit` route**

Add after the `router.post("/hooks/pre-tool-use")` block (after line 175):

```swift
        router.post("/hooks/user-prompt-submit") { request, context -> Response in
            let input = try await Self.decodeInput(request, label: "UserPromptSubmit")
            Task { @MainActor in
                // The user replied in the terminal: release any hold for the
                // session (defensive — a live hold can't normally coexist with
                // a prompt submission) and dismiss its stale notifications.
                store.releaseStopHold(sessionId: input.sessionId)
                store.sessionAdvanced(id: input.sessionId)
                store.trackSessionPublic(id: input.sessionId, cwd: input.cwd)
            }
            return Response(status: .ok)
        }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Smoke-test hold and release with curl**

```bash
swift build -c release
cp .build/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
codesign --force --deep --sign - ClaudeBell.app
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app; sleep 2
# Hold: this request must NOT return immediately
curl -s -X POST http://localhost:19485/hooks/stop \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"smoke","cwd":"/tmp","transcript_path":""}' > /tmp/hold-response.txt &
sleep 2
# Release via user-prompt-submit
curl -s -X POST http://localhost:19485/hooks/user-prompt-submit \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"smoke","cwd":"/tmp"}'
wait
cat /tmp/hold-response.txt
```

Expected: the first curl stays open for ~2 s (not instant), then `/tmp/hold-response.txt` contains `{}`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Server/HookServer.swift
git commit -m "Hold Stop hook as long-poll; add UserPromptSubmit endpoint"
```

---

### Task 6: HookInstaller — UserPromptSubmit, dynamic Stop timeout, block cap

**Files:**
- Modify: `Sources/Setup/HookInstaller.swift`

- [ ] **Step 1: Make the Stop hook timeout dynamic**

In `install()`, change the Stop hook entry (line 50–57) from `"timeout": 10` to:

```swift
        // Stop hook (agent finished) — long-poll for direct replies.
        // Timeout = hold duration + 60 s margin so ClaudeBell always
        // self-releases before Claude Code gives up on the hook.
        let stopHook: [String: Any] = [
            "matcher": "",
            "hooks": [[
                "type": "http",
                "url": "http://localhost:19485/hooks/stop",
                "timeout": DirectReplySettings.hookTimeoutSeconds
            ] as [String: Any]]
        ]
```

- [ ] **Step 2: Add the UserPromptSubmit hook**

In `install()`, after the Notification hook block (after line 147, before `settings["hooks"] = hooks`):

```swift
        // UserPromptSubmit hook (user replied in terminal → dismiss stale notifications)
        let promptSubmitHook: [String: Any] = [
            "matcher": "",
            "hooks": [[
                "type": "http",
                "url": "http://localhost:19485/hooks/user-prompt-submit",
                "timeout": 10
            ] as [String: Any]]
        ]

        var promptSubmitArray = hooks["UserPromptSubmit"] as? [[String: Any]] ?? []
        promptSubmitArray.removeAll { entry in
            if let hooksList = entry["hooks"] as? [[String: Any]] {
                return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
            }
            return false
        }
        promptSubmitArray.append(promptSubmitHook)
        hooks["UserPromptSubmit"] = promptSubmitArray
```

- [ ] **Step 3: Raise the consecutive-block cap**

Still in `install()`, after `settings["hooks"] = hooks` (line 149) and before `try writeSettings(settings)`:

```swift
        // Each panel reply is one Stop-hook "block". Claude Code's default cap
        // of 8 consecutive blocks would kill long question chains (e.g.
        // superpowers brainstorming). Only set it when the user hasn't.
        var env = settings["env"] as? [String: Any] ?? [:]
        if env["CLAUDE_CODE_STOP_HOOK_BLOCK_CAP"] == nil {
            env["CLAUDE_CODE_STOP_HOOK_BLOCK_CAP"] = "50"
        }
        settings["env"] = env
```

- [ ] **Step 4: Extend uninstall()**

In `uninstall()`, after the Notification removal block (after line 247) and before the final `if hooks.isEmpty`:

```swift
        // Remove Claude Bell entries from UserPromptSubmit
        if var promptSubmitArray = hooks["UserPromptSubmit"] as? [[String: Any]] {
            promptSubmitArray.removeAll { entry in
                if let hooksList = entry["hooks"] as? [[String: Any]] {
                    return hooksList.contains { ($0["url"] as? String)?.contains("19485") == true }
                }
                return false
            }
            if promptSubmitArray.isEmpty {
                hooks.removeValue(forKey: "UserPromptSubmit")
            } else {
                hooks["UserPromptSubmit"] = promptSubmitArray
            }
        }
```

And after the `if hooks.isEmpty { … } else { … }` block, before `try writeSettings(settings)`:

```swift
        // Remove the block cap only if it is still our value
        if var env = settings["env"] as? [String: Any],
           env["CLAUDE_CODE_STOP_HOOK_BLOCK_CAP"] as? String == "50" {
            env.removeValue(forKey: "CLAUDE_CODE_STOP_HOOK_BLOCK_CAP")
            if env.isEmpty {
                settings.removeValue(forKey: "env")
            } else {
                settings["env"] = env
            }
        }
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 6: Verify install/uninstall round-trip on the real settings file**

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
```

Rebuild + restart the app:

```bash
swift build -c release
cp .build/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
codesign --force --deep --sign - ClaudeBell.app
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app; sleep 2
```

Then in **Settings → General**: click *Remove Hooks*, then *Install Hooks…*. Inspect:

```bash
python3 -c "
import json
s = json.load(open('$HOME/.claude/settings.json'))
print('Stop timeout:', s['hooks']['Stop'][-1]['hooks'][0]['timeout'])
print('UserPromptSubmit:', 'UserPromptSubmit' in s['hooks'])
print('block cap:', s.get('env', {}).get('CLAUDE_CODE_STOP_HOOK_BLOCK_CAP'))
"
```

Expected: `Stop timeout: 360`, `UserPromptSubmit: True`, `block cap: 50`.

- [ ] **Step 7: Commit**

```bash
git add Sources/Setup/HookInstaller.swift
git commit -m "Install UserPromptSubmit hook, dynamic Stop timeout, block cap"
```

---

### Task 7: TerminalFocusObserver (focus-release)

**Files:**
- Create: `Sources/App/TerminalFocusObserver.swift`
- Modify: `Sources/App/ClaudeBellApp.swift:84` (`applicationDidFinishLaunching`)

- [ ] **Step 1: Create the observer**

Create `Sources/App/TerminalFocusObserver.swift`:

```swift
import AppKit

/// Releases all held Stop hooks when a terminal app becomes frontmost
/// (focus-release): if the user goes to the terminal, the console must be
/// immediately responsive. Notifications stay in the panel — only the
/// direct-reply channel for those turns downgrades to the terminal fallback.
@MainActor
final class TerminalFocusObserver {
    static let shared = TerminalFocusObserver()

    static let terminalBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
    ]

    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier,
                  Self.terminalBundleIds.contains(bundleId) else { return }
            Task { @MainActor in
                RequestStore.shared.releaseAllStopHolds()
            }
        }
    }
}
```

- [ ] **Step 2: Start it at launch**

In `Sources/App/ClaudeBellApp.swift`, inside `applicationDidFinishLaunching`, after the `RequestStore.shared.onDismissPanel` wiring (line 101):

```swift
        // Focus-release: terminal frontmost → release all held Stop hooks
        TerminalFocusObserver.shared.start()
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Smoke-test focus-release with curl**

Rebuild + restart the app:

```bash
swift build -c release
cp .build/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
codesign --force --deep --sign - ClaudeBell.app
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app; sleep 2
```

Then:

```bash
curl -s -X POST http://localhost:19485/hooks/stop \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"focus-smoke","cwd":"/tmp","transcript_path":""}' > /tmp/focus-response.txt &
sleep 2
open -a Terminal
wait
cat /tmp/focus-response.txt
```

Expected: activating Terminal releases the hold; the held curl returns `{}` immediately after `open -a Terminal`.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/TerminalFocusObserver.swift Sources/App/ClaudeBellApp.swift
git commit -m "Release held Stop hooks when a terminal app gains focus"
```

---

### Task 8: UI routing — direct reply with terminal fallback + countdown badge

**Files:**
- Create: `Sources/Views/DirectReplyBadge.swift`
- Modify: `Sources/Views/ContentView.swift:244-343` (`notificationDetail`)
- Modify: `Sources/Views/QuestionOptionsView.swift`

- [ ] **Step 1: Create the countdown badge**

Create `Sources/Views/DirectReplyBadge.swift`:

```swift
import SwiftUI

/// Shows that a live Stop-hook hold exists for the session: replies go
/// straight through the hook (no keystroke injection) until it expires.
struct DirectReplyBadge: View {
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(expiresAt.timeIntervalSince(context.date)))
            if remaining > 0 {
                Label("Direct reply · \(Self.format(remaining))", systemImage: "bolt.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    static func format(_ seconds: Int) -> String {
        if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
```

- [ ] **Step 2: Route notification replies through the hold in ContentView**

In `Sources/Views/ContentView.swift`, add this helper method to `ContentView` (next to `notificationDetail`):

```swift
    /// Send a reply for a stop/idle_prompt notification: through the held
    /// Stop hook when alive (direct, no keystrokes), else via TerminalBridge.
    private func sendReply(_ text: String, for notification: NotificationEntry) {
        if !store.answerStopHold(sessionId: notification.sessionId, text: text) {
            TerminalBridge.sendText(text, toCwd: notification.cwd, transcriptPath: notification.transcriptPath)
        }
        store.removeNotification(id: notification.id)
        selectedItem = nil
    }
```

In `notificationDetail(_:)`:

a) After the header `Divider()` (line 273), add the badge:

```swift
                    if let stop = store.pendingStops[notification.sessionId] {
                        DirectReplyBadge(expiresAt: stop.expiresAt)
                    }
```

b) Replace the `FollowUpActionView` `onSend` closure body (lines 287–291):

```swift
                        FollowUpActionView(
                            notification: notification,
                            onSend: { text in
                                sendReply(text, for: notification)
                            }
                        )
```

c) Replace the `QuestionOptionsView` call (lines 305–318):

```swift
                        QuestionOptionsView(
                            questions: questions,
                            onSend: { text in
                                sendReply(text, for: notification)
                            },
                            hasDirectChannel: store.pendingStops[notification.sessionId] != nil,
                            cwd: notification.cwd,
                            transcriptPath: notification.transcriptPath,
                            onDismiss: {
                                store.removeNotification(id: notification.id)
                                selectedItem = nil
                            }
                        )
```

d) Replace the `TextInputView` `onSend` closure body (lines 323–327):

```swift
                            onSend: { text in
                                sendReply(text, for: notification)
                            },
```

- [ ] **Step 3: Direct free-text path in QuestionOptionsView**

In `Sources/Views/QuestionOptionsView.swift`:

a) Add the property after `onAnswers` (line 9):

```swift
    /// True when a live Stop-hook hold exists for this session: free text is
    /// delivered as the hook reason in a single message (no option-token +
    /// text two-step, which only exists for the terminal-typing path).
    var hasDirectChannel: Bool = false
```

b) In `sendFreeText(_:)` (line 211), add the direct branch after the `onAnswers` branch:

```swift
    private func sendFreeText(_ text: String) {
        if let onAnswers, let firstQuestion = questions.first {
            onAnswers([firstQuestion.question: text], nil)
            return
        }
        if hasDirectChannel {
            onSend(text)
            return
        }
        if let firstQuestion = questions.first,
           let option = Self.freeTextOption(in: firstQuestion),
           !cwd.isEmpty {
            TerminalBridge.sendTextTwoStep(option.token ?? "\(option.index)", then: text, toCwd: cwd, transcriptPath: transcriptPath)
            onDismiss?()
        } else {
            onSend(text)
        }
    }
```

Note: `hasDirectChannel` must be declared **before** `cwd`/`transcriptPath` or passed with its label in the call — the ContentView call in Step 2c passes it after `onSend`, so keep the member order: `onAnswers`, `hasDirectChannel`, `cwd`, `transcriptPath`, `onDismiss`.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/Views/DirectReplyBadge.swift Sources/Views/ContentView.swift Sources/Views/QuestionOptionsView.swift
git commit -m "Route panel replies through held Stop hook with countdown badge"
```

---

### Task 9: Settings UI — hold duration picker

**Files:**
- Modify: `Sources/Views/SettingsContainerView.swift:27-216` (`GeneralSettingsTab`)

- [ ] **Step 1: Add the picker**

In `GeneralSettingsTab`, add the state property after `showHookConfirm` (line 30):

```swift
    @State private var holdSeconds = DirectReplySettings.holdSeconds
```

Add this Section after the Hooks section (after line 93, before the Auto Mode section):

```swift
            // MARK: Direct Reply
            Section {
                Picker("Hold duration", selection: $holdSeconds) {
                    ForEach(DirectReplySettings.presets, id: \.seconds) { preset in
                        Text(preset.label).tag(preset.seconds)
                    }
                }
                .onChange(of: holdSeconds) { _, newValue in
                    DirectReplySettings.holdSeconds = newValue
                    // Rewrite the Stop hook timeout to match
                    if hooksInstalled {
                        do {
                            try HookInstaller.install()
                            hooksError = nil
                        } catch {
                            hooksError = error.localizedDescription
                        }
                    }
                }
            } header: {
                sectionHeader("Direct Reply", systemImage: "bolt")
            } footer: {
                Text("After Claude finishes a turn, ClaudeBell keeps a direct channel open for this long: panel replies are delivered through the Stop hook instead of typing into the terminal. Pressing Esc in the terminal or focusing a terminal app releases it early.")
            }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Verify the timeout follows the setting**

Rebuild + restart the app:

```bash
swift build -c release
cp .build/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
codesign --force --deep --sign - ClaudeBell.app
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app; sleep 2
```

In Settings → General set *Hold duration* to "30 minutes", then:

```bash
python3 -c "
import json
s = json.load(open('$HOME/.claude/settings.json'))
print('Stop timeout:', s['hooks']['Stop'][-1]['hooks'][0]['timeout'])
"
```

Expected: `Stop timeout: 1860`. Set it back to "5 minutes" and re-check (expected `360`).

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/SettingsContainerView.swift
git commit -m "Add Direct Reply hold-duration setting"
```

---

### Task 10: Docs + end-to-end verification

**Files:**
- Modify: `CLAUDE.md` (hooks list)

- [ ] **Step 1: Update CLAUDE.md hooks list**

In `CLAUDE.md`, section "Hooks configuration", replace:

```
The full list: PermissionRequest, Notification, PreToolUse, PostToolUseFailure, Stop, SessionEnd.
```

with:

```
The full list: PermissionRequest, Notification, PreToolUse, PostToolUseFailure, Stop, SessionEnd, UserPromptSubmit. The Stop hook is a long-poll: ClaudeBell holds it open (configurable, default 5 min) and answers `{"decision":"block","reason":…}` to deliver panel replies directly — see docs/superpowers/specs/2026-06-02-stop-hook-direct-reply-design.md.
```

- [ ] **Step 2: Full rebuild, re-sign, restart**

```bash
swift build -c release
cp .build/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
codesign --force --deep --sign - ClaudeBell.app
codesign --verify --deep --strict ClaudeBell.app && echo SIGNED-OK
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app
```

Expected: `SIGNED-OK`. Note (CLAUDE.md): rebuilding may invalidate the Accessibility grant for the TerminalBridge fallback — if AppleScript error 1002 appears later, re-add ClaudeBell.app in System Settings → Privacy & Security → Accessibility.

- [ ] **Step 3: E2E with a real Claude Code session**

From a terminal, in any project: `claude --model haiku`, prompt: `ask me a question with two numbered options, then wait`. When Claude stops:

1. ClaudeBell shows the question notification with the orange "Direct reply" countdown badge.
2. Click an option in the panel → the terminal session resumes by itself (no typing, no window focus change); the transcript (`~/.claude/projects/...jsonl`) contains `Stop hook feedback: L'utente ha risposto da ClaudeBell: …`.
3. Repeat with a new question; this time reply **in the terminal**: the notification disappears from ClaudeBell (UserPromptSubmit).
4. Repeat; press **Esc** in the terminal during the hold: badge disappears (hold released), notification stays.
5. Repeat; bring Terminal to front without typing: badge disappears (focus-release), notification stays, panel reply now goes through TerminalBridge.
6. `/exit` the session: notification cleanup as before.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "Document UserPromptSubmit hook and Stop long-poll in CLAUDE.md"
```

---

### Task 11: Exact tty targeting for the terminal fallback

*(Added mid-execution at user request: the fuzzy fallback picks the wrong Terminal.app tab almost every time. Root cause: `resolveTty` via `lsof <transcript>` never finds a PID — Claude Code doesn't keep the transcript open. Fix: capture the claude PID from the hook's TCP connection (peer port → `lsof` → PID → `ps` tty), store `session → tty`, and let `TerminalBridge` use the exact Pass-0 tty match.)*

**Files:**
- Modify: `Sources/Server/HookServer.swift` (custom request context exposing `remoteAddress`; tty capture on hook arrival)
- Modify: `Sources/Models/SessionInfo.swift` (add `tty`)
- Modify: `Sources/Store/RequestStore.swift` (setter)
- Modify: `Sources/Terminal/TerminalBridge.swift` (accept a known tty)
- Modify: `Sources/Views/ContentView.swift`, `Sources/Views/QuestionOptionsView.swift` (pass the stored tty)

- [ ] **Step 1: Custom request context with remoteAddress**

In `Sources/Server/HookServer.swift`, add at file scope (above `final class HookServer`):

```swift
/// Request context that captures the client's socket address, so hook
/// handlers can resolve which claude process (and tty) sent the request.
struct HookRequestContext: RequestContext, RemoteAddressRequestContext {
    var coreContext: CoreRequestContextStorage
    let remoteAddress: SocketAddress?

    init(source: ApplicationRequestContextSource) {
        self.coreContext = .init(source: source)
        self.remoteAddress = source.channel.remoteAddress
    }
}
```

Change the router instantiation in `start()` from `let router = Router()` to:

```swift
        let router = Router(context: HookRequestContext.self)
```

(The route closures keep their `request, context` signatures; `context` is now `HookRequestContext`.)

- [ ] **Step 2: Resolve tty from the connection's peer port**

Add to `HookServer` (near the other static helpers):

```swift
    /// Resolve the controlling tty of the claude process behind a hook
    /// request: peer port → lsof (both endpoints of the localhost
    /// connection) → the PID that isn't ours → ps tty.
    static func resolveTty(fromPeerPort port: Int) -> String? {
        let myPid = ProcessInfo.processInfo.processIdentifier
        guard let out = Self.shell("lsof -nP -iTCP:\(port) -sTCP:ESTABLISHED -Fp 2>/dev/null") else { return nil }
        let pids = out.split(separator: "\n")
            .filter { $0.hasPrefix("p") }
            .compactMap { Int($0.dropFirst()) }
            .filter { $0 != Int(myPid) }
        guard let pid = pids.first else { return nil }
        guard let ttyRaw = Self.shell("ps -o tty= -p \(pid)"),
              !ttyRaw.isEmpty, ttyRaw != "??" else { return nil }
        return "/dev/" + ttyRaw
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
```

- [ ] **Step 3: Capture the tty once per session on hook arrival**

Add this helper to `HookServer`:

```swift
    /// Capture the session's tty from the connection once (sessions keep the
    /// same controlling terminal for their lifetime). Runs the lsof/ps work
    /// off the main actor; stores the result via RequestStore.
    func captureTtyIfNeeded(sessionId: String, context: HookRequestContext) {
        guard let port = context.remoteAddress?.port else { return }
        let store = self.store
        Task.detached(priority: .utility) {
            let alreadyKnown = await MainActor.run { store.sessions[sessionId]?.tty != nil }
            guard !alreadyKnown else { return }
            guard let tty = Self.resolveTty(fromPeerPort: port) else { return }
            await MainActor.run { store.setSessionTty(id: sessionId, tty: tty) }
        }
    }
```

Call it as the first statement after `decodeInput` in the THREE routes whose sessions matter for replies — `/hooks/permission-request` (after `input` is decoded), `/hooks/stop`, and `/hooks/pre-tool-use`:

```swift
            self.captureTtyIfNeeded(sessionId: input.sessionId, context: context)
```

(In `/hooks/permission-request` the handler closure must capture `self` — change `let store = self.store` usage accordingly if the closure list requires it; the route closures already capture `store`, adding `self` is fine since `HookServer` is `Sendable`.)

- [ ] **Step 4: Store the tty**

In `Sources/Models/SessionInfo.swift`, add after `var lastPrompt: String?`:

```swift
    /// Controlling terminal of the claude process (e.g. /dev/ttys003),
    /// resolved from the hook connection. Used for exact tab targeting.
    var tty: String?
```

In `Sources/Store/RequestStore.swift`, add after `renameSession(id:name:)`:

```swift
    func setSessionTty(id: String, tty: String) {
        sessions[id]?.tty = tty
    }
```

- [ ] **Step 5: Let TerminalBridge use the known tty**

In `Sources/Terminal/TerminalBridge.swift`:

`sendText` signature becomes:

```swift
    static func sendText(_ text: String, toCwd cwd: String, transcriptPath: String = "", knownTty: String? = nil) {
        logToFile("sendText: \"\(text)\" → cwd: \(cwd), transcript: \(transcriptPath), knownTty: \(knownTty ?? "nil")")
        let resolvedTty = knownTty ?? resolveTty(fromTranscriptPath: transcriptPath)
```

(the rest of the body unchanged — it already threads `resolvedTty` through).

`sendTextTwoStep` becomes:

```swift
    static func sendTextTwoStep(_ first: String, then second: String, toCwd cwd: String, transcriptPath: String = "", knownTty: String? = nil) {
        logToFile("sendTextTwoStep: first=\"\(first)\", then=\"\(second)\" → cwd: \(cwd)")
        sendText(first, toCwd: cwd, transcriptPath: transcriptPath, knownTty: knownTty)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            sendText(second, toCwd: cwd, transcriptPath: transcriptPath, knownTty: knownTty)
        }
    }
```

`focusTerminalTab` becomes:

```swift
    static func focusTerminalTab(forCwd cwd: String, transcriptPath: String = "", knownTty: String? = nil) {
        let resolvedTty = knownTty ?? resolveTty(fromTranscriptPath: transcriptPath)
```

(rest unchanged).

- [ ] **Step 6: Pass the stored tty at the reply/focus call sites**

In `Sources/Views/ContentView.swift`:

`sendReply` becomes:

```swift
    private func sendReply(_ text: String, for notification: NotificationEntry) {
        if !store.answerStopHold(sessionId: notification.sessionId, text: text) {
            TerminalBridge.sendText(
                text,
                toCwd: notification.cwd,
                transcriptPath: notification.transcriptPath,
                knownTty: store.sessions[notification.sessionId]?.tty
            )
        }
        store.removeNotification(id: notification.id)
        selectedItem = nil
    }
```

The two focus call sites inside `notificationDetail` (OpenInTerminalButton and TextInputView's onOpenTerminal) become:

```swift
TerminalBridge.focusTerminalTab(forCwd: notification.cwd, transcriptPath: notification.transcriptPath, knownTty: store.sessions[notification.sessionId]?.tty)
```

In `Sources/Views/QuestionOptionsView.swift`: add after `hasDirectChannel`:

```swift
    /// Exact tty of the session's terminal, when known (used by the
    /// legacy two-step terminal-paste path).
    var knownTty: String? = nil
```

and in `sendFreeText`, the two-step call becomes:

```swift
            TerminalBridge.sendTextTwoStep(option.token ?? "\(option.index)", then: text, toCwd: cwd, transcriptPath: transcriptPath, knownTty: knownTty)
```

In `Sources/Views/ContentView.swift`, the `QuestionOptionsView` call gains (after `hasDirectChannel:` and before `cwd:`):

```swift
                            knownTty: store.sessions[notification.sessionId]?.tty,
```

- [ ] **Step 7: Build** — `swift build`, expect `Build complete!`

- [ ] **Step 8: Smoke-test tty capture**

```bash
swift build -c release
cp .build/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
codesign --force --deep --sign - ClaudeBell.app
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app; sleep 2
# Simulate a hook from THIS terminal (curl's tty stands in for claude's):
curl -s -X POST http://localhost:19485/hooks/pre-tool-use \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"tty-smoke\",\"cwd\":\"/tmp\"}"
sleep 1
grep "tty" /tmp/claudebell.log | tail -2 || echo "check app stdout for setSessionTty"
tty   # compare: the captured tty should match this terminal's tty
```

Expected: the captured tty equals this terminal's `tty` output (curl runs on the same controlling terminal).

- [ ] **Step 9: Commit**

```bash
git add Sources/Server/HookServer.swift Sources/Models/SessionInfo.swift Sources/Store/RequestStore.swift Sources/Terminal/TerminalBridge.swift Sources/Views/ContentView.swift Sources/Views/QuestionOptionsView.swift
git commit -m "Capture session tty from hook connection for exact tab targeting"
```

---

## Out of scope

- Replying to idle sessions with no held hook (no Claude Code API exists).
- Unit tests via `swift test` (no XCTest/Swift Testing in this CLT-only environment — verification is build + curl smoke tests + E2E above).
