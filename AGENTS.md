# Jolt agent guide

Jolt is a native, read-only Jira Cloud issue searcher for macOS. It is a Swift Package with a reusable core target, a SwiftUI/AppKit application target, and a small Swift Testing suite.

## Start here

1. Read [README.md](README.md) for the product behavior and user-facing search syntax.
2. Read [agents/ARCHITECTURE.md](agents/ARCHITECTURE.md) before changing application state, Jira access, authentication, caching, or UI flow.
3. Read [agents/SEARCH.md](agents/SEARCH.md) before changing search editing, parsing, autocomplete, or JQL generation.
4. Use [agents/DEVELOPMENT.md](agents/DEVELOPMENT.md) for build, test, and release commands.

## Build reporting (mandatory)

- `scripts/build-app.sh` automatically assigns every successful local app build a new build number and prints it on its final line.
- After performing a new app build, always include the exact build number in the user-facing completion report so the user can confirm that the running app is current. Use the form **`Jolt build N`**. Do not report a build as complete without its number.
- If the build script's final line is unavailable, read `CFBundleVersion` from `build/Jolt.app/Contents/Info.plist` and report that value.

## Repository map

- `Sources/JoltCore/`: platform-light domain models, search parsing, JQL generation, and the Keychain abstraction.
- `Sources/JoltApp/`: app lifecycle, SwiftUI/AppKit UI, state coordination, Jira networking, authentication, preferences, and caches.
- `Tests/JoltCoreTests/`: parser and JQL behavior tests using Swift Testing.
- `Resources/`: app metadata, entitlements, and icon assets.
- `scripts/`: direct-download app build, icon generation, and DMG packaging.

## Working rules

- Keep Jira access read-only. Do not add issue mutation endpoints without an explicit product decision.
- Never log, persist in `UserDefaults`, or place in fixtures an email address, API token, or Authorization header. Credentials belong in macOS Keychain through `CredentialStoring`.
- Preserve actor boundaries. `AppModel` and UI-facing repositories are main-actor isolated; authentication, Jira networking, metadata, and disk cache services are actors.
- Keep the editor input as one plain string. Raw `@` (project), `#` (issue type), `~` (assignee), and `>` (reporter) shortcuts must resolve against Jira metadata before JQL reaches the network, without becoming styled editor objects.
- Keep `JoltCore` free of SwiftUI and app lifecycle concerns. Put deterministic parser/JQL behavior there and cover it with tests.
- Cancel or supersede stale asynchronous searches and autocomplete requests when input, site, or connection state changes.
- Keep this guide and the files in `agents/` short and current when changing the behaviors they describe.

## Definition of done

- Run `swift test` for core behavior changes.
- Add or update parser/JQL tests when search semantics change.
- For UI, Keychain, hot-key, login-item, signing, or sandbox changes, also run the app from Xcode or build it with `scripts/build-app.sh`; these paths are not covered by the core test suite. If you build the app, report its build number as required above.
- Do not commit generated `.build/`, `build/`, `.app`, `.dmg`, or user-specific Xcode files.
