# Flix Files

Flix Files (DEE-163) is an activity stream of what you opened, downloaded, saved, and screenshotted, built to be dragged from. Its home is a dock tile; the panel opens above the tile, at the pointer with Control-Option-Command-F, or under an optional menu bar item. The approved designs are [`mockups/flix-files-v2.html`](mockups/flix-files-v2.html) (the concept) and [`mockups/flix-files-ai.html`](mockups/flix-files-ai.html) (the target UI with every ✦ feature). How each feature behaves for a person is in the [guide](GUIDE.md#flix-files).

This document covers phase A (the data, sources, tile, panel, drag, settings, and every ✦ surface wired to a slot model) and phase B2's providers, in [Phase B2: intelligence](#phase-b2-intelligence). Phase B1 (Fits this window, conversions, the sensitive guard, link tracking) and analytics (C) are described with their own work.

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

## Phase B2: intelligence

`FlixCoordinator.installSmartProviders(lookout:robi:)` (`Intelligence/FlixCoordinator+SmartProviders.swift`), called by `DockCoordinator.configureFlix()` before `flix.start()`, sets the search, threads, annotations, morning, similarity, smartFilters, tidy, robi, and dragMemory slots on the existing `providers` value, leaving phase B1's `fits` and `drag` alone. Its stop closure (`FlixCoordinator.stopProviders`) cancels the providers' workers and writes their caches when Flix Files stops.

| Folder | What it holds |
| --- | --- |
| `Intelligence/Shared/` | `FlixSmartServices` (what the providers share), `FlixSemanticIndex` (Lookout), `FlixSemanticScoring` (cosine, centroids, ranking, thresholds), `FlixTopicCache`, `FlixLanguageModel` (every Apple Intelligence call), `FlixContentReader` (bounded file reading), `FlixWords` |
| `Intelligence/Search/` | `FlixQueryParser` (rules, EN and DE), `FlixQueryModel` (`@Generable` parse), `FlixQueryTokens`, `FlixSearchMatcher`, `FlixSearchProvider` |
| `Intelligence/Threads/` | `FlixThreadClusterer`, `FlixThreadNamer`, `FlixThreadProvider` |
| `Intelligence/Annotations/` | `FlixFileNaming` (cryptic names, safe renames), `FlixFactExtractor`, `FlixFileAnalyzer`, `FlixAnalysisStore`, `FlixFolderSuggester`, `FlixVersionFamilies`, `FlixAnnotationProvider` |
| `Intelligence/Tidy/`, `SmartFilters/`, `Morning/`, `Similarity/`, `DragMemory/`, `Robi/` | One provider each, with the Smart Filter builder and the drag memory model |

### Engines and fallbacks

- **Lookout** (`FlixSemanticIndex`) answers only while it runs (set up, on, started). Three narrow accessors on `LookoutEngine` serve it and change nothing the Hub shows: `embed(text:)` (the query encoder), `storedVectors(forPaths:)` (each file's segment vectors averaged, text segments preferred, at most 8 per modality, read from the store without loading the in-memory vectors; `Searcher.fileVectors`), and `contentMatches(for:limit:)` (Lookout's own hybrid search; a meaning search loads the vectors, which are released 120 s later unless the Files tab shows). Vectors are cached by path; "no vector" answers are dropped whenever Lookout reports new vectors.
- **Apple Intelligence** (`FlixLanguageModel`): a fresh session per call, greedy sampling, a timeout (3.5 s for search, 5 s for Smart Filters, 6 s for the morning card, 12–15 s in the background), silent failure. Pictures go to the model only when it reports `.vision`.
- **Without Lookout**: search matches names, captions, and folders; Threads group by time, working folder, and shared name words; folders are suggested by name and kind rules; More like this uses the same folder and kind.
- **Without Apple Intelligence**: search and Smart Filters use the rules; Threads keep folder or word names; no captions or renames; facts come from the deterministic extractor only.
- **`FlixSemanticScoring`** holds every threshold (related files 0.72 text / 0.82 pictures, folder fit 0.62 with a 0.03 margin, More like this 0.55 and z ≥ 0.8). They are first guesses, untuned. Phase B1's `FlixFitScoring` can adopt it: embed the window's wanted phrase with `FlixSemanticIndex.embed(_:)`, read candidate vectors with `vectors(for:)`, rank with `ranked(_:against:floor:minimumZ:limit:)` using its own lower floor (text-to-file scores run lower), and blend with the keyword score, keeping keywords when Lookout is off.

### Search in plain words

The panel debounces typing (420 ms); `FlixIntelligence` cancels the previous search. `FlixQueryModel` asks Apple Intelligence for `FlixGeneratedQuery` (activity, kinds, extension, days, minimum amount, folder, site, topic) and keeps only what the sentence backs: a folder, site, or amount must appear in it, and with a rules topic the model may only narrow it. Fields the model leaves empty come from `FlixQueryParser`, which knows English and German words for activity ("sent", "geschickt"), kinds, extensions, times ("last week", "gestern", "letzten 10 Tagen"), amounts ("over €1,000", "über 1.000 €"), places ("in Downloads"), and hosts.

`FlixQueryTokens` turns the fields into tokens, each a Smart Filter rule. A new rule, `.amountOver`, is answered from the totals the analysis read, through the same cached lookup as `.about`. `FlixSearchMatcher` applies every rule; the topic matches by name, or **by meaning** through the caption, the folders, the download host, or Lookout's content matches, which are also kept in `FlixTopicCache` so removing a token (which re-evaluates the rules) keeps the meaning matches. When nothing has every topic word, the search widens to any distinctive word in the name. A single word without Lookout is left to plain name search.

### Threads

`FlixThreadProvider` clusters the last seven days (files and folders, no apps, links, or noise; at most 300 items) off the main actor. Two items link within 72 hours when their Lookout vectors are related or their names share a distinctive word, or within 12 hours when they share a working folder that is not a catch-all one (home, Desktop, Documents, Downloads, Pictures, Movies, Music, iCloud Drive). Connected groups of three or more are threads; at most eight, 40 members each, newest first.

Identity: a cluster keeps the previous thread it overlaps most when they share at least a third of their members (Jaccard); otherwise it is named `thread-<oldest member's id>`. Threads are saved in `threads.json`. Names start as the most common working folder or shared word with an emoji for the kind; the provider's worker then asks Apple Intelligence (`FlixGeneratedThread`: name, emoji, summary) from member names, captions, and folders, one thread at a time, and again when fewer than 60 % of the members are the ones it named.

### Annotations

`FlixAnnotationProvider` answers every history pass quickly from caches and does its slow work in its own worker:

- **Versions** (`FlixVersionFamilies`): names that match once version marks are removed (`v3`, `version 2`, `rev 4`, `(2)`, final, signed, draft, copy, Fassung, Entwurf, unterschrieben…), of the same broad kind, with at least one mark. Cryptic names never form families. With vectors, a member clearly unrelated (cosine below 0.5) to the newest one leaves. Rank: signed > final > plain > draft, then the version number, then the date. Phase A's version pill and "newer version" question read the result.
- **Folder suggestions** (`FlixFolderSuggester`), for files directly in Downloads: the nearest centroid among folders holding at least two history items (outside Downloads, the Desktop, and home); without vectors, a folder whose name words all appear in the file's name or caption, then finance and picture folders.
- **Captions, renames, facts**: the worker reads at most 40 waiting files, newest first, one at a time, only paths `FlixReadPolicy` allows, never during a drag (`FlixSmartServices.waitWhileDragging()`, observation, no polling). `FlixContentReader` reads the first four PDF pages, 64 KB of text files, Office and RTF documents through AppKit's importers, Spotlight's page count, and a picture downscaled to 1,024 px; at most 6,000 characters. `FlixFactExtractor` finds due and valid-until dates, totals with currency, signature and paid wording, and page or slide counts. Apple Intelligence is asked for cryptic names (`FlixFileNaming.isCryptic`: screenshots, camera names, `document (3)`, hashes, digits) and for documents that read like invoices, quotes, contracts, or forms: `FlixGeneratedDocument` (caption, file name, due date, total, currency, signature) or `FlixGeneratedPicture`. Model facts are kept only when the text backs them. Captions and renames show only while the name is still cryptic; `FlixFileNaming.sanitizedName` keeps the extension, strips separators, colons, control characters, and leading dots, caps the stem at 80 characters, and numbers around names already in the folder.
- **Caching**: `analysis.json`, by path, invalidated by modification date and size, at most 3,000 records. A record made without the model is redone once the model is ready; a failed model call is retried after a day; an unreadable file gets an empty record until it changes. Renames and moves made in Flix Files carry their record along.
- **Sensitive flags and learned noise** are never set or cleared here: the previous values are kept (phase B1 owns the sensitive guard). Noise refinement is not implemented; `FlixNoiseRules` decides.

### Tidy

`FlixTidyProvider` lists items whose names are still cryptic and have a rename suggestion (captions on), or that sit directly in Downloads with a folder suggestion (folder suggestions on), at most 30, from the annotations already computed, so the sheet fills at once. `FlixPanelState.applyTidy` renames, then moves, and its one Undo moves each file back to its original path.

### Smart Filters from a sentence, and the filter tip

`FlixSmartFilterProvider` asks Apple Intelligence for `FlixGeneratedFilter` (name, emoji, kinds, activity, days, folder, site, topic); unlike search, the topic may widen the sentence ("tax stuff" → "invoices, receipts, budget") because it matches by meaning. A folder must be one the history uses. `FlixSmartFilterBuilder` makes the rules: when the topic names such a folder and nothing else constrains it, the filter matches that folder **or** the topic by meaning; otherwise every rule must hold. The proposal waits for Lookout's matches of its topic, so the sheet's count (now evaluated with the semantic lookup) and the new filter agree. Saved filters' `.about` topics are asked again in the background on history passes (`FlixSimilarityProvider.warmSmartFilters`, at most every ten minutes per topic).

The **filter tip** comes from drag memory's open counts: a working folder opened in the same part of the day (morning 5–12, afternoon 12–18, evening 18–24) on three different days of the last 14 earns one tip, offered once and never again, and never for catch-all folders or a folder that already has a location Smart Filter.

### Where was I?

`FlixMorningProvider` runs on the first open of a day (remembered in `flix.morning.lastShownDay`, so a relaunch doesn't repeat it), when the last day with activity is at most four days back and had at least three items. Apple Intelligence writes one or two sentences from the threads' names, summaries, and member names; a message naming none of the threads is dropped for the fallback, which names up to two threads or the newest file. Actions: **Reopen** the main thread's files (at most ten) and show the second thread.

### More like this

`FlixSimilarityProvider.similar` ranks history items by their Lookout vectors against the item's own (like with like), at most 12. Without a vector it falls back to the same kind with a shared name word, then the same folder and kind. It stays inside the history.

### Drag memory

`FlixDragMemoryProvider` counts each accepted drop out of the panel by file kind (`pdf`, `image`, `spreadsheet`, …) against the app that was in front when the panel opened (bundle identifier). Rows then show "↺ you've sent PDFs here before" while that app is in front; after three drops of one kind, a toast says what Flix Files noticed (right away when the panel stays open, otherwise on the next open). `FlixIntelligence.likelyItem(for:among:)` names the newest item of the kind usually sent to the app in front, a ranking hint for phase B1's Fits card. Tile drags carry no context and are not counted. **Forget** empties `memory.json`, drops and opens alike.

### Ask Robi

`FlixRobiProvider` follows Robi's own answer model. With Claude, the key is read from the Keychain only when a question is asked; with no key the answer is "Add a Claude key in Robi settings to ask about files." With the on-device model, the answer is made on the Mac and the sheet says so. Suggested questions depend on the selection: totals and due dates for invoices, what changed for versions, what is shown for pictures, otherwise summarize, what they share, and a draft message. At most six files are read, 12,000 characters each for Claude and 1,500 for the on-device model, plus one picture per image for Claude (Vision text for the on-device model); protected folders DOKK may not read contribute only their name. `RobiAgent.answer(question:about:model:update:)` (`Robi/Answering/RobiFileQuestion.swift`) is the narrow entry point: no tools, files quoted as untrusted data, at most four pictures, 700 answer tokens, and AI observability with `includesContent: false`.

### Checks by hand

The [acceptance checklist](ACCEPTANCE.md#phase-b2-intelligence) lists them. The thresholds above and the AI prompts need tuning against real files; none of it has run yet.

## Settings

**Settings → Flix Files** is its own section under Features, like Lookout and Plugins:

- **Flix Files** on or off. Off removes the tile, the menu bar item, and the shortcut, and stops every source.
- **Where it lives**: Show in the dock (on), Show in the menu bar (off), Keyboard shortcut with a recorder (Control-Option-Command-F). The recorder needs Control, Option, or Command (function keys excepted), refuses DOKK's own shortcuts and app-wide commands, and warns about Spotlight's and launchers' combinations. An orange row appears when another app holds the combination. Recording pauses the shortcut so pressing the current combination records it.
- **When Flix Files opens**: Do nothing, Copy newest, or Copy its path. **After you drag something out**: Close or Stay open.
- **What it tracks**: Files you open, New, saved, and downloaded files, Folders, Apps, and the watched folders with their access and **Allow…**.
- **Web links** (planned for phase B1): Track web links (off), Pages you read (off, its own opt-in), Leave out banking and health sites (on), Load site icons (off), and sites never tracked. Saved now; nothing is tracked until B1.
- **✦ What powers it**: Lookout, Apple Intelligence, and Robi status, read without starting anything. Suggest files for the window in front, Show "fits here" on the tile, and the Helpers (captions, Threads, folder suggestions, sensitive guard, hide noise, drag memory with **Forget**). Phase B2's providers obey them; see below.
- **History**: the item count and **Clear History…** (files, Favorites, and Smart Filters stay).

Search finds the section by its name and keywords such as downloads, screenshots, shortcut, and web links.

## Privacy

- The history stays on the Mac, in DOKK's Application Support folder. Nothing in phase A leaves the Mac.
- Spotlight metadata needs no permission. Protected folders are read only after you allow them, from a button you press.
- Download pages are stored without query or fragment. Link tracking (B1) stores only URL, title, time, and caption, never private windows, and strips tokens.
- Ask Robi sends only the files you ask about, with your question, only when you ask, and only when Robi's settings choose Claude with your key; with the on-device model nothing leaves the Mac. Captions, Threads, facts, search, Smart Filters, and the morning card use Apple Intelligence on the Mac and Lookout's local index.
- Every Flix Files model call reports metadata only to AI observability (`AIObservability.capture(…, includesContent: false)`): span name, model, latency, token counts, and an error type. Prompts, file names, file contents, and answers are never captured.
- What Flix Files learns stays in its Application Support folder: `analysis.json` (captions, names, facts by path), `threads.json` (thread names and members), and `memory.json` (drop counts by file kind and app, opens by folder and part of the day). **Forget** empties `memory.json`.
- Analytics (phase C) will count feature use without names, paths, URLs, hosts, contents, query text, app names, or bundle identifiers.

## Known limitations

- A URL dragged from a browser onto the **tile** is not kept; drop it on the panel. The dock's drop routing reads file URLs only.
- macOS does not reveal a drop's destination app, so the sensitive and version questions run at drag start and stop the drag; you drag again after answering.
- The tile's ✦ pill refreshes on app activation only; window switches inside one app need phase B1's Accessibility observer.
- A folder granted once and later reset with `tccutil` still counts as allowed, so the watcher could then make macOS ask again. Remove and re-add the folder to reset what DOKK remembers.
- Items moved or renamed outside Flix Files keep their old path until Spotlight or the watcher reports the new one; the old row stays until removed.
- App activations are recorded at most every five minutes per app, so a quick switch back does not move the app up.
- `FlixShortcutCombo` names keys from the current keyboard layout when the recorder draws them; a layout change shows the new layout's character for the same key.
- Phase B2's similarity thresholds and prompts are untuned first guesses.
- Captions, facts, and renames exist only for files in folders DOKK may read (allowed watched folders and Lookout's folders). Spreadsheets' sheet counts and Keynote or Pages text are not read; their page or slide count comes from Spotlight when it has one.
- The filter tip counts each item's latest open only, so opens between two history passes of the same file count once. Tips are folder-based; Thread-based tips are not implemented.
- The analysis worker runs one file at a time; a large first history fills captions over minutes, newest first.
- Settings' Robi engine row still reads the Claude key only; with Robi set to the on-device model, Ask Robi works while the row says it needs setup.
## Analytics

Planned for phase C. Phase A only adds `flix` to the `settings_viewed` section values, which the new Settings section requires.

## Not yet exercised by hand

Phase A and phase B2 were built and their tests compiled; the app was not launched and the tests were not run. No Apple Intelligence, Claude, or Lookout call from Flix Files has run. None of the following has been seen on screen: the tile and its badge, pop, and Option-drag; the panel's spring, stepping aside, and closing after a drop; the shortcut at the pointer; the menu bar item; Quick Look; drops on favorites, the panel, and the tile; the folder access card and prompts; the Settings page and recorder; Reduce Motion and Reduce Transparency; multiple displays, Spaces, full-screen apps, and sleep. The [acceptance checklist](ACCEPTANCE.md#dee-163-flix-files) lists them.
