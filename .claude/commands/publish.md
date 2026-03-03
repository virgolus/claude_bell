Build a release version of ClaudeBell and deploy it to Vercel. Follow these steps exactly:

## 1. Build release binary

```bash
swift build -c release
```

Wait for the build to complete successfully before proceeding.

## 2. Update the app bundle

Copy the release binary into the app bundle:

```bash
cp .build/arm64-apple-macosx/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
```

## 3. Create the distribution zip

Remove the old zip and create a new one from the updated app bundle:

```bash
rm -f public/ClaudeBell.zip
zip -r public/ClaudeBell.zip ClaudeBell.app -x "*.DS_Store"
```

## 4. Restart the app

Kill the running instance and relaunch with the new binary:

```bash
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app
```

## 5. Commit and push

Stage the updated zip (the binary in ClaudeBell.app/Contents/MacOS/ is in .gitignore, only the zip is tracked):

```bash
git add public/ClaudeBell.zip
```

Then commit with a message describing what changed, push to origin, and deploy:

```bash
git push
vercel --prod
```

## Important notes

- Always build with `-c release` for distribution — debug builds are larger and slower
- The Vercel site serves the `public/` folder as a static site; `ClaudeBell.zip` is the download link
- Only `public/ClaudeBell.zip` is tracked in git — the binary inside `ClaudeBell.app/Contents/MacOS/` is gitignored
- Verify the build succeeds before creating the zip
