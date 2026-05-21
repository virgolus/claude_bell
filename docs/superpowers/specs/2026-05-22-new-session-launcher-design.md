# New Session Launcher — Design

## Goal

Let the user start a fresh Claude Code session on an arbitrary directory directly from ClaudeBell. The app opens (or reuses) a terminal, opens a new tab, `cd`s to the chosen directory, and runs `claude` — optionally with an initial prompt entered in the panel.

## User flows

### Flow 1 — explicit "+ New Session"

1. User clicks `+` button in the sidebar header.
2. Detail panel switches to `NewSessionView` (inline form, no modal).
3. User clicks `Choose Directory…` → `NSOpenPanel` (directories only, no multi-select).
4. User optionally types a prompt in the textarea.
5. User clicks `Open Session`.
6. Form closes (selection reverts to last live session, or empty if none); a new terminal tab appears with `claude` running.

### Flow 2 — Recent Projects shortcut

1. User right-clicks the menu bar icon.
2. Submenu `Recent Projects ▸` lists up to 10 entries, each labeled with the directory basename and a path tooltip.
3. Click → terminal tab opens immediately with `claude` (no initial prompt, no form).

## Components

### `Sources/Views/NewSessionView.swift` — new

Inline form rendered by `ContentView.detailPanel` when `selectedItem == .newSession`.

State:
- `selectedDirectory: URL?` — set by the open panel
- `initialPrompt: String` — bound to the textarea
- `recentProjects` — observed from `RecentProjectsStore.shared` (optional small list inside the form for one-click recent selection; nice-to-have, not required for v1)

Actions:
- `Choose Directory…` → presents `NSOpenPanel(canChooseDirectories: true, canChooseFiles: false, allowsMultipleSelection: false)`
- `Cancel` → `selectedItem = nil` (auto-select fallback already exists)
- `Open Session` → calls `TerminalBridge.openNewSession(cwd:initialPrompt:)`, then `RecentProjectsStore.shared.recordUsage(...)`, then `selectedItem = nil`. Disabled when `selectedDirectory == nil`.

### `Sources/Store/RecentProjectsStore.swift` — new

```swift
@MainActor
final class RecentProjectsStore: ObservableObject {
    static let shared = RecentProjectsStore()
    struct Entry: Identifiable, Codable { let cwd: String; let lastUsed: Date; var id: String { cwd } }
    @Published private(set) var entries: [Entry] = []

    func recordUsage(_ cwd: String) { /* dedupe by cwd, prepend, cap at 10, persist */ }
}
```

- Persistence: JSON-encoded array under `AppDefaults` key `recentProjects`.
- Max length: 10. Insertion strategy: remove existing entry with same `cwd`, prepend new one with `lastUsed = .now`, truncate.
- Loaded once on init.

### `TerminalBridge.openNewSession(cwd:initialPrompt:)` — new

Signature: `static func openNewSession(cwd: String, initialPrompt: String)`

Resolution order for target terminal:
1. `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`
   - `com.apple.Terminal` → Terminal.app branch
   - `com.googlecode.iterm2` → iTerm2 branch
2. Otherwise scan `NSWorkspace.shared.runningApplications` for the same bundle IDs and pick the first match.
3. Otherwise default to Terminal.app.

(Warp is intentionally not a target. Even though `sendWarpPaste` uses keystroke automation today, spawning a brand new tab + typing a command via System Events is too fragile to ship. If Warp is frontmost we fall back to Terminal.app and silently activate it.)

Command construction:
- Single-quote-wrap both the cwd and the prompt. Escape inner `'` as `'\''`.
- Empty prompt: `cd 'DIR' && claude`
- Non-empty prompt: `cd 'DIR' && claude 'PROMPT'`

AppleScript per terminal:
- **Terminal.app**: `tell application "Terminal"` → `activate` → `do script "<command>"`. `do script` opens a new window if no window is open, or a new tab in the current window depending on user prefs. That's acceptable.
- **iTerm2**: `tell application "iTerm2"` → if a current window exists, `tell current window` create new tab + write text; else create new window + write text.

### `Sources/Views/ContentView.swift` — modify

