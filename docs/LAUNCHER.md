# App Launcher

The permanent **App Launcher** tile expands its dock window into a panel on the same display.
**Back to dock** and Escape reverse the transition. An outside click closes the panel without
reactivating the previous app. Reduce Motion disables the window animation, and Reduce
Transparency supplies an opaque background.

The launcher is also a selectable tile in **Focus Dock**. Return opens it. In the launcher,
typing searches applications, arrows select results, and Return opens the selected result or
the first result. Command-F focuses the search field. Tab navigates the native controls.

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
identifies directory enumeration failures. Search latency and discovery completeness have not
been measured on a large application collection.

Each app has a context menu in both views: **Open**, **Show in Finder**, **Pin** or
**Unpin**, **Pin on Display**, and **Create capsule…**. Pinning applies to the source
display; the submenu lists other enabled docks. Creating a capsule opens an editable draft
containing that app. Enter a summary and save to persist it.

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
