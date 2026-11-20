# Flix Files

Flix Files (DEE-163) is an activity stream of what you opened, downloaded, saved, and screenshotted, built to be dragged from. Its home is a dock tile; the panel opens above the tile, at the pointer with Control-Option-Command-F, or under an optional menu bar item. The approved designs are [`mockups/flix-files-v2.html`](mockups/flix-files-v2.html) (the concept) and [`mockups/flix-files-ai.html`](mockups/flix-files-ai.html) (the target UI with every ✦ feature). How each feature behaves for a person is in the [guide](GUIDE.md#flix-files).

This document covers phase A: the data, sources, tile, panel, drag, settings, and every ✦ surface wired to an inert slot model. The intelligence providers (phase B1 and B2), link tracking (B1), and analytics (C) are planned and marked as such below.

## How it is built

Everything lives in `DeeDock/Flix/`, one responsibility per file.

| Folder | What it holds |
| --- | --- |
| `Coordination/` | `FlixCoordinator` (owned by `DockCoordinator`; lifecycle, sources, open and close, drags), `FlixTileState` (what every tile draws), `FlixDockItem`, `FlixFrontmostContext+Capture` |
| `Models/` | `FlixItem` and `FlixActivityEvent`, `FlixActivity`, `FlixItemKind`, `FlixLink`, `FlixFilter`, `FlixSmartFilter` and its rules, `FlixFavorite`, `FlixTimeGroup`, `FlixPaths` |
| `History/` | `FlixHistoryDocument` (the merge rules), `FlixLibraryDocument` (Favorites, Smart Filters), `FlixHistory` (the observable store), `FlixJSONFile` (debounced atomic writes off the main actor) |
| `Sources/` | `FlixSpotlightSource`, `FlixFolderWatcher` (FSEvents), `FlixNoiseRules`, `FlixReadPolicy` |
| `Intelligence/` | `FlixIntelligence` (the slot model), the provider protocols, the slot values, live engine status |
| `Shortcut/` | `FlixShortcut` (Carbon hot key ID 19), `FlixShortcutCombo`, `FlixShortcutConflict`, the recorder |
| `Panel/` | `FlixPanelController` (window), `FlixPanelGeometry`, `FlixPanelState` with its commands and keys, `FlixListBuilder`, `FlixFileActions`, `FlixQuickLook` |
| `Drag/` | `FlixDragSession` (`NSDraggingSource`) |
| `Views/` | Panel, sidebar, list, rows, cards, sheets, footer, tile, and shared pieces, with previews over `FlixPreviewData` |
| `MenuBar/` | `FlixStatusItemController` |
| `Settings/` | `FlixSettings`, its repository and store, and the Settings page's cards |

### Data

`FlixHistory` is DOKK's own history; Spotlight and the folder watcher only feed it. Every source produces `FlixActivityEvent`s, which `FlixHistoryDocument.record(_:)` merges:

- One item per standardized path (or page address). A newer event changes the item's activity and moves it to the top; an older one only fills in missing details. Identity, flag, and first-seen date survive, so selection and phase B's annotations stay attached.
- When two sources report the same moment, a download beats "new", which beats "saved".
- **Remove from Flix Files** leaves a tombstone: the item returns only with activity newer than its removal. Undo restores it.
- At most 5,000 items, oldest unflagged first; flagged items never age out. Noise is capped separately at 200, so a build folder cannot push real activity out.
- A finished download replaces its partial entry (`Report.pdf.crdownload` → `Report.pdf`).

The history and the library are two JSON files in `~/Library/Application Support/DDock/Flix/` (`Flix-dev/` for a development build, the split Lookout makes). Writes coalesce for 0.8 seconds and run on a utility queue; quit flushes them. An unreadable file is moved aside as `history.unreadable-<time>.json` and Flix Files starts fresh, so a broken file never stops it.

Settings are JSON under `flix.settings.v1` in DOKK's defaults. Missing keys decode to their defaults.

### Sources

- **Opened** (`FlixSpotlightSource`): a live `NSMetadataQuery` on `kMDItemLastUsedDate` over the last 30 days, folders included and app bundles left out. The first gather seeds the newest 300; updates report only what changed. Everything comes from Spotlight's attributes (path, name, type, size, `kMDItemIsScreenCapture`, `kMDItemWhereFroms`), so it never reads a file.
- **New, saved, downloaded** (`FlixFolderWatcher`): one FSEvents stream with file-level events over the watched folders DOKK may read. Events coalesce per path for 1.2 seconds. A file born in the last five minutes is a download when it carries `kMDItemWhereFroms` or sits in Downloads, otherwise new; an older file that changed is saved. Screenshots come from the `kMDItemIsScreenCapture` attribute. Hidden files, package internals, partial downloads, and noise are skipped.
- **Apps**: `DockCoordinator`'s existing activation callback; each app is recorded at most every five minutes. Finder and DOKK are left out.

The download page is stored as scheme, host, and path only (`FlixPaths.sourcePage`), so tokens in a query or fragment are never kept.

### Folder access

`FlixReadPolicy` decides what may be touched on disk. Desktop, Documents, Downloads, iCloud Drive, cloud storage folders, and other volumes are protected (`LookoutFolderChoice.needsPrompt`): reading one makes macOS show its Files and Folders prompt. A protected path is readable only inside a watched folder you allowed with **Allow…** (in Settings or on the panel's card) or inside a folder Lookout's setup already read with your permission, since macOS grants per app. Thumbnails, file icons, the watcher, and file commands check the policy; otherwise rows draw the type's icon. No background work can cause a prompt.

### Tile

`DockRenderSlot.flix` sits in the trailing utilities after the Notification Feed and is reorderable like them (`dockUtilityOrder`). `DockFlixButton` reads `FlixTileState` from `DockInteraction.flix`, so a new item redraws the tiles alone. A plain drag carries the newest item through `FlixDragSession`; Option-drag moves the tile (`DockUtilityMoveModifier.movesOnlyWithOption`, the Shelf's split inverted). A file drag from Finder onto the tile goes through `DockDragCoordinator` (`DockUtilityDropTarget.flix`) and is kept; the tile refuses Flix's own items. The badge counts downloads and new files since the panel was last opened.

### Panel

`FlixPanelController` owns a borderless key panel at the floating level, the body plus a 30-point transparent margin for the shadow. Anchored, it sits 12 points above (or beside) the tile and follows it when the dock moves; at the pointer, its top-left corner sits a little up and left of the pointer. Both clamp into the display's visible frame (`FlixPanelGeometry`, tested with negative origins). Opening goes through `ExplicitWindowPresenter`, so the panel becomes key and search gets a field editor.

Before anything takes focus, the coordinator captures the app and window in front (`FlixFrontmostContext.capture`): process, bundle identifier, app name, and the frontmost window's number from the window server's list, with its title only when Screen Recording is granted. `FlixPanelState.frontmost` holds it for the panel's lifetime.

Monitors exist only while the panel is on screen: a local key monitor that offers every key to `FlixPanelState.handleKey`, local and global mouse-down monitors for outside clicks (a dock click closes the panel and is consumed), and an observer that closes it when DOKK stops being active. None of them closes the panel during a drag out or while Quick Look is up. An anchored panel registers as the `.flix` popover, which closes the other popovers and holds the docks revealed.

### Dragging out

Rows, the selection, a Thread card, and the tile start a `FlixDragSession`: file URLs, web URLs for links, and a private type listing item IDs. As the pointer leaves the panel it fades to 6 % and lets the pointer through; after a drop outside it closes unless pinned or set to stay open; a cancelled drag brings it back. A drop on a dock app opens the files there, as any file drag does.

Two hooks exist for phase B1, both at drag start because macOS never tells a drag source where the drop will land:

- **Substitution.** `FlixIntelligence.dragPlan(for:context:)` asks `FlixDragIntercepting.plan(for:context:fits:)`. Its `substitutions` replace an item's file on the pasteboard (a PDF made from an image for a PDF-only portal). It is synchronous, so conversions must exist already; browsers read file URLs, not promises.
- **Confirmation.** `FlixIntelligence.dropConfirmation(for:context:)` asks `FlixDragIntercepting.confirmation(for:context:)`, then falls back to phase A's own rules: an item annotated as sensitive (while the guard is on), then an older version with a newer one in the history. A question stops the drag and shows a dialog in the panel; answering lets the next drag of the same items go ahead for 30 seconds ("Drag it again to send it"). A tile drag that needs a question opens the panel with it.

## Intelligence slots (contract for phase B)

`FlixIntelligence` (`@Observable`, main actor) is the only thing the views read for ✦ features. With no providers, every slot stays empty and its surface does not appear; plain filters and name search keep working. Phase B assigns `flix.intelligence.providers` (a `FlixIntelligenceProviders` struct of optional existentials) and keeps `flix.intelligence.engines` current.

| Slot | Provider protocol | Surface |
| --- | --- | --- |
| `fits`, `tileFitCount` | `FlixFitsProviding` | Fits card with reader chain and shimmer; tile pill |
| `query` | `FlixSearchProviding` | "Ask in your own words", Understanding…, tokens, "by meaning" chips |
| `threads` | `FlixThreadProviding` | ✦ Threads sidebar section, Thread card, Show Thread |
| `annotations` | `FlixAnnotationProviding` | Captions, Rename and Move pills, fact chips, sensitive blur, version pill and children, learned noise |
| `morning` | `FlixMorningProviding` | Where were you? card |
| `moreLikeThis`, `semanticMatch` | `FlixSimilarityProviding` | More like this token and results; `.about` Smart Filter rules |
| `smartFilterDraft` | `FlixSmartFilterGenerating` | New Smart Filter from a sentence |
| `tidy` | `FlixTidyProviding` | Tidy sheet |
| `robi` | `FlixRobiProviding` | Ask Robi sheet, ⌘R, menu item (must opt out of AI observability content) |
| `filterTip`, `dragReason`, `notice` | `FlixDragMemoryProviding` | Sidebar tip card, "you've sent PDFs here before", Forget |
| drag hooks | `FlixDragIntercepting` | Conversions and drop questions |

Every slot task is cancelled when its replacement starts, and a generation check drops stale results; `panelClosed()` cancels the panel's tasks and `stop()` all of them. Providers read the intelligence and link switches from `flix.settingsStore.settings` (`suggestsForFrontWindow`, `showsFitsOnTile`, `writesCaptions`, `groupsThreads`, `suggestsFolders`, `guardsSensitiveFiles`, `learnsDragDestinations`, `tracksLinks`, `tracksPagesYouRead`, `excludesSensitiveSites`, `excludedSites`, `fetchesSiteIcons`); `FlixIntelligence.settings` mirrors them and hides disabled surfaces.

Link items (phase B1) are recorded with `flix.history.record(_:)` and a `FlixActivityEvent` whose `link` is set and whose activity is `.link`. Rows already draw them with the page's host.

## Settings

**Settings → Flix Files** is its own section under Features, like Lookout and Plugins:

- **Flix Files** on or off. Off removes the tile, the menu bar item, and the shortcut, and stops every source.
- **Where it lives**: Show in the dock (on), Show in the menu bar (off), Keyboard shortcut with a recorder (Control-Option-Command-F). The recorder needs Control, Option, or Command (function keys excepted), refuses DOKK's own shortcuts and app-wide commands, and warns about Spotlight's and launchers' combinations. An orange row appears when another app holds the combination. Recording pauses the shortcut so pressing the current combination records it.
- **When Flix Files opens**: Do nothing, Copy newest, or Copy its path. **After you drag something out**: Close or Stay open.
- **What it tracks**: Files you open, New, saved, and downloaded files, Folders, Apps, and the watched folders with their access and **Allow…**.
- **Web links** (planned for phase B1): Track web links (off), Pages you read (off, its own opt-in), Leave out banking and health sites (on), Load site icons (off), and sites never tracked. Saved now; nothing is tracked until B1.
- **✦ What powers it**: Lookout, Apple Intelligence, and Robi status, read without starting anything. Suggest files for the window in front, Show "fits here" on the tile, and the Helpers (captions, Threads, folder suggestions, sensitive guard, hide noise, drag memory with **Forget**). Saved now; the providers arrive with phase B.
- **History**: the item count and **Clear History…** (files, Favorites, and Smart Filters stay).

Search finds the section by its name and keywords such as downloads, screenshots, shortcut, and web links.

## Privacy

- The history stays on the Mac, in DOKK's Application Support folder. Nothing in phase A leaves the Mac.
- Spotlight metadata needs no permission. Protected folders are read only after you allow them, from a button you press.
- Download pages are stored without query or fragment. Link tracking (B1) stores only URL, title, time, and caption, never private windows, and strips tokens.
- Ask Robi (B2) sends only the files you ask about, with your key, and only when you ask.
- Analytics (phase C) will count feature use without names, paths, URLs, hosts, contents, query text, app names, or bundle identifiers.

## Known limitations

- A URL dragged from a browser onto the **tile** is not kept; drop it on the panel. The dock's drop routing reads file URLs only.
- macOS does not reveal a drop's destination app, so the sensitive and version questions run at drag start and stop the drag; you drag again after answering.
- The tile's ✦ pill refreshes on app activation only; window switches inside one app need phase B1's Accessibility observer.
- A folder granted once and later reset with `tccutil` still counts as allowed, so the watcher could then make macOS ask again. Remove and re-add the folder to reset what DOKK remembers.
- Items moved or renamed outside Flix Files keep their old path until Spotlight or the watcher reports the new one; the old row stays until removed.
- App activations are recorded at most every five minutes per app, so a quick switch back does not move the app up.
- `FlixShortcutCombo` names keys from the current keyboard layout when the recorder draws them; a layout change shows the new layout's character for the same key.

## Analytics

Planned for phase C. Phase A only adds `flix` to the `settings_viewed` section values, which the new Settings section requires.

## Not yet exercised by hand

Phase A was built and its tests compiled; the app was not launched and the tests were not run. None of the following has been seen on screen: the tile and its badge, pop, and Option-drag; the panel's spring, stepping aside, and closing after a drop; the shortcut at the pointer; the menu bar item; Quick Look; drops on favorites, the panel, and the tile; the folder access card and prompts; the Settings page and recorder; Reduce Motion and Reduce Transparency; multiple displays, Spaces, full-screen apps, and sleep. The [acceptance checklist](ACCEPTANCE.md#dee-163-flix-files) lists them.
