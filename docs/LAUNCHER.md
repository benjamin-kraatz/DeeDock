# Launcher

Optional [app suggestions](LAUNCHER-SUGGESTIONS.md) appear above ordinary results for an empty query after explicit opt-in.

The permanent **App Launcher** tile expands its dock window into a panel on the same display.
**Back to dock** and Escape reverse the transition. An outside click closes the panel without
reactivating the previous app. Reduce Motion disables the window animation, and Reduce
Transparency supplies an opaque background.

The launcher is also a selectable tile in **Focus Dock**. Return opens it. In the launcher,
typing searches apps, windows, saved work, Shelf filenames, pinned Shortcuts, and Dock Modes.
Arrows select results, and Return performs the selected result's labeled action. If no result
has been selected, Return performs the first result's action. Command-F focuses the search field. Tab navigates the native controls.

## Search and discovery

Search matches names, bundle filenames, identifiers, executable names, and localized aliases.
It ignores case, accents, character width, and invisible formatting characters. Exact names rank above prefixes, substrings,
initials, and metadata matches. One-edit typo matching applies to name tokens of at least four
characters and includes adjacent transpositions. Typing does not invoke Robi.

Discovery runs off the main actor when the launcher opens. It scans `/Applications`,
`~/Applications`, `/System/Applications`, and `/System/Library/CoreServices/Applications`.
Spotlight supplements those directories with apps at other indexed locations. Pins, running
apps, and previously opened apps supply additional known locations. The standard directory
scan works without Spotlight. Background helpers and nested bundles are excluded from
general discovery, as are cache locations and incompatible device builds. Candidates must have
a runnable executable. Duplicate bundle identifiers produce one entry.

