Build a release version of ClaudeBell and deploy it to Vercel. Follow these steps exactly:

## 1. Increment version

Read `Sources/App/AppVersion.swift` and increment the `build` number by 1. If the changes warrant it (new features, breaking changes), also bump the `current` version string. Use the Edit tool to update the file.

## 2. Build release binary

```bash
swift build -c release
```

Wait for the build to complete successfully before proceeding.

## 3. Update the app bundle

Copy the release binary and the SPM resource bundle into the app bundle:

```bash
cp .build/arm64-apple-macosx/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
rm -rf ClaudeBell.app/ClaudeBell_ClaudeBell.bundle
mkdir -p ClaudeBell.app/ClaudeBell_ClaudeBell.bundle
cp public/changelog.json ClaudeBell.app/ClaudeBell_ClaudeBell.bundle/changelog.json
```

## 4. Create the distribution zip

Remove the old zip and create a new one from the updated app bundle:

```bash
rm -f public/ClaudeBell.zip
zip -r public/ClaudeBell.zip ClaudeBell.app -x "*.DS_Store"
```

## 5. Restart the app

Kill the running instance and relaunch with the new binary:

```bash
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app
```

## 6. Commit and push

Stage all changed files including the version bump and the updated zip:

```bash
git add Sources/App/AppVersion.swift public/ClaudeBell.zip
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
- Always increment the build number in `Sources/App/AppVersion.swift` before building
