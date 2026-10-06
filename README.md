<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" alt="Jolt app icon" width="112" height="112">
</p>

<h1 align="center">Jolt for macOS</h1>

<p align="center">
  <strong>Your Jira issues. One shortcut away.</strong><br>
  Find, preview, and share Jira issues from a native Mac app.
</p>

<p align="center">
  <a href="https://smnsc.github.io/Jolt/">Website</a> ·
  <a href="#get-started">Get started</a> ·
  <a href="#search-your-way">Search guide</a> ·
  <a href="agents/DEVELOPMENT.md">Build from source</a> ·
  <a href="https://ko-fi.com/simonsc">Support Jolt</a>
</p>

---

Press **⌥ J**, type what you need, and get back to work. Jolt brings Jira Cloud search to your desktop with autocomplete, quick previews, and shortcuts that keep your hands on the keyboard.

## Why Jolt?

- **Find issues from anywhere.** Bring up search with a global shortcut, just like Spotlight.
- **Search without writing JQL.** Combine words with projects, issue types, assignees, and reporters. Autocomplete helps you find the right match.
- **Preview without switching apps.** Read an issue’s description right in Jolt, or open it in Jira for the full picture.
- **Share in a few keystrokes.** Copy an issue’s key and title, or a rich link ready to paste into apps like Microsoft Teams.
- **Make it feel at home.** Choose your shortcut, appearance, and window size. Keep Jolt in the menu bar or Dock, and launch it at login.

Jolt is **read-only**: it searches your issues without changing them. Your API token and connection details are stored in **macOS Keychain**.

## Get started

You’ll need **macOS 14 or later**, a **Jira Cloud account**, and an **Atlassian API token**.

### 1. Install Jolt

Download a DMG from [GitHub Releases](https://github.com/smnsc/Jolt/releases), open it,
and drag **Jolt** to **Applications**. If no release is listed yet, build from source below.

Jolt is ad-hoc signed and **not Apple-notarized**. After trying to open it, use
**System Settings → Privacy & Security → Open Anyway** if macOS blocks it.
See [Apple’s instructions](https://support.apple.com/en-us/102445).

Jolt checks for updates automatically. **Settings → Updates** lets you turn checks
off, enable automatic installation, or check manually. Jira may need reconnecting
after an update because ad-hoc builds have different Keychain identities.

#### Build from source

With **Xcode 26 or later** installed, run these commands from your checkout:

```sh
scripts/build-app.sh
open build/Jolt.app
```

See the [development guide](agents/DEVELOPMENT.md) for Xcode setup, testing, and release packaging.

### 2. Connect your Jira account

1. Create a token in your [Atlassian API token settings](https://id.atlassian.com/manage-profile/security/api-tokens).
2. Open Jolt and enter your Jira site, such as `your-team.atlassian.net`, and your Atlassian account email.
3. Paste the token into the **API key** field and connect.

Regular and scoped tokens are supported with the Jira read permissions Jolt needs.

### 3. Find your first issue

Press **⌥ J** and search by keyword or issue key. Use **↑ / ↓** to select a result, **Return** to open it in Jira, **→** at the end of the search text to preview it, or **⌥ Return** for copy and open actions.

## Search your way

Start with a few words. Add shortcuts to narrow things down.

| Search | Find |
| --- | --- |
| `pdf export` | Issues matching both word prefixes |
| `DEV-1234` | A specific issue |
| `@dev #bug` | Bugs in the DEV project |
| `~me` | Issues assigned to you |
| `>me` | Issues reported by you |
| `@dev ~me pdf` | Your DEV issues matching “pdf” |
| `#"User Story"` | An issue type with spaces in its name |

Choose projects, issue types, and people from autocomplete. Use multiple shortcuts of the same kind to include either value: `@dev @it` searches both projects. Different kinds narrow the search together: `@dev #bug ~me` finds DEV bugs assigned to you.

Need more results? **See more results in Jira** opens the same search in your browser.

## For developers

Built with SwiftUI and AppKit. Open `Package.swift` in Xcode to explore the app.

[Development & releases](agents/DEVELOPMENT.md) · [Architecture](agents/ARCHITECTURE.md) · [Search & JQL](agents/SEARCH.md) · [Contributor guide](AGENTS.md)

## License and support

Jolt is available under the [MIT license](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md)
for Sparkle and its dependencies. Donations are optional: [Support Jolt on Ko-fi](https://ko-fi.com/simonsc).

Jolt is an independent project, not affiliated with Atlassian. It sends Jira requests
to Atlassian and update requests to GitHub. It does not send Jira credentials with
update checks or collect usage analytics.

Maintainers: see the [release guide](agents/RELEASING.md) for GitHub Pages, signed
updates, and the Homebrew tap.
