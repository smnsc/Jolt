# Development

## Prerequisites

- macOS 14 or later.
- Swift 6 toolchain compatible with the package's Swift 5 language mode.
- Full Xcode 26 or later for Icon Composer asset compilation, universal release builds, signing, and notarization (verified with Xcode 26.6).
- A Jira Cloud account and user-supplied API token for live integration testing.

No developer-owned Jira credentials belong in the repository. The app collects credentials at runtime and stores them in macOS Keychain.

## Fast validation loop

Run script checks and the core suite from the repository root:

```sh
scripts/test.sh
```

Successful script checks buffer fixture output so simulated build versions never
appear as real build results; failed checks include their captured output.
The script first checks the build/release/website helpers, then selects the installed Xcode toolchain when `DEVELOPER_DIR` is unset,
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
5. With another app in native full screen (including video playback and a Microsoft Teams call), invoke search with Option-J and confirm it appears over that app without switching to a desktop Space. Type immediately, dismiss with Escape, and repeat with the shortcut to open and hide. Repeat with “Show in Dock and app switcher” both enabled and disabled, and check ordinary desktop Spaces as well.
6. Leave search open over a full-screen app, swipe back to the desktop, and invoke it again: search should dismiss on the swipe and reopen visibly on the desktop with immediate keyboard focus. Repeat in the opposite direction and across ordinary desktop Spaces, including swiping during the first 350 ms after invocation. After swiping away, Return must not open an issue through the hidden panel. Repeat with Dock visibility enabled and disabled.
7. From a full-screen Space, reveal the Dock and click Jolt: after any macOS Space transition, search must appear promptly, stay visible, and accept typing instead of flashing and hiding. Confirm repeated activation/reopen events do not add another half-second of waiting. Repeat with search already open, repeated Dock clicks, and Dock visibility enabled/disabled. Click another app or dismiss search before presentation completes: Jolt must not reappear or steal focus. Then confirm swiping away from open search still dismisses it and Option-J reopens it on the current Space.
8. Check clear-cache versus logout semantics.
9. Check appearance, Dock visibility, launch at login, and shortcut changes when touched. With Settings and search visible, toggle “Show in Dock and app switcher” off and on repeatedly: both windows should remain visible at their existing sizes and positions, with Settings retaining keyboard focus. Switch to another app afterward and confirm search still hides normally. With Jolt pinned in the Dock, disable “Show in Dock and app switcher”, then click its Dock icon repeatedly with search hidden and visible: search should open without a persistent running dot or app-switcher entry. Repeat after quitting and relaunching; re-enable the setting and confirm normal Dock/app-switcher visibility.

Authentication and Jira calls are live integration paths; the automated suite does not mock or exercise them today.

## Script layout

The top level contains the three everyday commands:

| Command | Purpose |
| --- | --- |
| `scripts/build.py [X.Y.Z \| --build-only]` | Test and create a new numbered local build; prompt if no argument is given |
| `scripts/test.sh [Swift test arguments]` | Run script checks and Swift tests |
| `scripts/release.sh` | Request a release from committed remote main |

Supporting scripts are grouped under `scripts/macos/` (app assembly and icons),
`scripts/release/` (packaging and signing), `scripts/website/` (download links),
`scripts/shared/` (version validation), and `scripts/tests/` (script checks).
The build command is directly executable Python; no shell wrapper is needed.
The macOS app builder remains separate so CI and retries can compile the tracked
version/build without incrementing it or prompting.

## Direct-download build

For a new local test build, run:

```sh
scripts/build.py           # Prompt for a version; Enter keeps the current version
scripts/build.py 0.1.5     # Supply a new version directly
scripts/build.py --build-only  # Skip the version prompt; increment only the build number
```

The script runs `scripts/test.sh`, updates the tracked version/build number, and
calls `scripts/macos/build-app.sh`. A supplied version must exceed the current version;
its `dev-docs/releases/X.Y.Z.md` is created only if missing, using the release
notes template and commit history. If notes for the selected version already exist,
interactive builds ask whether to regenerate them from scratch, including when
keeping the current version. Yes replaces the file with the template and current
committed history, including new commits; manual edits are replaced. Enter, No,
or end-of-input preserves the existing file. Without a terminal, existing notes
are preserved and omitted version input means build only. Review notes before
committing. Failed tests leave tracked files
unchanged. If compilation fails, the new identity and notes are retained; retry
with `scripts/macos/build-app.sh` to avoid incrementing again. No commit or publication
is performed.

