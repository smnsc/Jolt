# Jolt for macOS

A native, keyboard-first Jira Cloud issue searcher inspired by the Raycast Jira Search extension. Jolt supports plain prefix text search plus autocomplete-backed `@project`, `#issue type`, `~assignee`, and `>reporter` shortcuts.

## Highlights

- Global **Option-J** shortcut toggles Jolt like Spotlight, with Dock and menu-bar access.
- Result actions with **Option-Return**: open in Jira, copy the issue key and title, or copy a rich
  HTML link for pasting into apps such as Microsoft Teams. The footer actions are clickable, and
  right-clicking a result opens the same action menu.
- Lightweight issue previews: press **Right Arrow** on a result to read its description without
  leaving Jolt. Use **Up/Down Arrow** to scroll the preview.
- Resizable search window: drag its edges to resize it down to a 640 × 400 point minimum, or use
  the reset action in the window or menu-bar menu to restore its 900 × 560 point default size and
  center it slightly above the midpoint of the active display.
- Additive JQL: `pdf export @dev @it #bug #story` means both words, either project, and either issue type.
- Spotlight-style Project and Issue Type scopes add plain-text shortcuts to the query.
- Configurable 10, 25, 50, or 100-result limit, with a final handoff to the same live search in Jira.
- Plain-text autocomplete shortcuts, including issue types with spaces such as `#"User Story"`.
- User-supplied Atlassian API key with secure Keychain storage.
- Light, dark, and automatic appearance with opaque, tinted, and clear backgrounds.
- Configurable shortcut (including standalone F1–F12 keys), “Show in Dock and app switcher,” and Start at Login.
- Switching back to Jolt with Cmd+Tab brings search forward, even when Settings is open.

## Requirements

- macOS 14 or later.
- Xcode 26 or later for Icon Composer asset compilation, release archiving, signing, and notarization. Swift Package tests can also run with a matching Command Line Tools installation.
- A Jira Cloud account with access to the site you want to search.

## Connect Jira

The app shows these connection steps when it launches without saved credentials:

1. Open [Atlassian API token settings](https://id.atlassian.com/manage-profile/security/api-tokens).
2. Create and copy an API token.
3. Enter the Jira site (for example, `your-team.atlassian.net`) and the email address for the Atlassian account that created the token.
4. Paste the token into the API key field and connect.

The API key and its associated connection details are stored in macOS Keychain. The app uses Atlassian's API gateway, so both regular and scoped API tokens are supported when they include the Jira read permissions needed by the app.

## Develop and test

Open `Package.swift` in Xcode, select the `Jolt` scheme, and press Command-R. The app asks for the user's Jira connection details on first launch; no developer-owned Atlassian credentials are required.

Run the core Swift Testing suite with Xcode's Test action or:

```sh
swift test
```

The current machine must have a matching Swift compiler and macOS SDK. A full Xcode installation is required for the release packaging workflow.

The app icon is saved from Icon Composer as `Resources/AppIcon.icon`. The build script compiles it alongside `Resources/Assets.xcassets`, which retains the legacy PNG app icon for older macOS versions and the separate menu-bar icon. Edit and save the `.icon` document to update the modern icon; flattened PNG exports are not needed.

## Build a direct-download app

For a local build, run these commands in Terminal, replacing `/path/to/project` with your checkout location:

```sh
cd /path/to/project
scripts/build-app.sh
```

This creates `build/Jolt.app`, signs it for local use, and prints its new build number. No signing credentials are needed. The script automatically uses Xcode at `/Applications/Xcode.app`; for another installation, set `DEVELOPER_DIR` to its `Contents/Developer` directory.

Quit any running copy of Jolt, then launch the new build:

```sh
open build/Jolt.app
```

After changing `Resources/AppIcon.png`, run the same build command: it automatically regenerates the legacy icon sizes. The modern Liquid Glass icon comes from `Resources/AppIcon.icon`, so update that separately in Icon Composer when changing the modern design.

For a Developer ID signed release and notarized DMG:

```sh
BUNDLE_IDENTIFIER=com.example.Jolt \
SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
scripts/build-app.sh

APPLE_ID=... \
APPLE_TEAM_ID=... \
APPLE_APP_PASSWORD=... \
scripts/package-dmg.sh
```

Signing values are intentionally excluded from source control.

## Search syntax

- `pdf export` → `text ~ "pdf*" AND text ~ "export*"`
- `@dev @it` → either project
- `#bug #"user story"` → either issue type
- `~me` or an assignee selected from autocomplete
- `>me` or a reporter selected from autocomplete (for example, `>"Jane Smith"`)
- `DEV-1234` → direct issue-key lookup

Values within one shortcut category use OR semantics; categories and plain text use AND semantics.
For example, `@dev ~me >"Jane Smith"` finds DEV issues assigned to you and reported by Jane Smith.
Use `>me >"Jane Smith"` to match either reporter. Names resolve through Jira autocomplete; unknown
or ambiguous shortcuts must be matched before a search can run.

## Maintainer context

Start with [AGENTS.md](AGENTS.md) for the repository map and working rules. More focused context lives in:

- [Architecture](docs/ARCHITECTURE.md)
- [Search and JQL contract](docs/SEARCH.md)
- [Development and release workflow](docs/DEVELOPMENT.md)
