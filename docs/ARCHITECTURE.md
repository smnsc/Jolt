# Architecture

## Shape of the app

Jolt has two Swift Package targets:

- `JoltCore` owns portable models, the search parser, JQL generation, and credential/cache protocols.
- `JoltApp` owns macOS UI and integrations: SwiftUI, AppKit, Carbon hot keys, Service Management, Keychain use, disk caching, and Jira HTTP calls.

The executable starts in `JoltApp.swift`. `AppDelegate` applies the Dock policy, registers the global shortcut, and starts the shared `AppModel`. The same model is injected into the search window, menu-bar item, and settings scene.

## Runtime flow

```text
JoltApp / AppDelegate
        |
        v
AppModel (@MainActor) <---- SearchView / SettingsView / SearchField
   |       |       |
   |       |       +---- ImageRepository (@MainActor) ---- CacheManager actor
   |       +------------ JiraMetadataStore actor ---------+
   +-------------------- JiraClient actor -----------------+---- Jira Cloud
                              |
                              +---- JiraAuthSession actor ---- Keychain
```

`AppModel` is the coordination point. It owns published connection, input, results, selection, issue-preview, error, and autocomplete state. It also owns cancellable tasks for connection, search, and autocomplete work.

The search window uses custom, draggable chrome but remains a native, resizable titled window underneath so it can become key after being dismissed and restored. `AppModel` owns showing, hiding, and resetting it to its default centered frame; restoration defers first-responder focus until the window is key.

## Important files

| Concern | Primary file | Notes |
| --- | --- | --- |
| App lifecycle and scenes | `Sources/JoltApp/JoltApp.swift` | Search window, menu bar, settings, launch setup |
| State and async coordination | `Sources/JoltApp/AppModel.swift` | Debounce, cancellation, site changes, result selection |
| Main search UI | `Sources/JoltApp/SearchView.swift` | Connection, loading, empty, result, and footer states |
| Plain search editor | `Sources/JoltApp/SearchField.swift` | Single-line AppKit text view inside SwiftUI |
| Jira credentials | `Sources/JoltApp/JiraAuthSession.swift` | Site validation and Keychain-backed Basic auth |
| Jira API boundary | `Sources/JoltApp/JiraClient.swift` | Read-only REST requests and DTO mapping |
| Metadata/autocomplete | `Sources/JoltApp/JiraMetadataStore.swift` | Projects/types locally; assignees remotely |
| Cache and images | `Sources/JoltApp/CacheManager.swift` | 24-hour metadata snapshot and issue-type images |
| Preferences | `Sources/JoltApp/AppPreferences.swift` | `UserDefaults`, Dock state, login item, shortcut |
| Domain models | `Sources/JoltCore/Models.swift` | Search and Jira value types |

## Authentication and network boundary

Connection accepts only an HTTPS `*.atlassian.net` site with no credentials, port, query, fragment, or non-root path. `JiraAuthSession` obtains the cloud ID from `/_edge/tenant_info`, validates credentials through Atlassian's API gateway, and stores the site, email, and API token as one Keychain value.

Authenticated Jira REST calls use:

```text
https://api.atlassian.com/ex/jira/{cloudID}/rest/api/3/...
```

`JiraClient` currently reads projects, issue types, autocomplete suggestions, and a configurable 10, 25, 50, or 100 search results (25 by default). It also fetches issue-type images, adding credentials only for the selected Jira tenant or its API-gateway URL. Preserve that host check to avoid leaking Authorization headers.

Logging out removes the Keychain value, clears in-memory state, and deletes cached Jira data. Clearing the cache alone preserves login and preferences.

## Persistence

- Keychain: Jira site, email, and API token under account key `atlassian.api.credentials`.
- `UserDefaults`: appearance, background style, scope-bar layout, Dock visibility,
  launch-at-login choice, shortcut, and selected site.
- Caches directory: `Jolt/metadata.json` plus hashed issue-type images.
- Memory: current results, autocomplete state, metadata, and decoded images.

The metadata disk snapshot is scoped to one site ID and fresh for 24 hours. Assignee suggestions are cached only in memory by normalized query.

## Concurrency invariants

- UI mutation stays on `@MainActor`.
- Mutable authentication, client-site, metadata, and disk-cache state stays inside actors.
- Search input is debounced by 250 ms; initial site selection searches immediately.
- Assignee autocomplete is debounced by 180 ms; project and issue-type autocomplete use loaded metadata immediately.
- Check cancellation and current context before publishing asynchronous results. A cancelled request must not replace newer state.

## Current test boundary

Automated tests cover `JoltCore` parser and JQL behavior. The macOS application target has no automated UI or service tests yet, so changes to authentication, networking, caches, preferences, hot keys, windows, and rich-text editing require manual verification.