The installed-app snapshot stays in memory between presentations. Opening the launcher or
choosing **Refresh apps** refreshes it. Discovery stops when the last launcher closes. Apps in
unindexed, nonstandard folders that DDock has never opened or pinned may not appear. A warning
identifies directory enumeration failures. Synthetic metadata-ranking measurements are recorded in [DEE-20 acceptance](ACCEPTANCE.md#dee-20-unified-launcher).
Discovery completeness and end-to-end native latency remain unmeasured.

Each app has a context menu in both views: **Open**, **Show in Finder**, **Pin** or
**Unpin**, **Pin on Display**, and **Create capsule…**. Pinning applies to the source
display; the submenu lists other enabled docks. Creating a capsule opens an editable draft
containing that app. Enter a summary and save to persist it.

## Mixed search

A nonempty query keeps app matches in the selected grid or list layout. Other kinds use compact
rows that identify their kind, source, and default action.
**Result type** filters apps, windows, Capsules and Breadcrumbs, Shelf files, pinned Shortcuts,
or named Dock Modes. Selecting a non-app type also browses that source without a query.
Clear the query and choose **All types** or **Apps** to return to app grid/list browsing.
App filters, sorting, and grouping apply with or without a query, including when **Apps** is
selected as the result type. Running, pinned, and recent filters show only matching apps in
**All types** or **Apps**. Select the all-apps filter to include other kinds again. A specific
non-app result type uses its own source and ignores the hidden app filter. App sections appear first and use the selected
category or first-letter grouping. Other kinds remain compact rows below them.

Ordinary search reads copied metadata. It does not capture windows, read file contents,
request permission, use a model, or run an action. Queries debounce for 120 milliseconds.
Ranking runs outside the UI actor and obsolete tasks cannot publish results. Forty rows appear
initially; **Show more results** reveals forty more. A selected object retains its identity
when another provider finishes. If that object disappears, Return does nothing until you select
another result, rather than acting on a replacement. Explicit window refresh obtains new AX tokens
and requires selecting a window again.

App matching retains normalization, aliases, and one-edit typo matching. Within each app group,
relevance ranks first and the chosen name, recent, or frequent order breaks ties. Other kinds
retain their own relevance order. Prefix, substring, app alias, window metadata,
historical capsule, and app typo matches use fixed priorities with name and typed identity
as tie-breakers. Objects of different kinds remain separate even when their names match.

Window titles are a snapshot from opening or explicit refresh. Exact window actions revalidate
the original process and AX handle. Metadata-only windows without usable AX handles are labeled
unavailable for exact activation. **Refresh window metadata** obtains a fresh snapshot.
App-level search remains available without capture permission or Apple Intelligence.

Capsule matches identify historical saved text. Matches found only in saved breadcrumb OCR carry
**Saved OCR text · historical**. Opening a capsule uses the current saved object and does not
resume it automatically. Shelf rows identify stored references whose availability is checked on
opening. Missing files produce an error and keep the Launcher open. Shortcut availability is
checked by the existing runner; running, success, and failure status remain visible in the row.
The runner prevents duplicate concurrent runs. A deleted or guarded mode cannot be activated.
Unreadable stores show a notice without removing other providers' results or rewriting storage.

Right-click a row for its actions, or use Tab to reach **Result actions** for the keyboard-selected
row. App results retain their full existing menu. Shelf files also offer **Show in Finder**;
window results offer metadata refresh. **Capture & image search…** opens the existing explicit
window-search flow with its capture chooser, OCR, and separately labeled model suggestions.
The existing **Find a Window** entry points and keyboard shortcut keep their existing controls.

## Views and history

| Control | Choices |
| --- | --- |
| View | Grid or list |
| Filter | All apps, running, pinned on the source display, or recent |
| Sort | Name, last opened through DDock, or number of opens through DDock |
| Group | None, application category, or first letter |

Search relevance precedes the selected sort order. Choosing **Recent** selects last-opened
sorting; the sort menu can change that order. Missing category metadata goes into **Other
apps**. View choices remain with the display's panel for its lifetime.

Launch history records successful app opens and document handoffs through the shared DDock
application catalog. Hiding an already foreground app, failed opens, and app activation
outside DDock do not create entries. History persists under `launcher.history.v1` and retains
at most 500 app identities. The launcher options menu clears the history after confirmation.
Unreadable history bytes remain untouched until that explicit clear action.

## Robi

**Ask Robi** matches a task description to installed apps using on-device Apple Intelligence.
It receives the task and app names, categories, and bundle identifiers. It receives no file
contents or window captures. Requests use bounded batches and can be cancelled. Editing the
query or closing the launcher invalidates pending suggestions.

Suggestions are restricted to known app identities. Robi never opens an app itself. The user
chooses a result to launch it. If Apple Intelligence is unavailable or a request fails, the
launcher shows an explanation and keeps ordinary app search available. A final review limits the combined results to five suggestions. Suggestion quality depends on
the local model and app metadata; the native checks cover a limited set of tasks.

The search phrase `do a barrel roll` reveals the Easter egg. With Reduce Motion enabled, its
message appears without rotation.

Compilation and remaining native checks are recorded in [acceptance notes](ACCEPTANCE.md#dee-8-app-launcher).

## File actions

Choose **Use in Launcher** from a Shelf selection, drop files on the Launcher tile or open
panel, or choose **Choose Files**. The Launcher shows the ordered batch and actions that can
use it. Search and the Apps / Shortcuts / Folders filter narrow that list. Hover and keyboard
selection do not run an action. Return or a click runs it once.

**Open with** is an app-level handoff. It does not attach files to a window or project; that
path remains [Window Peek file routing](WINDOW-FILE-HANDOFF.md). An app that declares support
for only some files stays listed with the unsupported names. Those files are not opened
silently.

Pinned Shortcuts appear as **Pass selected files to this Shortcut**. DDock does not claim to
know what a Shortcut accepts. Mark **Pass selected files** in Settings to sort a Shortcut
with the file-input actions. The installed Shortcut list loads when Settings, Watch, or this
file-action UI appears. **Reload Shortcuts** remains a manual refresh. The existing
one-run-per-Shortcut rule still applies.

**Copy** writes into a chosen or bookmarked folder and leaves the sources in place. Existing
destination names are never replaced; a conflicting copy gets a numbered name. Saved
destinations are local bookmarks under Settings → Features → Action Tiles. Removing a
destination deletes the bookmark, not the folder.

Clear the batch or choose **Back to Search** to return to ordinary Launcher search. File
contents are not read to rank actions. Shortcut output is not captured back to Shelf.

Compilation and remaining native checks are recorded in [acceptance notes](ACCEPTANCE.md#dee-24-launcher-file-actions).
