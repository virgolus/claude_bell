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

## Release (distribuzione)

```bash
# 1. Aggiorna versione in Sources/App/AppVersion.swift (incrementa build)
# 2. Aggiorna public/changelog.json con le modifiche della release
# 3. Build release
swift build -c release

# 4. Copia il binario e il resource bundle nell'app
cp .build/arm64-apple-macosx/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
rm -rf ClaudeBell.app/ClaudeBell_ClaudeBell.bundle && mkdir -p ClaudeBell.app/ClaudeBell_ClaudeBell.bundle
cp public/changelog.json ClaudeBell.app/ClaudeBell_ClaudeBell.bundle/changelog.json

# 5. Crea lo zip per il download
rm -f public/ClaudeBell.zip
zip -r public/ClaudeBell.zip ClaudeBell.app -x "*.DS_Store"

# 6. Riavvia l'app
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app
```

## Deploy su Vercel

Il sito serve la cartella `public/`. Lo zip `public/ClaudeBell.zip` **non è tracciato da git** (è in `.gitignore`): viene costruito in locale e caricato su Vercel al momento del deploy.

```bash
# Commit solo dei sorgenti (NON lo zip)
git add Sources/App/AppVersion.swift public/changelog.json public/index.html
git commit -m "Release v<version> (build <build>): <highlights>"
git push

# Deploy: vercel --prod carica tutto ciò che è in public/ (incluso lo zip appena generato)
vercel --prod
```

## Flusso completo (build release + deploy)

```bash
# 1. Aggiorna Sources/App/AppVersion.swift (incrementa build)
# 2. Aggiorna public/changelog.json con le modifiche della release
swift build -c release
cp .build/arm64-apple-macosx/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
rm -rf ClaudeBell.app/ClaudeBell_ClaudeBell.bundle && mkdir -p ClaudeBell.app/ClaudeBell_ClaudeBell.bundle
cp public/changelog.json ClaudeBell.app/ClaudeBell_ClaudeBell.bundle/changelog.json
rm -f public/ClaudeBell.zip
zip -r public/ClaudeBell.zip ClaudeBell.app -x "*.DS_Store"
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app

# Commit sorgenti (zip escluso) + deploy
git add Sources/App/AppVersion.swift public/changelog.json public/index.html
git commit -m "Release v<version> (build <build>): <highlights>"
git push
vercel --prod
```

## Note

- Il binario in `ClaudeBell.app/Contents/MacOS/` e `public/ClaudeBell.zip` sono in `.gitignore`: esistono solo in locale e vengono caricati su Vercel tramite `vercel --prod`
- `swift build` senza `-c release` crea una debug build (piu grande, con simboli di debug)
- Il server HTTP gira su `localhost:19485`
- **Non saltare mai l'aggiornamento del changelog** — alimenta sia il sito web che il pannello "What's New" nell'app
