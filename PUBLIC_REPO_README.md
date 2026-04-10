# ClaudeBell

**A native macOS menu bar app for Claude Code.**
Unifies notifications, permission prompts, and hook events from every Claude Code session into one place — no more switching between terminals.

🌐 **Website:** [claude-bell.com](https://claude-bell.com)
💳 **Buy a license:** **$19 one-time** · [claude-bell.com/buy](https://claude-bell.com/buy)
🆓 **Free 14-day trial:** [start the trial](https://claude-bell.com/trial) — no credit card

![ClaudeBell panel showing a permission request for a Bash command](https://claude-bell.com/app-preview.webp)

---

## Why ClaudeBell?

When you run Claude Code in multiple terminals, it's easy to miss a permission prompt, a clarifying question, or the moment a long task finishes. ClaudeBell sits quietly in your menu bar and rings a bell the instant any of your sessions needs attention — and lets you respond without ever leaving your current window.

Built natively in Swift + SwiftUI. Under 1 MB of UI code, no Electron, no background bloat, no telemetry.

## Features

- 🔔 **Unified notification center** — every Claude Code session, one panel
- ✅ **Interactive permission prompts** — approve or deny tool use directly from the menu bar
- 💬 **Idle prompts & elicitation dialogs** — answer questions without switching to the terminal
- 📋 **Session tracking** — see every active session at a glance
- 📜 **Conversation context** — inspect transcript history for each notification
- ⌨️ **Global shortcut** — toggle the panel with a configurable hotkey
- 🔊 **Sound alerts** — configurable notification sound
- 🚀 **One-click setup** — installs Claude Code hooks automatically
- 🔄 **Auto-update** — checks for new versions and installs them in place
- 📊 **Statusline integration** — token usage per message and session total

## How it works

ClaudeBell runs a local HTTP server on `localhost:19485` that receives events from Claude Code via [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks):

| Hook | Purpose |
|------|---------|
| `PermissionRequest` | Tool permission prompts (approve/deny) |
| `Notification` | Questions, idle prompts, elicitation dialogs |
| `PreToolUse` | Clears stale notifications when session advances |
| `PostToolUseFailure` | Tool error notifications |
| `Stop` | Task completion |
| `SessionEnd` | Removes closed sessions from the panel |

All hook events are processed locally — nothing leaves your machine.

## Pricing

**$19 one-time purchase** — lifetime license, free updates, activate on up to 3 Macs.
No subscription, no account, no data collection.

[**Buy a license →**](https://claude-bell.com/buy)

Or [start a 14-day free trial](https://claude-bell.com/trial). Full features, no credit card required. After the trial, the app continues to work in lite mode (single-session, no statusline, no auto-update) until you activate a license.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (arm64)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with hook support

## Installation

1. [Purchase a license](https://claude-bell.com/buy) or [start the free trial](https://claude-bell.com/trial)
2. Download `ClaudeBell.zip`, unzip, drag `ClaudeBell.app` into `/Applications`
3. Launch the app — the bell icon appears in your menu bar
4. Open **Settings** from the menu and click **Enable Hooks** to wire up Claude Code
5. If you bought a license, paste your license key in **Settings → Account**

The app is signed and notarized by Apple, so it opens cleanly on a fresh Mac.

## Privacy

ClaudeBell runs entirely on your machine. The HTTP server listens on `localhost:19485` and never makes outbound connections except to:
- Validate your license key with Lemon Squeezy (once at activation, then every 7 days)
- Check for updates from `claude-bell.com`

No telemetry, no analytics, no accounts.

## Support

- 🐛 **Bug reports & feature requests:** [open an issue](../../issues)
- 📧 **License & purchase questions:** support@claude-bell.com
- 📰 **Changelog:** [claude-bell.com/#changelog](https://claude-bell.com/#changelog)

This repository hosts the public website, documentation, and issue tracker. The application source code is maintained in a private repository.

## License

Documentation and screenshots in this repository are released under the MIT license.
The ClaudeBell application binary is proprietary and sold under the terms of the [End User License Agreement](https://claude-bell.com/eula).

---

Made by [Ezio Vergine](https://github.com/virgolus) · [claude-bell.com](https://claude-bell.com)
