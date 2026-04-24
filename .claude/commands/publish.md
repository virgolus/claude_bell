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

Copy the release binary and the changelog directly into the app bundle. The changelog lives at `Contents/Resources/changelog.json` (flat, NOT inside an SPM-style sub-bundle) — `Sources/Views/ContentView.swift` loads it via `Bundle.main.url(forResource:withExtension:)`.

Also clean up any leftover SPM sub-bundle from older builds, since `swift build` may still emit `.build/.../ClaudeBell_ClaudeBell.bundle/` even though the target no longer declares resources.

```bash
cp .build/arm64-apple-macosx/release/ClaudeBell ClaudeBell.app/Contents/MacOS/ClaudeBell
rm -rf ClaudeBell.app/ClaudeBell_ClaudeBell.bundle ClaudeBell.app/Contents/Resources/ClaudeBell_ClaudeBell.bundle
cp public/changelog.json ClaudeBell.app/Contents/Resources/changelog.json
```

## 6. Re-sign the bundle (ad-hoc)

`swift build` only signs the binary (linker ad-hoc). The surrounding `.app` has no `CodeResources` file, which makes the whole bundle fail `codesign --verify` — and a quarantined download gets rejected as "damaged". Re-sign the full bundle ad-hoc so `CodeResources` is generated and the seal matches the binary:

```bash
codesign --force --deep --sign - ClaudeBell.app
codesign --verify --deep --strict ClaudeBell.app
```

The second command MUST exit 0. If it doesn't, stop and investigate — shipping a zip that fails verification means every user sees "damaged".

(Ad-hoc means `spctl -a` will still reject the app — that's expected for an unsigned app and produces the normal "unidentified developer" dialog with an "Open Anyway" option. Getting past that requires a Developer ID certificate + notarization, which this skill does not do.)

## 7. Create the distribution zip

Remove the old zip and create a new one from the updated app bundle. Use `ditto` (not `zip`) so extended attributes and the signature envelope are preserved correctly when Safari downloads and macOS extracts it:

```bash
rm -f public/ClaudeBell.zip
ditto -c -k --keepParent ClaudeBell.app public/ClaudeBell.zip
```

## 8. Install and restart the app

Copy the build to Applications, kill the running instance, and relaunch:

```bash
rm -rf /Applications/ClaudeBell.app && cp -R ClaudeBell.app /Applications/ClaudeBell.app
pkill -x ClaudeBell; sleep 1; open /Applications/ClaudeBell.app
```

## 9. Commit, push and deploy

The release zip (`public/ClaudeBell.zip`) is **not** tracked by git — it lives only on your local filesystem and is uploaded to Vercel at deploy time. Stage source changes only:

```bash
git add Sources/App/AppVersion.swift public/changelog.json public/index.html
```

Then commit with a descriptive message, push to origin, and deploy:

```bash
git commit -m "Release v<version> (build <build>): <highlights>"
git push
vercel --prod
```

`vercel --prod` uploads everything currently in `public/` (including the freshly-built `ClaudeBell.zip`), so the download on claude-bell.com always serves the matching binary without committing it to git.

## Important notes

- Always build with `-c release` for distribution — debug builds are larger and slower
- The Vercel site serves the `public/` folder as a static site; `ClaudeBell.zip` is the download link
- `public/ClaudeBell.zip` is gitignored — it is built locally and shipped to Vercel, never committed
- The binary inside `ClaudeBell.app/Contents/MacOS/` is also gitignored
- Verify the build succeeds before creating the zip
- Always increment the build number in `Sources/App/AppVersion.swift` before building
- **Never skip the changelog step** — it feeds both the website and the in-app "What's New" panel
