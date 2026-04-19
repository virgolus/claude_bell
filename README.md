# Claude Bell

A macOS menu bar app that bridges Claude Code notifications to a native UI. When Claude Code needs your attention (permission requests, questions, task completions), Claude Bell shows them in a panel accessible from the menu bar bell icon.

## Features

- **Permission requests** — approve or deny tool usage directly from the panel
- **Interactive notifications** — respond to questions and elicitation dialogs without switching to the terminal
- **Session tracking** — see all active Claude Code sessions at a glance
- **Conversation context** — view transcript history for each notification
- **Global shortcut** — toggle the panel with a keyboard shortcut
- **Sound alerts** — configurable notification sound when Claude needs attention
- **One-click setup** — installs Claude Code hooks automatically from the app settings

## How it works

Claude Bell runs a local HTTP server on `localhost:19485` that receives events from Claude Code via [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks). The configured hooks are:

| Hook | Purpose |
|------|---------|
| `PermissionRequest` | Tool permission prompts (approve/deny) |
| `Notification` | Questions, idle prompts, elicitation dialogs |
| `PreToolUse` | Clears stale notifications when session advances |
| `PostToolUseFailure` | Tool error notifications |
| `Stop` | Task completion |
| `SessionEnd` | Removes closed sessions from the panel |

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.10+
- Claude Code with hooks support

## Install

Download `ClaudeBell.zip` from the [releases page](https://claude-bell.com), unzip, and move to Applications. On first launch, open Settings in the app and click "Enable Hooks" to configure Claude Code.

## Build

See [BUILDING.md](BUILDING.md) for debug, release, and deploy instructions.

## License

Released under the [MIT License](LICENSE).

## Support the project

If ClaudeBell is useful to you, consider [buying me a coffee](https://buymeacoffee.com/virgolus) ☕. It's entirely optional — the app is and will remain free.

## Project structure

```
Sources/
  App/            — App entry point, global shortcut, AppDelegate
  Models/         — Data models (HookInput, NotificationEntry, PendingRequest, SessionInfo)
  Server/         — HTTP server receiving Claude Code hooks (Hummingbird)
  Resources/      — Bundle resources (changelog.json)
  Setup/          — Hook, auto-mode, and statusline installers
  Store/          — RequestStore (central state management)
  Terminal/       — Terminal tab detection and focus (TerminalBridge)
  Transcript/     — Claude Code transcript parser
  Update/         — Auto-update checker and installer
  Utilities/      — Markdown renderer, formatters, helpers
  Views/          — SwiftUI views (panel, detail views, setup)
public/           — Vercel-served landing page + ClaudeBell.zip download
```
