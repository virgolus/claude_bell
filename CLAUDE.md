# CLAUDE.md

## Project overview

ClaudeBell is a macOS menu bar app (SwiftUI + Hummingbird) that receives Claude Code hook events via a local HTTP server on port 19485 and presents them in a native panel UI.

## Build & run

```bash
swift build                # debug build
swift build -c release     # release build
open ClaudeBell.app        # run the app (uses binary in Contents/MacOS/)
```

See [BUILDING.md](BUILDING.md) for the full release + deploy workflow.

## Architecture

- **RequestStore** (`Sources/Store/RequestStore.swift`) — single source of truth for all state. All mutations happen on `@MainActor`.
- **HookServer** (`Sources/Server/HookServer.swift`) — Hummingbird HTTP server. Routes map 1:1 to Claude Code hook types. Decodes `HookInput`, creates model objects, dispatches to `RequestStore`.
- **Notification lifecycle**: interactive notifications (permission_prompt, idle_prompt, elicitation_dialog) stay in the panel until answered or dismissed. Passive notifications (stop, tool_error, session_end) only appear as bell badge updates and clear stale interactive notifications.
- **Session tracking**: sessions are created on first hook event and removed on `SessionEnd` hook or manual dismissal.

## Key conventions

- All UI state is in `RequestStore.shared` — views observe `@Published` properties
- Hook endpoints follow the pattern: decode input → dispatch to `@MainActor` store method → return HTTP response
- `NotificationMeta` centralizes all per-type metadata (icon, color, passive/interactive, deduplication)
- `HookInstaller` manages writing/removing hooks from `~/.claude/settings.json`
- The app bundle `ClaudeBell.app` in the repo root has its binary in `.gitignore` — only `public/ClaudeBell.zip` is tracked

## Hooks configuration

Hooks are installed in `~/.claude/settings.json` by `HookInstaller.install()`. All hooks point to `http://localhost:19485/hooks/{endpoint}`. The full list: PermissionRequest, Notification, PreToolUse, PostToolUseFailure, Stop, SessionEnd.

## Testing changes

After modifying Swift code:
1. `swift build` to verify compilation
2. `pkill -x ClaudeBell; sleep 1; open ClaudeBell.app` to restart
3. Trigger a hook from another Claude Code session to test

## Deploy

The Vercel site serves `public/` as a static landing page with `ClaudeBell.zip` as the download. After a release build, update the zip and deploy:
```bash
swift build -c release
cp .build/arm64-apple-macosx/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
rm -rf ClaudeBell.app/ClaudeBell_ClaudeBell.bundle && mkdir -p ClaudeBell.app/ClaudeBell_ClaudeBell.bundle
cp public/changelog.json ClaudeBell.app/ClaudeBell_ClaudeBell.bundle/changelog.json
rm -f public/ClaudeBell.zip && zip -r public/ClaudeBell.zip ClaudeBell.app -x "*.DS_Store"
git add Sources/App/AppVersion.swift public/changelog.json public/ClaudeBell.zip
git commit -m "Release v<version> (build <build>): <highlights>"
git push
vercel --prod
```
