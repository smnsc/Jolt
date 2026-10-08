# Development

## Prerequisites

- macOS 14 or later.
- Swift 6 toolchain compatible with the package's Swift 5 language mode.
- Full Xcode 26 or later for Icon Composer asset compilation, universal release builds, signing, and notarization (verified with Xcode 26.6).
- A Jira Cloud account and user-supplied API token for live integration testing.

No developer-owned Jira credentials belong in the repository. The app collects credentials at runtime and stores them in macOS Keychain.

## Fast validation loop

Run the core suite from the repository root:

```sh
scripts/test.sh
```

The script selects the installed Xcode toolchain when `DEVELOPER_DIR` is unset,
keeps generated caches and build products in ignored `build/`, and disables the
nested SwiftPM sandbox for agent compatibility. Additional Swift test arguments
are forwarded, for example `scripts/test.sh --filter SearchParserTests`.
Plain `swift test` also works with a correctly selected toolchain; if it reports
an SDK/compiler mismatch from Command Line Tools, use the script above.

Open `Package.swift` in Xcode and run the `Jolt` scheme for application behavior. Useful manual checks after app-layer changes are:

1. Connect with a valid `*.atlassian.net` site, email, and API token.
2. Verify empty search, plain text, all four shortcuts (`@project`, `#type`, `~assignee`,
   `>reporter`), combined shortcuts, and direct issue keys. Check `>me`, a quoted reporter name,
   multiple reporters, and reporter autocomplete; unknown or ambiguous reporters must block search.
3. Exercise keyboard suggestion selection, copy/paste, Escape, result navigation, and Return-to-open.
4. Hide and reopen the search window with the global shortcut and menu-bar item. Cold-launch from the Dock and type immediately without clicking the window. With Dock visibility enabled, repeatedly open an issue with Return and confirm search stays hidden; return with Command-Tab, the Dock, and the global shortcut and verify keyboard focus.
5. Check clear-cache versus logout semantics.
6. Check appearance, Dock visibility, launch at login, and shortcut changes when touched. With Settings and search visible, toggle “Show in Dock and app switcher” off and on repeatedly: both windows should remain visible at their existing sizes and positions, with Settings retaining keyboard focus. Switch to another app afterward and confirm search still hides normally. With Jolt pinned in the Dock, disable “Show in Dock and app switcher”, then click its Dock icon repeatedly with search hidden and visible: search should open without a persistent running dot or app-switcher entry. Repeat after quitting and relaunching; re-enable the setting and confirm normal Dock/app-switcher visibility.

Authentication and Jira calls are live integration paths; the automated suite does not mock or exercise them today.

## Direct-download build

Build an ad-hoc signed universal app:

```sh
scripts/build-app.sh
```

The result is `build/Jolt.app`. The script builds arm64 and x86_64, compiles the asset catalog, applies bundle version values, signs, and verifies the app. Each successful local build automatically increments the lightweight counter in `build/.build-number`; the final output reports the version and build number. Settings displays the same values as `Version X (Build N)`.

Release signing and an explicit build-number override can be supplied without editing tracked files:

```sh
BUNDLE_IDENTIFIER=co.simonsc.jolt \
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

## Public distribution

Follow [RELEASING.md](RELEASING.md) for the first release and later updates. Sparkle
2.10.0 is pinned in Package.swift and Package.resolved. The build embeds its framework
and signs nested helpers individually before signing the host; do not use `--deep`
for signing. The sandbox installer requires the two bundle-specific Mach lookup
exceptions in `Resources/Jolt.entitlements`.

The default identifier is `co.simonsc.jolt`. Builds remain ad-hoc signed unless a
Developer ID identity is supplied. Sparkle archive/feed signatures use a separate,
free Ed25519 key in the maintainer's Keychain. `scripts/prepare-release.py` prepares
release assets and a matching Homebrew cask without publishing them.

## Icons and resources

- Modern app icon: `Resources/AppIcon.icon`; edit and save in Icon Composer.
- Legacy app icon source artwork: `Resources/AppIcon.png`.
- Menu-bar source artwork: `Resources/MenuBarIcon.png`.
- Regenerate legacy icon sizes: `swift scripts/generate-app-icon.swift Resources/AppIcon.png Resources/Assets.xcassets/AppIcon.appiconset`.
- `scripts/build-app.sh` regenerates these legacy sizes automatically from `Resources/AppIcon.png` before every build.
- Asset catalog: `Resources/Assets.xcassets`.
- Bundle template: `Resources/Info.plist`.
- Sandbox permissions: `Resources/Jolt.entitlements`.

The build compiles the `.icon` document and asset catalog together, producing `Assets.car` and `AppIcon.icns`, and merges the compiler's icon metadata into the app's Info.plist. Keep the catalog's `AppIcon.appiconset` for macOS 14/15 and `MenuBarIcon.imageset` for the menu bar. `Resources/AppIcon.iconset` is a standalone legacy export and is not read by the build script.

The app sandbox currently allows client and server networking. Review entitlements deliberately when adding platform capabilities.

## Change checklist

- Search model, parser, or JQL: update `JoltCore` tests and `dev-docs/SEARCH.md`.
- Jira endpoint or DTO: verify error decoding, cancellation behavior, and that credentials are attached only to trusted Atlassian URLs.
- Persistence: preserve the distinction between Keychain secrets, `UserDefaults` preferences, and disposable caches.
- Site switching or logout: clear site-scoped memory and prevent stale tasks from publishing results.
- UI: verify both automatic appearance modes and keyboard-first operation.
- Build/release: keep signing identifiers and credentials external to the repository.
