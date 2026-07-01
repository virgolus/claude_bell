# Session Tab Marker — Design

**Date:** 2026-07-01
**Status:** Approved pending user review

## Problem

Panel replies are delivered reliably only through a live Stop-hook hold
(`answerStopHold` → `{"decision":"block","reason":…}` on the held HTTP
connection). When no live hold exists — the common case where a terminal was
frontmost when Claude stopped (so `HookServer` intentionally does not hold, see
`HookServer.swift:204-211`), or the hold timed out, or was focus-released — the
reply falls back to `TerminalBridge.sendText`, which must *re-identify* the
session's terminal tab.

That re-identification is inherently fragile. There is no stable, queryable
handle mapping "this Claude Code session" → "this terminal tab". `TerminalBridge`
infers it from three unstable signals:

- **tty** — resolved live from the hook connection's peer port, but macOS
  recycles `ttysNNN` device numbers when tabs close/open, so a persisted tty
  can later point at an unrelated tab. `ttyBelongsToSession` guards this but
  can reject valid ttys (see fix `aff15e3`) or be fooled by a plausible recycle.
- **cwd** — ambiguous: multiple tabs can share a cwd, and the hook cwd is often
  a subdirectory of the shell's launch cwd. Matching is necessarily fuzzy.
- **process name** — AppleScript only exposes `"claude"`/`"node"` in the tab's
  process list, not a session id; the iTerm2 fuzzy pass even matches on the
  session *name* containing `"claude"`, which breaks if the tab is renamed.

The result: the fuzzy fallback fails to find the tab (or hits the wrong one),
and — before the companion silent-failure fix — the typed reply was lost with
no feedback.

## Goal

Give each Claude Code session's terminal tab a **stable, unique marker** written
at a moment when the tty is reliably known, and match replies on that marker.
This makes reply targeting exact and immune to tty recycling, cwd ambiguity, and
tab renames.

## Non-goals

- Replacing the Stop-hook direct-reply channel. The held hook remains the
  primary, deterministic path; this work only hardens the *fallback*.
- Supporting Warp. Warp exposes no per-tab AppleScript handle (no tty, no id,
  no settable title), so it stays best-effort (focused-tab paste).
- Changing the "don't hold when a terminal is frontmost" optimization
  (explicit prior decision).

## Empirically verified facts (Terminal.app, macOS 15.4, 2026-07-01)

Verified with `osascript` against Terminal.app throwaway windows:

1. **`custom title` is readable and already reflects Claude's OSC-set title.**
   Live claude tabs report `custom title` equal to the conversation summary
   Claude sets via OSC (e.g. "Massimizzare refresh rate BabylonJS VR").
2. **An AppleScript-set `custom title` pins and overrides later process OSC
   titles.** After `set custom title of w to "CB-MARKER-12345"`, a shell
   emitting `\033]2;PROCESS-SET-TITLE\007` did **not** change the title.
3. **The pin survives repeated OSC writes.** After 5 successive OSC title
   writes from the process over ~2s, the AppleScript-set custom title
   (`"…  ⟨cb-abc123⟩"`) was unchanged.

iTerm2's stable `id of session` (approach C) is **not yet verified** on a
running iTerm2 (none running at design time); the implementation must verify it
and fall back to a `name` marker if `id` is unusable.

## Approaches considered

- **A — Statusline emits an OSC title with the session id.** Rejected: the
  statusline is optional (`StatuslineInstaller.isInstalled` may be false), and
  the statusline and Claude would both write the OSC title every render
  (last-writer-wins flicker).
- **B — ClaudeBell stamps the marker via AppleScript when the tty is reliable.**
  **Chosen.** Relies only on verified behavior; self-contained; no dependency
  on Claude Code config or on the statusline being installed.
- **C — On iTerm2, capture the stable `id of session` instead of writing the
  title.** Used as an iTerm2-specific optimization of B (no title pollution),
  with a `name`-marker fallback.

## Mechanism

### Marker format

```
⟨cb:<code>⟩
```

where `<code>` is the first 8 hex characters of the Claude `session_id`. 8 hex
chars are enough to avoid collisions among concurrent sessions; the code is
recomputable from `session_id`, so Terminal.app needs no extra persistence. The
delimiters `⟨cb:` / `⟩` are unlikely to appear in a normal title and make the
substring match unambiguous.

If a collision among concurrent live sessions is ever detected, the code length
can be extended — call this out but do not build collision handling now (YAGNI).

### Stamping — `TerminalBridge.stampSessionMarker(sessionId:tty:)`

Given `(sessionId, tty)`, locate the tab/session by **exact tty** (reliable only
at call time, which is why stamping happens during a live hook connection) and:

- **Terminal.app**: read `custom title`; if it already contains `⟨cb:<code>⟩`,
  return (idempotent). Otherwise set
  `custom title = "<currentTitle>  ⟨cb:<code>⟩"` — preserving the summary
  snapshot plus the marker. The snapshot freezes at this point (accepted
  trade-off).
