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
# 1. Build release
swift build -c release

# 2. Copia il binario nel bundle app
cp .build/arm64-apple-macosx/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell

# 3. Crea lo zip per il download
rm -f public/ClaudeBell.zip
zip -r public/ClaudeBell.zip ClaudeBell.app -x "*.DS_Store"

# 4. Riavvia l'app
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app
```

## Deploy su Vercel

Il sito serve la cartella `public/` che contiene `ClaudeBell.zip` come download.

```bash
# Commit, push e deploy
git add public/ClaudeBell.zip
git commit -m "Update ClaudeBell.zip"
git push
vercel --prod
```

## Flusso completo (build release + deploy)

```bash
swift build -c release
cp .build/arm64-apple-macosx/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
rm -f public/ClaudeBell.zip
zip -r public/ClaudeBell.zip ClaudeBell.app -x "*.DS_Store"
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app
git add public/ClaudeBell.zip
git commit -m "Update ClaudeBell.zip"
git push
vercel --prod
```

## Note

- Il binario in `ClaudeBell.app/Contents/MacOS/` è in `.gitignore` — solo lo zip in `public/` viene tracciato
- `swift build` senza `-c release` crea una debug build (piu grande, con simboli di debug)
- Il server HTTP gira su `localhost:19485`
