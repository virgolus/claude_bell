# ClaudeBell — Build & Run

Requisiti: macOS 14+, Swift 5.10+

## Debug (sviluppo)

```bash
swift build
open ClaudeBell.app
```

Il binario debug viene creato in `.build/arm64-apple-macosx/debug/ClaudeBell`.
L'app bundle `ClaudeBell.app` nella root usa il binario in `Contents/MacOS/ClaudeBell` — la debug build **non** lo aggiorna automaticamente.

Per testare la debug build senza aggiornare il bundle:

```bash
swift build
.build/arm64-apple-macosx/debug/ClaudeBell
```

## Release (build locale)

```bash
# 1. (opzionale) Aggiorna versione in Sources/App/AppVersion.swift
# 2. Build release
swift build -c release

# 3. Copia il binario e il resource bundle nell'app
cp .build/arm64-apple-macosx/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
rm -rf ClaudeBell.app/ClaudeBell_ClaudeBell.bundle && mkdir -p ClaudeBell.app/ClaudeBell_ClaudeBell.bundle
cp public/changelog.json ClaudeBell.app/ClaudeBell_ClaudeBell.bundle/changelog.json

# 4. Crea lo zip (opzionale, per distribuzione manuale)
zip -r ClaudeBell.zip ClaudeBell.app -x "*.DS_Store"

# 5. Riavvia l'app
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app
```

## Note

- `swift build` senza `-c release` crea una debug build (più grande, con simboli di debug)
- Il binario in `ClaudeBell.app/Contents/MacOS/` è in `.gitignore`: va rigenerato ad ogni release build
- Il server HTTP in-app gira su `localhost:19485`
