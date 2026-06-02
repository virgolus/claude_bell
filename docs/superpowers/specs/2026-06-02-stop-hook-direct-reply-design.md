# Stop-Hook Direct Reply — Design

**Date:** 2026-06-02
**Status:** Approved pending user review

## Problem

Replies sent from ClaudeBell to text questions (e.g. superpowers' "Due opzioni di esecuzione: 1. Subagent-Driven / 2. Inline") and free-text follow-ups are typed into the terminal via `TerminalBridge` (AppleScript + clipboard paste). Window targeting is unreliable: `resolveTty` fails on every send (Claude Code does not keep the transcript file open, so `lsof -t <transcript>` never finds a PID — confirmed in `/tmp/claudebell.log`), so the fuzzy fallback ("any tab with a claude process") frequently pastes into the wrong window.

Permission requests, `AskUserQuestion`, and `ExitPlanMode` already reply through the `PermissionRequest` hook response (long-poll continuation) and are not affected.

## Goal

Deliver panel replies for text questions and follow-ups through the hook channel — no keystroke injection — whenever a hook is available, with the existing terminal path as fallback for late replies.

## Non-goals

- Improving `TerminalBridge` tty/window targeting (kept as-is for the late-reply fallback).
- Replying to sessions that are idle with no held hook (no external injection API exists in Claude Code; feature requests [#27441](https://github.com/anthropics/claude-code/issues/27441) and [#53049](https://github.com/anthropics/claude-code/issues/53049) closed not-planned).

## Mechanism (empirically verified on Claude Code 2.1.160, 2026-06-02)

A real `claude` TUI session was driven via `expect` with instrumented hooks. Verified facts:

1. **Stop hook hold + block delivers the answer.** A Stop hook held open and then returning `{"decision":"block","reason":"<text>"}` makes Claude continue; the transcript shows the reason injected as `Stop hook feedback: <text>` and Claude acting on it.
2. **The TUI stays usable during a held Stop hook.** Statusline shows `(running stop hooks…)`; typed prompts are queued (`press up to edit queued messages`) and submit when the hook returns. No deadlock.
3. **`UserPromptSubmit` fires only after the hold releases** — a queued prompt does not fire it mid-hold, so it cannot serve as an early-release signal. It does fire reliably on every real submission, making it the right signal for dismissing stale notifications.
4. **Esc kills a running Stop hook instantly** (hook process terminated mid-sleep). For an `http` hook this aborts the connection — a per-session, native early release.
5. **The `timeout` field is honored above the 600 s default**: a hook declaring `timeout: 720` ran for the full 700 s. No hard cap encountered; long holds are configurable. If an undocumented internal cap ever kills a longer hold, the connection drops and ClaudeBell degrades to the fallback path — nothing breaks.

## Flow

```
Claude finishes a turn
  └─ Stop hook → POST /hooks/stop  (settings timeout = hold + 60 s margin)
       ClaudeBell HOLDS the request (withCheckedContinuation, same pattern
       as /hooks/permission-request) and shows the notification
       │
       ├─ panel reply (option click or free text)
       │     → 200 {"decision":"block","reason":"L'utente ha risposto da ClaudeBell: <text>"}
       │     → Claude resumes with the answer. Done.
       ├─ panel dismiss            → 200 {}   (normal stop)
       ├─ hold timer expires       → 200 {}   (normal stop; notification stays;
       │                                       later replies use the terminal fallback)
       ├─ terminal app focused     → 200 {} for ALL held stops (focus-release;
       │                                       notifications stay)
       ├─ Esc pressed in terminal  → connection aborted → ClaudeBell cleans up state
       └─ SessionEnd               → 200 {} + cleanup
```

All stops are held — both question stops (`idle_prompt` classification) and plain completions — so option answers *and* free-text follow-ups travel through the hook while the hold is alive.

Releasing a hold never removes a notification. Notifications are removed only by: a panel reply, an explicit dismiss, `UserPromptSubmit` for that session (user answered in the terminal), or `SessionEnd`.

## Component changes

### `HookInstaller` (`Sources/Setup/HookInstaller.swift`)
- `Stop` hook timeout: `10` → hold duration + 60 s (rewritten when the setting changes).
- New `UserPromptSubmit` hook entry → `http://localhost:19485/hooks/user-prompt-submit`, timeout 10.
- Write `"env": {"CLAUDE_CODE_STOP_HOOK_BLOCK_CAP": "50"}` into `~/.claude/settings.json` (merge, don't clobber existing env). The default cap of 8 consecutive blocks would kill a brainstorming session after 8 panel answers in a row.

### `HookServer` (`Sources/Server/HookServer.swift`)
- `/hooks/stop` becomes a long-poll endpoint: decode input, classify (existing `transcriptHasPendingQuestion` logic still decides `idle_prompt` vs `stop` for display), then suspend on a continuation registered in the store. Resume values: `.block(reason:)` or `.allow` (empty JSON `{}`).
- Handle request cancellation (Esc / Claude exit): release and clean up the pending hold.
- New `/hooks/user-prompt-submit`: `sessionAdvanced(id:)` + remove the session's interactive notifications, return 200.

### `RequestStore` (`Sources/Store/RequestStore.swift`)
- New `PendingStop` registry keyed by `sessionId`: continuation + per-hold `Task`-based timer (hold duration from settings) + creation date.
- Release paths: `answer(text)` → block+reason; `release()` → `{}`; invoked by timer, panel dismiss, focus-release, and `SessionEnd`. (`UserPromptSubmit` cannot fire while that session's hold is alive — verified fact 3 — but the endpoint still calls `release()` defensively before dismissing notifications.)
- A new hold for a session replaces (releases) any stale previous hold for the same session.

### Focus-release (`Sources/App/` — new observer)
- `NSWorkspace.didActivateApplicationNotification` observer; when the frontmost app becomes Terminal/iTerm2/Warp (same bundle-id list as `TerminalBridge.activateTerminal`), release **all** holds with `{}`. Notifications stay.

### Settings UI (`SettingsContainerView` + `AppDefaults`)
- "Risposta diretta" section: hold duration picker — 5 min (default) / 30 min / 4 h / 24 h. Changing it re-runs `HookInstaller.install()` to update the Stop hook timeout.

### Views (`ContentView`, `QuestionOptionsView`, `FollowUpActionView`, `TextInputView`)
- For stop/idle_prompt notifications: if a live `PendingStop` exists for the session, route the reply through it (`onAnswers`-style structured path, mirroring the existing `RequestDetailView` hook path); otherwise use `TerminalBridge` exactly as today.
- Visual indicator on the notification while the hold is alive: a countdown using the existing `formatCountdown` pattern from `RequestDetailView`, so the user knows which channel a reply will use and how long the direct channel stays open.

## Edge cases

- **`stop_hook_active: true`** (stop following our own block): hold again — this is what enables multi-question chains; the raised block cap (50) bounds runaway loops.
- **ClaudeBell quits/restarts mid-hold**: connection drops; Claude Code treats http hook errors as non-blocking → normal stop. Clean degradation.
- **Multiple concurrent sessions**: holds are per `session_id`; focus-release is the only global action and it only downgrades the channel, never discards notifications.
- **Reply typed in terminal during a hold**: queued by Claude Code, processed at release; `UserPromptSubmit` then dismisses the notification. Esc releases immediately for that session.
- **Hold expired, user replies from panel**: falls back to the current `TerminalBridge` path unchanged.

## Testing

- Unit: block/allow JSON serialization; `PendingStop` release logic (answer / dismiss / timer / replace / session-end).
- Manual (per CLAUDE.md workflow): rebuild, restart app, then from a second Claude Code session verify: panel option answer lands as `Stop hook feedback` in the transcript; Esc aborts the hold cleanly; focus-release fires on terminal activation; terminal reply dismisses the notification; timeout falls back to terminal paste; permission/AskUserQuestion flows unchanged.