To rebuild the same numbered source directly:

```sh
scripts/macos/build-app.sh
```

The result is `build/Jolt.app`. The script builds arm64 and x86_64, compiles the asset catalog, signs, and verifies the app.
Run `python3 scripts/tests/test_build.py` for offline local-workflow checks.

Xcode with the macOS 27 SDK may warn that Intel is deprecated for a macOS 27
deployment target during a universal build. The built executable was checked with
`vtool -show-build`: both slices still declare macOS 14.0, matching the package and
app plist. Keep Intel support; this warning alone does not indicate a failed build.
Swift test output also includes an XCTest summary of zero tests before the actual
Swift Testing results; use the final Swift Testing count.

`Resources/Info.plist` is the source-controlled authority for both
`CFBundleShortVersionString` (MAJOR.MINOR.PATCH) and `CFBundleVersion` (a positive
integer without leading zeros). Settings displays `Version MAJOR.MINOR.PATCH (build N)`;
Sparkle uses the build number to order updates. Increment the tracked build number
when preparing a new build for testing or distribution, and commit it with the source.
Rebuilding the same source preserves its number, even after deleting `build/`.
The old `build/.build-number` is no longer read or written.

Every published release must increase both the version and build number. Never
reuse a published version. `MARKETING_VERSION` and `BUILD_NUMBER`, if supplied,
must match the tracked values; they cannot override them. The release command and direct GitHub workflow dispatches both read the version
and build number from the committed remote `main` plist; no release arguments are
needed. The release command asks for confirmation if files are staged, unstaged,
or untracked, or if the current branch has unpushed commits or differs from remote
`main`. Continuing releases remote `main`; Enter or missing input cancels.

Optional signing settings remain available:

```sh
SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" scripts/macos/build-app.sh
```

After any successful app build, include the reported **Jolt build N** in the
completion message.

Package the existing app as `build/Jolt.dmg`:

```sh
scripts/release/package-dmg.sh
```

Packaging generates a compact Retina background with installation and first-launch
instructions below the Jolt and Applications icons. It mounts a temporary
writable image and uses Finder to save the window size, background, and icon
positions before compressing it. Run in a logged-in macOS session with Finder
available; macOS may request permission for the terminal to control Finder.
Layout lives in `scripts/release/configure-dmg.applescript`; artwork and wording live in
`scripts/release/generate-dmg-background.swift`. Repackaging an unchanged app preserves
its build number. Open the final DMG to visually check the layout after changes.

If `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD` are all present, the packaging script also submits the DMG for notarization and staples the result. Keep these values in the environment or a local ignored configuration, never in source control.

## Public distribution

Follow [RELEASING.md](RELEASING.md) for the first release and later updates. Sparkle
2.10.0 is pinned in Package.swift and Package.resolved. The build embeds its framework
and signs nested helpers individually before signing the host; do not use `--deep`
for signing. The sandbox installer requires the two bundle-specific Mach lookup
exceptions in `Resources/Jolt.entitlements`.

The default identifier is `co.simonsc.jolt`. Builds remain ad-hoc signed unless a
Developer ID identity is supplied. Sparkle archive/feed signatures use a separate,
free Ed25519 key in the maintainer's Keychain. `scripts/release/prepare.py` prepares
release assets and a matching Homebrew cask without publishing them. It generates
release notes from commit history when no versioned notes file exists; otherwise
it uses the notes created by `scripts/build.py`. Supply an optional notes file
to use custom text from another path. Local app builds do
not require release notes.

## Icons and resources

- Modern app icon: `Resources/AppIcon.icon`; edit and save in Icon Composer.
- Legacy app icon source artwork: `Resources/AppIcon.png`.
- Menu-bar source artwork: `Resources/MenuBarIcon.png`.
- Regenerate legacy icon sizes: `swift scripts/macos/generate-app-icon.swift Resources/AppIcon.png Resources/Assets.xcassets/AppIcon.appiconset`.
- `scripts/macos/build-app.sh` regenerates these legacy sizes automatically from `Resources/AppIcon.png` before every build.
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