- **iTerm2**: capture `id of session` for that tty and store the mapping
  `session_id → iTermSessionId` (no title change). If `id` proves unusable at
  implementation time, set the session `name` to include `⟨cb:<code>⟩` instead
  (title-pollution fallback, analogous to Terminal.app).
- **Warp**: no-op.

Stamping is best-effort: any AppleScript failure is logged to
`/tmp/claudebell.log` and never blocks the hook.

### When to stamp

In `HookServer`, immediately after `refreshSessionTty` resolves the live tty,
on the **Stop** and **Notification** hooks only:

- Both fire after Claude has done work, so the conversation summary is
  well-formed and the frozen snapshot is meaningful.
- Both are the moments that precede a possible panel reply.
- Both already run `refreshSessionTty` while the hook connection is open.

`refreshSessionTty` currently resolves the tty and stores it but discards the
value locally; it will be adjusted to return the resolved tty (or the stamp
step will read `store.resolvedTty(for:)` right after) so the stamp can target
the exact tab. Stamping runs off the main thread (like the tty resolution) and
is idempotent, so repeated Stops are cheap.

Explicitly **not** stamped on PreToolUse / UserPromptSubmit / PermissionRequest
(either too early for a good summary, or already covered by their own reliable
hook channels).

### Matching at reply time

Add a new highest-priority pass to the existing match scripts, tried **before**
the current Pass 0 (exact tty):

- **Terminal.app** (`terminalMatchScript`): Pass −1 — find the tab where
  `custom title contains "⟨cb:<code>⟩"` → paste/focus.
- **iTerm2** (`sendiTerm2Paste` / `focusiTerm2`): Pass −1 — find the session
  where `id is <storedITermSessionId>` → write/focus (or `name contains marker`
  with the fallback).

If the marker is absent (e.g. stamping never ran, tab was closed and reopened,
Warp), matching falls through to the existing tty → cwd → fuzzy passes. This
makes the feature strictly additive: worst case equals today's behavior.

The store exposes the marker/id to the bridge:
`RequestStore.sessionMarkerCode(for:) -> String` (derives `<code>` from the
session id) and `RequestStore.iTermSessionId(for:) -> String?`.

## Component changes

- **`Sources/Terminal/TerminalBridge.swift`**
  - New `stampSessionMarker(sessionId:tty:)` with per-terminal AppleScript
    (owning-app routed like `sendText`).
  - `terminalMatchScript`: prepend a marker pass (parameterized by the marker
    string; empty → skipped, mirroring the existing `ttyLiteral` handling).
  - `sendiTerm2Paste` / `focusiTerm2`: prepend an `id`/`name` marker pass.
  - `sendText` / `focusTerminalTab` gain an optional `marker` (and iTerm id)
    parameter, threaded from the callers.
- **`Sources/Server/HookServer.swift`**
  - `refreshSessionTty` returns the resolved tty (or add a sibling that does).
  - Stop and Notification handlers call `stampSessionMarker` after tty refresh,
    off-main-thread.
- **`Sources/Store/RequestStore.swift`**
  - `TtyRecord` (and in-memory `SessionInfo`) gain an optional `iTermSessionId`.
  - `sessionMarkerCode(for:)` and `iTermSessionId(for:)` accessors.
  - `removeSession` drops the iTerm mapping (already drops the tty cache).
- **Callers of `sendText`** (`ContentView.sendReply`,
  `QuestionOptionsView`, `ExitPlanModeView`) pass the session marker / iTerm id
  so the new pass is used.

## Error handling

- Stamping failure → logged, hook proceeds normally, matching degrades to the
  existing passes.
- Marker not found at reply time → existing tty/cwd/fuzzy fallback (unchanged).
- Combined with the companion silent-failure fix (`sendText` returns `Bool`,
  panel keeps text + clipboard + warning on failure), a missed match is now
  visible rather than silent.

## Testing

- **AppleScript harness** (like the design-time probes): open a throwaway
  Terminal.app window, stamp a marker, hammer OSC titles, assert the marker
  survives and is matched.
- **Manual, Terminal.app**: two claude sessions in the *same* cwd; trigger Stop
  in one (no hold — terminal frontmost); reply from the panel; assert it lands
  in the correct tab. Repeat after closing/reopening tabs to churn ttys.
- **Manual, iTerm2**: verify `id of session` capture and match; if unusable,
  verify the `name`-marker fallback.
- **Regression**: reply through a live Stop hold still goes direct (marker path
  not exercised); Warp still pastes into the focused tab.

## Open questions / risks

- **iTerm2 `id of session` feasibility** — must be verified during
  implementation; `name`-marker fallback defined above if it fails.
- **Snapshot freeze** — the Terminal.app summary freezes at first stamp;
  accepted.
- **Code collision** — 8 hex chars; extend if ever observed (not handled now).
