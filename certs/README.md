# Code-signing identity

The release flow (`/publish`) signs `ClaudeBell.app` with the **`ClaudeBell Self-Signed`** code-signing identity (see `CLAUDE.md` → Deploy, and `.claude/commands/publish.md` → step 6). Signing with a *stable* identity is what makes the macOS Accessibility grant survive app updates — ad-hoc signing (`--sign -`) rebinds the code identity on every build and silently breaks the panel-reply paste.

## What lives here (and is gitignored)

- `ClaudeBell-Self-Signed.p12` — the identity **including its private key**, password-protected. This is the backup needed to sign on a fresh machine / after a keychain reset.
- `ClaudeBell Self-Signed.cer` — the public certificate only (not sufficient to sign).

Both are ignored by `.gitignore` (`*.p12`, `*.cer`, `certs/*`). **Never commit them** — the `.p12` contains a private key. A copy also lives in 1Password.

## Restore the identity on a new machine

```bash
security import "certs/ClaudeBell-Self-Signed.p12" -k ~/Library/Keychains/login.keychain-db -P '<p12-password>' -T /usr/bin/codesign
# verify it resolves:
codesign -dvvv ClaudeBell.app 2>&1 | grep Authority=   # → Authority=ClaudeBell Self-Signed
```

## ⚠️ Do NOT regenerate the certificate

macOS binds the Accessibility grant to the certificate's leaf hash
(`identifier "com.virgolus.claudebell" and certificate leaf = H"…"`). Creating a
new cert changes that hash and forces **every user** to re-grant Accessibility
after their next update. Always reuse this exact identity.