Add `case newSession` to `SelectedItem` (or whichever enum drives detail panel routing). Add the corresponding branch to `detailPanel` switch returning `NewSessionView()`.

Add an "Auto-select" guard: when the form closes, fall back to the most recent live notification/request as today.

### `Sources/Views/HeaderView.swift` — modify

`HeaderView` is the top bar (above the sidebar list and the empty-state view in `ContentView`). Add a trailing `+` button using SF Symbol `plus.circle` (or `plus.square.on.square` if a "new session" symbol reads better) that sets `selectedItem = .newSession`. The button is always visible — including in the empty state — so the feature is reachable on a fresh install with no sessions.

### `Sources/App/ClaudeBellApp.swift` — modify

In `showContextMenu(near:)`, after the existing items, insert a `Recent Projects` `NSMenu` populated from `RecentProjectsStore.shared.entries`. Hide the submenu entirely when the list is empty. Each `NSMenuItem`:
- `title`: `(URL(fileURLWithPath: cwd)).lastPathComponent`
- `toolTip`: full `cwd`
- `action`: a selector that calls `TerminalBridge.openNewSession(cwd: cwd, initialPrompt: "")` and records usage.

### `Sources/Store/RequestStore.swift` — modify

`trackSession(id:cwd:lastPrompt:)` is the single insertion point. Inside its `else` branch (new session created), call `RecentProjectsStore.shared.recordUsage(cwd)` so any session observed via hooks also feeds the recents list passively. Skip the call on the existing-session branch — only first-sighting counts as a new project usage to avoid bumping the entry on every hook event.

## Data flow

```
+--------------+        +-----------------+        +----------------------+
| Sidebar "+"  | --set--> selectedItem    | --renders--> NewSessionView   |
+--------------+        +-----------------+        +----------+-----------+
                                                              |
                       +------------------------+             | Open Session
RecentProjectsStore <--+ recordUsage(cwd)       |<------------+
       ^                +------------------------+             |
       |                                                       v
       |                                              TerminalBridge
       |                                              .openNewSession(...)
       |                                                       |
hooks  +------- recordUsage(cwd) from session detection        v
                                                       AppleScript → tab
```

## Error handling

- **NSOpenPanel cancelled** → no state change, form stays open.
- **AppleScript failure** (terminal app not running and Terminal.app launch denied, etc.) → log to `/tmp/claudebell.log` via existing `logToFile`; the form already closed by then. No in-app alert: matches existing UX where AppleScript errors are silent.
- **Directory removed since added to Recent Projects** → `cd` will fail in the new tab, user sees the shell error. We do NOT validate up-front; that would race anyway.
- **Empty cwd** (shouldn't happen since `NSOpenPanel` guarantees a URL) → guard in `openNewSession`: return early if empty.

## Testing

- `RecentProjectsStore`: unit tests for `recordUsage` (dedupe, ordering, cap at 10, persistence round-trip).
- Prompt escaping: unit test that converts `it's a "test"` into `'it'\''s a "test"'` correctly.
- TerminalBridge AppleScript: manual smoke test for each branch (Terminal.app frontmost, iTerm2 frontmost, nothing running).

## Out of scope (deferred)

- Configurable launch command (e.g. `claude --model opus`) — would be a Settings field added later.
- Warp support — needs keystroke automation, not worth shipping in v1.
- Pinning recent projects — current spec is auto-only.
- Showing recent projects inside `NewSessionView` for one-click selection — easy follow-up.

## Files touched

| File | Type | Change |
|------|------|--------|
| `Sources/Views/NewSessionView.swift` | new | Form view |
| `Sources/Store/RecentProjectsStore.swift` | new | Persistent recents |
| `Sources/Terminal/TerminalBridge.swift` | modify | Add `openNewSession` + 2 AppleScript helpers |
| `Sources/Views/ContentView.swift` | modify | New `SelectedItem` case + detail panel branch |
| Sidebar header view | modify | Add `+` button |
| `Sources/App/ClaudeBellApp.swift` | modify | Add `Recent Projects ▸` submenu |
| `Sources/Store/RequestStore.swift` | modify | Hook `recordUsage` into session detection |
