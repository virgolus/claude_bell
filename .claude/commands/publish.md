Build a release version of ClaudeBell and deploy it to Vercel. Follow these steps exactly:

## 1. Increment version

Read `Sources/App/AppVersion.swift` and increment the `build` number by 1. If the changes warrant it (new features, breaking changes), also bump the `current` version string. Use the Edit tool to update the file.

## 2. Update download button version

Use the Edit tool to update the download button text in `public/index.html`. Find the line containing `Download v` and `for macOS` and replace it with the new version:
- Replace: `Download v<old-version> for macOS`
- With: `Download v<new-version> for macOS`

## 3. Generate changelog entry (MANDATORY — DO NOT SKIP)

Read `public/changelog.json` to see the latest existing entry and its version/build.

Find commits since the last changelog entry by looking at `git log --oneline`. Identify the commit that matches the last changelog entry's version. Then get all commits since:

```bash
git log --oneline <last-release-hash>..HEAD
```

From these commits, generate a changelog entry. Classify each meaningful change as:
- `new` — new feature or capability
- `changed` — modification to existing behavior
- `fixed` — bug fix
- `removed` — removed feature

Skip merge commits, version bumps, and trivial changes (typos, formatting). Combine related commits into a single entry. Write user-facing descriptions (not git commit messages).

**IMPORTANT**: If the latest entry in `changelog.json` already matches the current version, UPDATE it with new changes rather than adding a duplicate. If it's a new version, PREPEND a new entry at the top of the array.

The entry must have:
- `version`: from AppVersion.swift (after increment)
- `build`: from AppVersion.swift (after increment)
- `date`: today's date (YYYY-MM-DD)
- `highlights`: one-line summary of the release
- `changes`: array of `{type, text}` objects

Use the Edit tool to update the file. Ensure valid JSON.

**VERIFICATION**: After editing, read back `public/changelog.json` and confirm the new entry is present and the JSON is valid.

## 4. Build release binary

```bash
swift build -c release
```

Wait for the build to complete successfully before proceeding.

## 5. Update the app bundle

Copy the release binary and the SPM resource bundle (including the updated changelog.json) into the app bundle:

```bash
cp .build/arm64-apple-macosx/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
rm -rf ClaudeBell.app/ClaudeBell_ClaudeBell.bundle
mkdir -p ClaudeBell.app/ClaudeBell_ClaudeBell.bundle
cp public/changelog.json ClaudeBell.app/ClaudeBell_ClaudeBell.bundle/changelog.json
```

## 6. Create the distribution zip

Remove the old zip and create a new one from the updated app bundle:

```bash
rm -f public/ClaudeBell.zip
zip -r public/ClaudeBell.zip ClaudeBell.app -x "*.DS_Store"
```

## 7. Restart the app

Kill the running instance and relaunch with the new binary:

```bash
pkill -x ClaudeBell; sleep 1; open ClaudeBell.app
```

## 8. Commit and push

Stage ALL changed files — version bump, changelog, index.html, and zip:

```bash
git add Sources/App/AppVersion.swift public/changelog.json public/index.html public/ClaudeBell.zip
```

Then commit with a descriptive message, push to origin, and deploy:

```bash
git commit -m "Release v<version> (build <build>): <highlights>"
git push
vercel --prod
```

## Important notes

- Always build with `-c release` for distribution — debug builds are larger and slower
- The Vercel site serves the `public/` folder as a static site; `ClaudeBell.zip` is the download link
- Only `public/ClaudeBell.zip` is tracked in git — the binary inside `ClaudeBell.app/Contents/MacOS/` is gitignored
- Verify the build succeeds before creating the zip
- Always increment the build number in `Sources/App/AppVersion.swift` before building
- **Never skip the changelog step** — it feeds both the website and the in-app "What's New" panel
