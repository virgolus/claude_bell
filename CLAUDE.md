# CLAUDE.md

## Project overview

ClaudeBell is a macOS menu bar app (SwiftUI + Hummingbird) that receives Claude Code hook events via a local HTTP server on port 19485 and presents them in a native panel UI.

## Build & run

```bash
swift build                # debug build
swift build -c release     # release build
open ClaudeBell.app        # run the app (uses binary in Contents/MacOS/)
```

See [BUILDING.md](BUILDING.md) for the build workflow.

## Architecture

- **RequestStore** (`Sources/Store/RequestStore.swift`) — single source of truth for all state. All mutations happen on `@MainActor`.
- **HookServer** (`Sources/Server/HookServer.swift`) — Hummingbird HTTP server. Routes map 1:1 to Claude Code hook types. Decodes `HookInput`, creates model objects, dispatches to `RequestStore`.
- **Notification lifecycle**: interactive notifications (permission_prompt, idle_prompt, elicitation_dialog) stay in the panel until answered or dismissed. Passive notifications (stop, tool_error, session_end) only appear as bell badge updates and clear stale interactive notifications.
- **Session tracking**: sessions are created on first hook event and removed on `SessionEnd` hook or manual dismissal.
- **UpdateChecker** (`Sources/Update/UpdateChecker.swift`) — checks for new versions via changelog.json and handles in-app download + install.

## Key conventions

- All UI state is in `RequestStore.shared` — views observe `@Published` properties
- Hook endpoints follow the pattern: decode input → dispatch to `@MainActor` store method → return HTTP response
- `NotificationMeta` centralizes all per-type metadata (icon, color, passive/interactive, deduplication)
- `HookInstaller`, `AutoModeInstaller`, and `StatuslineInstaller` in `Sources/Setup/` manage writing/removing hooks, auto-mode config, and statusline script respectively
- The app bundle `ClaudeBell.app` in the repo root has its binary in `.gitignore`; `public/ClaudeBell.zip` is also gitignored and ships to Vercel via the CLI deploy, never via git

## Hooks configuration

Hooks are installed in `~/.claude/settings.json` by `HookInstaller.install()`. All hooks point to `http://localhost:19485/hooks/{endpoint}`. The full list: PermissionRequest, Notification, PreToolUse, PostToolUseFailure, Stop, SessionEnd.

## Testing changes

After modifying Swift code:
1. `swift build` to verify compilation
2. `pkill -x ClaudeBell; sleep 1; open ClaudeBell.app` to restart
3. Trigger a hook from another Claude Code session to test

## Logs

```bash
log stream --process ClaudeBell --level debug
```

**Note:** After rebuilding, macOS may invalidate Accessibility permissions (the binary signature changes). If `TerminalBridge` stops working (AppleScript error 1002), go to **System Settings → Privacy & Security → Accessibility**, remove ClaudeBell, and re-add `ClaudeBell.app`.

## Deploy

The Vercel site serves `public/` as a static landing page with `ClaudeBell.zip` as the download. **The zip is NOT committed to git** — it is gitignored and uploaded to Vercel at deploy time (`vercel --prod` ships the local `public/` directory, binary included).

Use the `/publish` command for the full release flow. Two things are critical and non-obvious:

1. **Changelog lives at `Contents/Resources/changelog.json`** (flat, not inside an SPM sub-bundle). The target is declared `exclude: ["Resources"]` in `Package.swift` so SwiftPM does NOT generate a `ClaudeBell_ClaudeBell.bundle/`. `ContentView.loadChangelog` reads the file via `Bundle.main.url(forResource:withExtension:)`. Do not reintroduce `resources: [.copy(...)]` — the generated `Bundle.module` accessor only searches `Bundle.main.bundleURL/ClaudeBell_ClaudeBell.bundle` (the `.app` root, which is unsealable), with a hard-coded dev fallback path that only exists on the original build machine, so on any other Mac `Bundle.module` fatalErrors on first access.
2. **Re-sign after updating the binary**: `swift build` only signs the binary ad-hoc (linker-signed). The surrounding `.app` has no `CodeResources`, so quarantined downloads get rejected as "damaged and can't be opened". Always run `codesign --force --deep --sign - ClaudeBell.app` after copying the binary, then verify with `codesign --verify --deep --strict ClaudeBell.app` (must exit 0). Use `ditto -c -k --keepParent` instead of `zip` to preserve the signature envelope.
