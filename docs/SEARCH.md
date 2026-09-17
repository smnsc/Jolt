# Search and JQL contract

Search crosses three representations. Keep their roles distinct:

```text
PlainSearchTextEditor string
  -> SearchQueryParser (plain terms, shortcut text, direct key)
  -> AppModel metadata resolution
  -> ParsedSearch (resolved filters, plain terms, unresolved shortcuts, direct key)
  -> JQLBuilder output
  -> Jira search API
```

## User syntax

| Input | Meaning | Canonical value after resolution |
| --- | --- | --- |
| plain words | Full-text prefix terms | Each word becomes `text ~ "word*"` |
| `@DEV` | Project | Jira project ID |
| `#Bug` | Issue type | Jira issue-type ID |
| `~Jane` | Assignee | Jira account ID |
| `~me` | Assigned to the signed-in user | `currentUser()` |
| `>Jane` | Reporter | Jira account ID |
| `>me` | Reported by the signed-in user | `currentUser()` |
| `DEV-123` | Direct issue lookup when it is the only input | Uppercased issue key |

Names containing whitespace use portable quoted syntax, such as `#"User Story"` or `>"Jane Smith"`. Backslashes and quotes are escaped when a resolved shortcut is copied.

## Resolution is a safety boundary

Text that looks like a shortcut is not automatically trusted as a Jira value. The editor asks `JiraMetadataStore` for suggestions, but accepting a suggestion only completes ordinary text in the search field. The entire field always uses one font and shortcuts receive no chip, color, underline, or other special visual treatment.

After the input debounce, `AppModel` parses the same plain string and resolves exact project, issue-type, assignee, and reporter shortcut text against Jira metadata. Resolution exists only in the transient `ParsedSearch` passed to `JQLBuilder`; the editor and its stored input remain plain text.

If shortcut text cannot be resolved exactly and unambiguously, `SearchQueryParser` emits an `UnresolvedShortcut`. `JQLBuilder` must reject the entire search with `JQLBuilderError.unresolvedShortcuts`; unresolved values must never be interpolated into JQL.

Typed, pasted, and autocomplete-completed shortcuts follow the same resolution path. Unknown or ambiguous values remain ordinary text and prevent a Jira request without acquiring error styling.

## Combination rules

- Multiple values within one shortcut category use `OR` through one `IN` clause.
- Project, issue type, assignee, reporter, and plain-text categories combine with `AND`.
- Duplicate canonical values within a category are removed while preserving first-seen order.
- Each plain term is a separate prefix-text condition.
- A direct issue key is used only when it is the sole plain term and no resolved or unresolved shortcuts exist.
- An otherwise empty search defaults to issues updated in the last 180 days.
- Every query ends with `ORDER BY lastViewed DESC`.

Examples:

```text
pdf export + @DEV + @IT + #Bug
=> project IN ("DEV_ID", "IT_ID")
   AND issuetype IN ("BUG_ID")
   AND text ~ "pdf*"
   AND text ~ "export*"
   ORDER BY lastViewed DESC

~me + ~Jane
=> assignee IN (currentUser(), "JANE_ACCOUNT_ID")
   ORDER BY lastViewed DESC

~me >me >"Jane Smith"
=> assignee IN (currentUser())
   AND reporter IN (currentUser(), "JANE_ACCOUNT_ID")
   ORDER BY lastViewed DESC
```

Actual project and issue-type queries use Jira IDs returned by metadata, even though the UI displays names or project keys.

## Result scopes

When a search returns issues, the scope bar derives its Project and Issue Type choices from that
result set. Projects and Issue Types share one list, ordered by how many times each value appears in
the current results; ties are alphabetical. This ranked layout is the default. Settings → Search →
Scope Bar can switch to the alternative layout, which groups Projects and Issue Types separately.
It can also turn the scope bar off entirely.

Settings → Search → Results controls whether Jolt requests 10, 25, 50, or 100 issues; the
default is 25. A final **See more results in Jira** row opens Jira's issue search with the exact JQL
that produced the currently displayed result set.

Search responses omit issue descriptions so the result list can arrive with a smaller payload.
Jolt prefetches the selected issue's description after selection settles, fetches it on demand if a
preview opens first, and keeps fetched descriptions in memory for the current connection.

Choosing a Project appends its lowercase key as a normal shortcut (for example, `@si`); choosing an
Issue Type appends its name (for example, `#Epic`). The updated plain-text field follows the same
metadata resolution, debounce, and JQL path as typed input. Choosing an active scope removes that
shortcut, and **All** removes Project and Issue Type shortcuts while preserving plain terms and
assignees and reporters. Scope edits end with a space so the shortcut is committed and autocomplete remains
closed. Jira Issue Types that share a display name appear once in the bar and autocomplete, while
the query resolves to all of their canonical IDs.

Project autocomplete matches keys and full names, showing both in the dropdown. Exact key matches
rank first, followed by key prefixes, other key matches, and name matches.

Assignee (`~`) and reporter (`>`) autocomplete query their respective Jira fields. Both support
`me` as the signed-in user and require an unambiguous exact name or account ID for other users.
Their suggestion caches are separate, so an assignee match is never reused as a reporter match.

## Automatic query reset

Settings → Search → Auto-reset search query clears the query after the search window is hidden.
Choices are Immediately, After 5 seconds (default), After 15 seconds, After 30 seconds,
After 60 seconds, After 90 seconds, and Never. Reopening search before the delay expires cancels
that reset; hiding it again starts a new delay. The query stays intact while search is visible,
including the live preview behind Settings.

## Editing behavior

- Up/down moves through autocomplete when it is open; otherwise it moves result selection.
- Right Arrow opens the selected issue's description preview. Left Arrow, Backspace, or Escape
  returns from the preview to the search results.
- Completion preserves the casing of an already typed matching prefix or exact value; added text
  uses the suggestion’s casing. Metadata resolution remains case-insensitive.
- Return or Tab inserts the selected suggestion as plain text followed by a space. Tab does nothing
  when autocomplete is closed, while Return opens the selected issue.
- Option-Return opens the actions menu for the selected issue. Up/down changes the selected action,
  Return runs it, and Escape closes the menu.
- Space completes an exact suggestion when one exists; otherwise it inserts a normal space.
- Escape clears a nonempty query, closes autocomplete, and keeps focus in the search field. Pressing
  Escape again when the query is empty hides the search window.
- Copy, cursor movement, selection, and backspace use standard plain-text editing behavior. Pasted
  line breaks are converted to spaces so the editor remains a single-line query.

## Where to test changes

- Lexing, issue-key detection, and parsed grouping: `Tests/JoltCoreTests/SearchParserTests.swift`.
- Clause ordering, escaping, grouping, defaults, and rejection: `Tests/JoltCoreTests/JQLBuilderTests.swift`.
- Editor/AppKit behaviors and metadata resolution currently require manual app testing.
