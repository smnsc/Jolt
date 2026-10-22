# Jolt agent guide

Jolt is a native, read-only Jira Cloud issue searcher for macOS. It is a Swift Package with a reusable core target, a SwiftUI/AppKit application target, and a small Swift Testing suite.

## Start here

1. Read [README.md](README.md) for the product behavior and user-facing search syntax.
2. Read [dev-docs/ARCHITECTURE.md](dev-docs/ARCHITECTURE.md) before changing application state, Jira access, authentication, caching, or UI flow.
3. Read [dev-docs/SEARCH.md](dev-docs/SEARCH.md) before changing search editing, parsing, autocomplete, or JQL generation.
4. Use [dev-docs/DEVELOPMENT.md](dev-docs/DEVELOPMENT.md) for build, test, and release commands.

## Build reporting (mandatory)

- `Resources/Info.plist` is the source-controlled authority for version and build number. Increment `CFBundleVersion` when preparing a new app build for testing or distribution; rebuilding the same source preserves its number. `scripts/macos/build-app.sh` prints it on its final line.
- After performing a new app build, always include the exact build number in the user-facing completion report so the user can confirm that the running app is current. Use the form **`Jolt build N`**. Do not report a build as complete without its number.
- If the build script's final line is unavailable, read `CFBundleVersion` from `build/Jolt.app/Contents/Info.plist` and report that value.

## Repository map

- `Sources/JoltCore/`: platform-light domain models, search parsing, JQL generation, and the Keychain abstraction.
- `Sources/JoltApp/`: app lifecycle, SwiftUI/AppKit UI, state coordination, Jira networking, authentication, preferences, and caches.
- `Tests/JoltCoreTests/`: parser and JQL behavior tests using Swift Testing.
- `Resources/`: app metadata, entitlements, and icon assets.
- `scripts/`: top-level `build.py`, `test.sh`, and `release.sh` commands; supporting tools live in `macos/`, `release/`, `website/`, `shared/`, and `tests/`.

## Working rules

- Keep Jira access read-only. Do not add issue mutation endpoints without an explicit product decision.
- Never log, persist in `UserDefaults`, or place in fixtures an email address, API token, or Authorization header. Credentials belong in macOS Keychain through `CredentialStoring`.
- Preserve actor boundaries. `AppModel` and UI-facing repositories are main-actor isolated; authentication, Jira networking, metadata, and disk cache services are actors.
- Keep the editor input as one plain string. Raw `@` (project), `#` (issue type), `~` (assignee), and `>` (reporter) shortcuts must resolve against Jira metadata before JQL reaches the network, without becoming styled editor objects.
- Keep `JoltCore` free of SwiftUI and app lifecycle concerns. Put deterministic parser/JQL behavior there and cover it with tests.
- Cancel or supersede stale asynchronous searches and autocomplete requests when input, site, or connection state changes.
- Keep this guide and the files in `dev-docs/` short and current when changing the behaviors they describe.

## Definition of done

- Run `swift test` for core behavior changes.
- Add or update parser/JQL tests when search semantics change.
- For UI, Keychain, hot-key, login-item, signing, or sandbox changes, also run the app from Xcode or build it with `scripts/macos/build-app.sh`; these paths are not covered by the core test suite. If you build the app, report its build number as required above.
- Use `scripts/build.py [X.Y.Z | --build-only]` for a tested new numbered local build. It prompts when no argument is supplied, increments the tracked build number, and creates missing versioned release notes for a supplied new version. If notes already exist, interactive builds offer to regenerate them from scratch; default to preserving them and replace manual edits only after explicit confirmation. `scripts/macos/build-app.sh` rebuilds the same identity.
- `scripts/release.sh` takes no arguments; both it and the GitHub Release workflow read version/build from remote `main`’s committed `Resources/Info.plist`. Warn and confirm for dirty files, unpushed commits, or HEAD differing from remote `main`; confirmation must explain that local changes are excluded.
- Release preparation uses existing `dev-docs/releases/X.Y.Z.md` notes or generates them from commit history if absent. Do not require manually creating the file; preserve reviewed notes. An optional notes-file argument supports custom local notes.
- Do not commit generated `.build/`, `build/`, `.app`, `.dmg`, or user-specific Xcode files.
