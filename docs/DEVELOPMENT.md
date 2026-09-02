# Development

## Prerequisites

- macOS 14 or later.
- Swift 6 toolchain compatible with the package's Swift 5 language mode.
- Full Xcode 16 or later for running the app, asset compilation, universal release builds, signing, and notarization.
- A Jira Cloud account and user-supplied API token for live integration testing.

No developer-owned Jira credentials belong in the repository. The app collects credentials at runtime and stores them in macOS Keychain.

## Fast validation loop

Run the core suite from the repository root:

```sh
swift test
```

If an agent sandbox reports SwiftPM cache permissions, `sandbox-exec`, or a Command Line Tools SDK/compiler mismatch while Xcode is installed, keep all generated state in the ignored `build/` directory and select Xcode explicitly:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/TestModuleCache" \
CLANG_MODULE_CACHE_PATH="$PWD/build/TestModuleCache" \
swift test --disable-sandbox --scratch-path "$PWD/build/TestSwiftPM"
```

Open `Package.swift` in Xcode and run the `Jolt` scheme for application behavior. Useful manual checks after app-layer changes are:

1. Connect with a valid `*.atlassian.net` site, email, and API token.
2. Verify empty search, plain text, each shortcut kind, combined shortcuts, and direct issue keys.
3. Exercise keyboard suggestion selection, copy/paste, Escape, result navigation, and Return-to-open.
4. Hide and reopen the search window with the global shortcut and menu-bar item.
5. Check clear-cache versus logout semantics.
6. Check appearance, Dock visibility, launch at login, and shortcut changes when touched.

Authentication and Jira calls are live integration paths; the automated suite does not mock or exercise them today.

## Direct-download build

Build an ad-hoc signed universal app:

```sh
scripts/build-app.sh
```

The result is `build/Jolt.app`. The script builds arm64 and x86_64, compiles the asset catalog, applies bundle version values, signs, and verifies the app. Each successful local build automatically increments the lightweight counter in `build/.build-number`; the final output reports the version and build number. Settings displays the same values as `Version X (Build N)`.

Release signing and an explicit build-number override can be supplied without editing tracked files:

```sh
BUNDLE_IDENTIFIER=com.example.Jolt \
MARKETING_VERSION=0.1.0 \
BUILD_NUMBER=1 \
SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
scripts/build-app.sh
```

Omit `BUILD_NUMBER` for normal development builds so the counter advances automatically. After any successful app build, include the reported `Jolt build N` in the user-facing completion message.

Package the existing app as `build/Jolt.dmg`:

```sh
scripts/package-dmg.sh
```

If `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD` are all present, the packaging script also submits the DMG for notarization and staples the result. Keep these values in the environment or a local ignored configuration, never in source control.

## Icons and resources

- Source artwork: `Resources/AppIcon.png`.
- Generate icon sizes: `swift scripts/generate-app-icon.swift`.
- Asset catalog: `Resources/Assets.xcassets`.
- Bundle template: `Resources/Info.plist`.
- Sandbox permissions: `Resources/Jolt.entitlements`.

The app sandbox currently allows client and server networking. Review entitlements deliberately when adding platform capabilities.

## Change checklist

- Search model, parser, or JQL: update `JoltCore` tests and `docs/SEARCH.md`.
- Jira endpoint or DTO: verify error decoding, cancellation behavior, and that credentials are attached only to trusted Atlassian URLs.
- Persistence: preserve the distinction between Keychain secrets, `UserDefaults` preferences, and disposable caches.
- Site switching or logout: clear site-scoped memory and prevent stale tasks from publishing results.
- UI: verify both automatic appearance modes and keyboard-first operation.
- Build/release: keep signing identifiers and credentials external to the repository.
