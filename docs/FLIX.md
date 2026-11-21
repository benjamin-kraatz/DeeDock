# Flix Files

Flix Files (DEE-163) is an activity stream of what you opened, downloaded, saved, and screenshotted, built to be dragged from. Its home is a dock tile; the panel opens above the tile, at the pointer with Control-Option-Command-F, or under an optional menu bar item. The approved designs are [`mockups/flix-files-v2.html`](mockups/flix-files-v2.html) (the concept) and [`mockups/flix-files-ai.html`](mockups/flix-files-ai.html) (the target UI with every ✦ feature). How each feature behaves for a person is in the [guide](GUIDE.md#flix-files).

This document covers phase A (the data, sources, tile, panel, drag, settings, and every ✦ surface wired to an inert slot model) and phase B1 (window reading and Fits this window, the tile's pill, upload conversion, the sensitive file guard, and web links). Phase B2's providers and phase C's analytics are planned and marked as such below.

## How it is built

Everything lives in `DeeDock/Flix/`, one responsibility per file.

| Folder | What it holds |
| --- | --- |
| `Coordination/` | `FlixCoordinator` (owned by `DockCoordinator`; lifecycle, sources, open and close, drags), `FlixContextServices` (phase B1's owner), `FlixTileState` (what every tile draws), `FlixDockItem`, `FlixFrontmostContext+Capture` |
| `Models/` | `FlixItem` and `FlixActivityEvent`, `FlixActivity`, `FlixItemKind`, `FlixLink`, `FlixFilter`, `FlixSmartFilter` and its rules, `FlixFavorite`, `FlixTimeGroup`, `FlixPaths` |
| `History/` | `FlixHistoryDocument` (the merge rules), `FlixLibraryDocument` (Favorites, Smart Filters), `FlixHistory` (the observable store), `FlixJSONFile` (debounced atomic writes off the main actor) |
| `Sources/` | `FlixSpotlightSource`, `FlixFolderWatcher` (FSEvents), `FlixNoiseRules`, `FlixReadPolicy` |
| `Intelligence/` | `FlixIntelligence` (the slot model), the provider protocols, the slot values, live engine status; B1's `Window/` (reader chain, demand, rules, Apple Intelligence, app categories, front-window observer), `Fits/` (scoring, ranking, provider), `Conversion/` (planner, converter, prepared copies, drag hooks), `Sensitive/` (rules, scanner, guard) |
| `Links/` | Web links: `FlixURLSanitizer`, `FlixSiteExclusions`, `FlixWebDocuments`, `FlixBrowserCatalog`, `FlixBrowserPageReader`, `FlixLinkTracker`, `FlixLinkRelations`, `FlixSiteIconStore` |
| `Shortcut/` | `FlixShortcut` (Carbon hot key ID 19), `FlixShortcutCombo`, `FlixShortcutConflict`, the recorder |
| `Panel/` | `FlixPanelController` (window), `FlixPanelGeometry`, `FlixPanelState` with its commands and keys, `FlixListBuilder`, `FlixFileActions`, `FlixQuickLook` |
| `Drag/` | `FlixDragSession` (`NSDraggingSource`) |
| `Views/` | Panel, sidebar, list, rows, cards, sheets, footer, tile, links (`FlixSavePageCard`, `FlixSiteIconView`), and shared pieces, with previews over `FlixPreviewData` |
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

Two hooks run at drag start, because macOS never tells a drag source where the drop will land:

- **Substitution.** `FlixIntelligence.dragPlan(for:context:)` asks `FlixDragIntercepting.plan(for:context:fits:)`. Its `substitutions` replace an item's file on the pasteboard (a PDF made from an image for a PDF-only portal), and its `label` is drawn under the first drag icon (`FlixDragLabelImage`). It is synchronous, so conversions must exist already; browsers read file URLs, not promises.
- **Confirmation.** `FlixIntelligence.dropConfirmation(for:context:)` asks `FlixDragIntercepting.confirmation(for:context:)`, then falls back to phase A's own rules: an item annotated as sensitive (while the guard is on, and only while no drag provider is installed, since B1's provider asks only for outside targets), then an older version with a newer one in the history. A question stops the drag and shows a dialog in the panel; answering lets the next drag of the same items go ahead for 30 seconds ("Drag it again to send it"). A tile drag that needs a question opens the panel with it.

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

Link items are recorded with `flix.history.record(_:)` and a `FlixActivityEvent` whose `link` is set, whose kind is `.link`, and whose activity is `.link`. Rows draw them with a site monogram and the host.

Three additions serve phase B1 and are open to B2:

- `FlixIntelligence.reviseAnnotation(for:_:)` changes one item's annotation in place. The sensitive guard writes its verdicts through it as they arrive. The sensitive fields (`isSensitive`, `sensitiveReason`) belong to the guard: when the coalesced `FlixAnnotationProviding` pass merges fresh annotations, it keeps them.
- `FlixIntelligence.slotsChanged` fires when the tile's pill or an annotation changes, so the coordinator redraws the tile (`FlixCoordinator.refreshTile()`), which is not a SwiftUI observer of the slot model.
- `FlixContextServices.start(with:)` installs its providers by mutating `intelligence.providers` (`fits`, `drag`) and leaves every other slot as it found it. Other phases should install theirs the same way.

## Window reading and Fits this window

`FlixContextServices` (phase B1) owns the parts below. `FlixCoordinator.live()` creates it; the coordinator calls it on start, stop, settings changes, history changes, recorded events, the panel opening, and drops. Previews and tests run without it.

### Reading the window

`FlixFrontmostContext.capture` records the app and window in front before the panel takes focus. When the panel opens, `FlixIntelligence.readWindow` asks `FlixFitsProvider.fits(for:candidates:progress:)`, which runs `FlixWindowReader`'s chain and reports each step, so the card's chain label and shimmer follow along:

1. **Accessibility**: `RobiWindowText.read` on the app's focused window, 0.6 seconds and 12,000 characters at most. Electron and Chromium apps build their web tree only for assistive apps, so `RobiWebAccessibility.enable` turns it on for this one read and `restore` turns it off straight after, cancelled or not. Skipped without Accessibility permission.
2. **Vision**: when Accessibility found too little, `RobiCapture.image(windowID:)` captures that one window and `recognizeText` reads it. The window number is the window-server window whose bounds match the app's focused accessibility window (both in global top-left points), else the one the capture recorded. Skipped without Screen Recording (`CGPreflightScreenCaptureAccess`, which never asks). The picture stays in memory.
3. **Apple Intelligence**: when Vision also found too little and the system model is available with the `.vision` capability, the picture itself goes to the model.

"Too little" is `FlixWindowTextPolicy`: fewer than eight words of three or more letters, about one sentence. Toolbar labels count, which is why the bar is a sentence and not a word.

### Understanding it

`FlixDemandInterpreter` asks Apple Intelligence (a `@Generable` `GeneratedWindowDemand`: wanted items with the window's own phrase and name keywords, accepted file types, a size limit, and the page kind) with a fresh session, greedy sampling, 320 tokens, and a 10-second limit. The window text is untrusted and the instructions say so. Without Apple Intelligence, or when it fails, `FlixDemandFallbackParser` applies plain rules: the objects of request verbs ("attach", "upload", "send", "anhängen", "hochladen"…, with German's verb-last order), type words on a line with a limit word ("PDF only", "Nur PDF"), size limits ("max 5 MB", "bis zu 1,5 GB"), and upload words for the page kind. The app's category (`FlixAppCategory`, from Launch Services' `https:` and `mailto:` handlers and `LSApplicationCategoryType`, never the name) says mail or chat.

These Apple Intelligence calls are not sent to AI observability: their input is the window's text or picture. Phase C can add a count-only capture once AI observability has a per-call content opt-out.

### Matching

`FlixFitRanker` scores the newest 1,500 items against each wanted phrase with a `FlixFitScoring`. Today that is `FlixKeywordFitScorer`: the phrase's keywords against the item's name (split on separators and case changes), phase B2's caption and facts, its folder, and its source host, with English and German synonyms ("agreement" finds "Vertrag"), word starts and ends for compounds, kind words ("screenshot", "photo") matched against the item's kind, and time words ("this month") against its date. A kind or time word alone never matches, so "the moodboard" is not answered by any picture. Scores below 0.5 are dropped. Each phrase first gets its best item, then the best remaining scores fill up to three. Upload pages skip folders, apps, and links, and every page skips files it would refuse that no conversion can fix. Lookout's semantic scoring can replace the keyword scorer behind the same protocol once Lookout exposes text and file vectors (phase B2's accessors); none exists yet.

Ranking runs off the main actor. Readings are cached per `FlixWindowKey` (process, window number, accessibility title), up to 24 windows, so opening the panel again on the same window only re-ranks, and a new page or conversation reads afresh. The card's label is the page's host in a browser (`FlixBrowserPageReader`, read for the label only), else "App · title".

### The tile's pill

`FlixFrontWindowObserver` keeps one `AXObserver` on the frontmost app for focused-window and main-window changes and on its focused window for title changes, plus NSWorkspace's activation notification. Bursts settle for 350 ms. Without Accessibility permission only app switches arrive. It runs only while **Show "fits here" on the tile** or **Track web links** is on, and `stop()` removes the run-loop source, the notifications, and the workspace observer. On each change, `FlixFitsProvider.tileFitCount` reads the window's accessibility text without turning on any web tree, applies the plain rules (never a model, never a capture), and counts the fits. A complete panel reading of the same window is used when cached.

## Upload conversion

When a window's demand has accepted types or a size limit, `FlixConversionPlanner` decides per item from its type and size, without reading it:

| Original | Window takes | Result |
| --- | --- | --- |
| A picture ImageIO reads (HEIC, PNG, TIFF, WebP, JPEG, GIF…) | PDF | One-page PDF wrapping a JPEG (passed through, so the PDF is barely larger) |
| That picture | JPEG or PNG, not PDF | JPEG, else PNG |
| A picture over the limit | its type or JPEG | Scaled down (and re-compressed for JPEG) until it fits |
| RTF, RTFD, plain text, Markdown, HTML, Word `.docx`/`.doc`, OpenDocument text | PDF | A4 pages laid out with Core Text, 54-point margins |
| Pages, Numbers, Keynote, a PDF over the limit, a zip, anything else | — | Unchanged; not suggested in Fits |

`FlixConversionStore` makes the copies before a drag: as soon as a window's demand is known it converts the Fits rows, the selected rows, and the first six rows of the list (on a tile reading, the newest item), two at a time, off the main actor, in tasks it owns. Only files `FlixReadPolicy` allows are read. Copies go to `…/T/DOKK Flix Conversions/<random>/<original name>.<ext>`; copies older than two hours are removed when more are prepared, and the folder is emptied when Flix Files starts and stops. A copy is used only while the original's modification date still matches.

At drag start `FlixDragInterceptor.plan` substitutes the ready copies and labels the drag ("✦ Upload as PDF · 1.2 MB", "✦ Upload as PDF · 2 converted", "✦ Upload smaller · 4.1 MB", "✦ 3 converted for upload"). A Fits row shows the same copy as a chip ("as PDF · 1.2 MB"), which appears when its copy is ready (`FlixConversionStore.version` is observed). An item whose copy is not ready goes out unchanged. Markdown keeps its inline bold, italic, and code but not headings; pictures inside RTFD and Word files are not drawn; HTML is imported on the main thread, which AppKit requires, and only up to 1.5 MB. Copies carry no metadata (no location, no camera).

## Sensitive file guard

`FlixSensitiveGuard` checks files once, in the background, while **Sensitive file guard** is on. Every history change queues new files (images, screenshots, documents, others), newest first, at most 300 per pass; one worker task reads one file at a time at utility priority. Verdicts are cached by path and modification date in `sensitive.json` next to the history; a file written after its check is checked again. Only files `FlixReadPolicy` allows are read, so the guard never makes macOS ask for folder access.

`FlixSensitiveScanner` stops at the first verdict: the name (`.pem`, `.key`, `.p12`, `.kdbx`, `.keychain-db`, `id_rsa`, `.env`, "passwords"…); text (plain text up to 256 KB, a PDF's first three pages, RTF and Word documents); Vision text recognition on pictures and on a scanned PDF's first page; and, for a picture with at least two lines of text that no rule matched, Apple Intelligence's look at it (identity document, bank details, secret, or something else; 12 seconds at most, not sent to AI observability). `FlixSensitiveRules` holds the text rules: a passport or ID machine-readable zone, two ID words (English, German, French), an IBAN that passes its mod-97 check, two bank words ("account number", "routing number", "BIC", "Kontonummer"…), a Luhn-valid card number next to "card", and PEM, OpenSSH, PGP, and PuTTY key markers.

Verdicts reach `FlixIntelligence.reviseAnnotation`, which sets `isSensitive` and `sensitiveReason`; rows, the tile (`refreshTile`), and VoiceOver read them. Switching the guard off clears every blur it set. At drag start `FlixDragInterceptor.confirmation` asks only when the window in front belongs to a browser, a mail app, or a chat app (`FlixAppCategory.isOutside`); a drop into Finder or another app on the Mac asks nothing. The dialog offers **Send Anyway**, **Not Sensitive** (stored by path in `sensitive.json`; that file is never flagged again, even after it changes), and **Cancel**.

## Web links

`FlixLinkTracker` does nothing while **Track web links** is off (the default). While it is on:

| Trigger | When | Browsers |
| --- | --- | --- |
| Download page | A download arrives with `kMDItemWhereFroms` (already reduced to scheme, host, and path) | Any |
| Page you dropped a file into | A Flix drop outside succeeded while that browser's window was in front | Automatic-tracking browsers |
| Web document | Google Docs/Sheets/Slides, Figma, Notion, Linear, Office 365, or Atlassian page in front for 30 s (`FlixWebDocuments`) | Automatic-tracking browsers |
| Pages you read (own switch) | Any page in front for 2 minutes with keyboard or pointer input in the last minute (`CGEventSource.secondsSinceLastEventType`) | Automatic-tracking browsers |
| Save this page, URL dropped on the panel | You press **Save** or drop a URL | Any, private or not, any site |

A browser is an app that opens `https:` addresses (Launch Services). Pages are read through Accessibility only when the observer reports a window change while a browser is in front, and again when a dwell ends, to confirm the same page is still showing; nothing polls, and the dwell timers are single sleeping tasks cancelled by the next change. `FlixBrowserPageReader` walks at most 700 elements or 0.3 seconds of the focused window, off the main actor, and never sets `AXEnhancedUserInterface`. The address comes from a web area's `AXURL`, else from the first text field whose value looks like an address (the omnibox).

Everything automatic needs a window that reads as **normal**: no private marker ("Incognito", "Inkognito", "InPrivate", "Private Browsing", "Privater Modus", or the whole word "Private"/"Privat"…) in the title or any toolbar label, and, for Chromium and Firefox, enough of the toolbar read (12 elements and an address) to rule one out. Anything less is unknown and is treated as private.

| Browser | Address | Private window check | Automatic tracking |
| --- | --- | --- | --- |
| Safari, Safari Technology Preview | Web area `AXURL` | None found that DOKK could verify | Off: download pages, saves, and URL drops only |
| Chrome, Edge, Brave, Vivaldi, Opera, Chromium, Helium, Arc, Comet, other Chromium builds | Omnibox value (scheme added), or `AXURL` when the web tree is already on | Marker in the toolbar (Chrome's "Incognito" avatar, Edge's "InPrivate", Brave's "Private") or title | On; unverified by hand, including localized UIs and Arc's sidebar layout |
| Firefox, Zen, LibreWolf, Floorp, Waterfox | URL bar value, or `AXURL` | Marker in the title or toolbar ("Private Browsing", "Privater Modus") | On; unverified by hand |
| Other browsers (Orion, DuckDuckGo, …) | Web area `AXURL` or an address field | None | Off: download pages, saves, and URL drops only |

`FlixURLSanitizer` cleans every address: user and password, the fragment, credential and session keys (`token`, `access_token`, `code`, `state`, `session`, `sid`, `sig`, `signature`, `key`, `auth`, `password`, `Expires`, `Key-Pair-Id`, `Policy`…), signed-storage prefixes (`X-Amz-*`, `X-Goog-*`, `X-Ms-*`), Azure SAS parameters once a signature is present, and click trackers (`utm_*`, `fbclid`, `gclid`…). Excluded sites (`FlixSiteExclusions`) are the person's list (host suffix on label boundaries) and, while **Leave out banking and health sites** is on, a built-in list of banks, payment services, brokers, insurers, tax and health portals, plus host labels containing banking or health words in English and German. They apply to automatic tracking only.

A link item stores the address, the title, the browser's bundle identifier, and the time; one item per address. `links.json` maps page addresses to the Flix items dropped on them, for "↑ You sent 2 files here"; "Source of “Invoice.pdf”" is derived from the items whose download page is that address. Link rows draw a monogram (`FlixSiteIconView`); with **Load site icons** on, `FlixSiteIconStore` asks `https://<host>/favicon.ico` once per host with an ephemeral session (no cookies, 5-second timeout, 256 KB cap) and keeps the icon in DOKK's caches folder. A link opens in the browser it came from and drags out as a web address, which Finder saves as `.webloc`. The sidebar's **Links** (activity) and **Web documents** (kind) filters list them; both appear while tracking is on or links exist.

With a browser in front and tracking on, the panel's **Save this page** card (`FlixSavePageCard`) reads that browser's page when the panel opens and keeps it on **Save**.

## Settings

**Settings → Flix Files** is its own section under Features, like Lookout and Plugins:

- **Flix Files** on or off. Off removes the tile, the menu bar item, and the shortcut, and stops every source.
- **Where it lives**: Show in the dock (on), Show in the menu bar (off), Keyboard shortcut with a recorder (Control-Option-Command-F). The recorder needs Control, Option, or Command (function keys excepted), refuses DOKK's own shortcuts and app-wide commands, and warns about Spotlight's and launchers' combinations. An orange row appears when another app holds the combination. Recording pauses the shortcut so pressing the current combination records it.
- **When Flix Files opens**: Do nothing, Copy newest, or Copy its path. **After you drag something out**: Close or Stay open.
- **What it tracks**: Files you open, New, saved, and downloaded files, Folders, Apps, and the watched folders with their access and **Allow…**.
- **Web links**: Track web links (off), Pages you read (off, its own opt-in), Leave out banking and health sites (on), Load site icons (off), and sites never tracked. While tracking is on, a note explains Safari's limit, and another appears without Accessibility permission.
- **✦ What powers it**: Lookout, Apple Intelligence, and Robi status, read without starting anything. Suggest files for the window in front, Show "fits here" on the tile, and the Helpers (captions, Threads, folder suggestions, sensitive guard, hide noise, drag memory with **Forget**). The window, tile, and sensitive switches work now (phase B1); captions, Threads, folders, and drag memory arrive with phase B2.
- **History**: the item count and **Clear History…** (files, Favorites, and Smart Filters stay).

Search finds the section by its name and keywords such as downloads, screenshots, shortcut, and web links.

## Privacy

- The history stays on the Mac, in DOKK's Application Support folder. Nothing in phases A and B1 leaves the Mac, except a site icon request while **Load site icons** is on.
- Spotlight metadata needs no permission. Protected folders are read only after you allow them, from a button you press. The sensitive guard and conversions read only what that policy allows.
- Window reading needs Accessibility (text) and Screen Recording (a picture of that one window); Flix Files never asks for either and skips the step without it. The picture and the text stay in memory for that reading; only the demand derived from them is cached, until the window changes. Apple Intelligence runs on the Mac, and these calls are not sent to AI observability.
- Download pages are stored without query or fragment. Link tracking stores only the address (tokens and session codes removed), title, browser, and time, never a private or unknown window, never an excluded site, and never page contents.
- The sensitive guard keeps a verdict per file path in `sensitive.json`, and the paths you marked **Not Sensitive**.
- Ask Robi (B2) sends only the files you ask about, with your key, and only when you ask.
- Analytics (phase C) will count feature use without names, paths, URLs, hosts, contents, query text, app names, or bundle identifiers.

## Known limitations

- A URL dragged from a browser onto the **tile** is not kept; drop it on the panel. The dock's drop routing reads file URLs only.
- macOS does not reveal a drop's destination app, so the sensitive and version questions run at drag start and stop the drag; you drag again after answering.
- The tile's ✦ pill follows window and title changes only with Accessibility permission; without it, only app switches refresh it. A page that changes its address without changing its title (some single-page apps) is not noticed until the next title change, for the pill and for web links.
- A conversion starts when the window's limits are known (the panel's reading or the tile's count). A row dragged before its copy is ready goes out unchanged. Copies of rows beyond the first six and the selection are not made ahead.
- Converted PDFs from text documents use Core Text: headings in Markdown stay as written, and pictures inside RTFD or Word files are left out. Pages, Numbers, and Keynote files are never converted.
- The fallback rules read English and German. Other languages need Apple Intelligence to find what a window asks for.
- Safari has no private-window signal DOKK could verify, so Safari pages are kept only by deliberate saves and as download pages. The private-window checks for Chromium and Firefox browsers rely on visible labels and have not been verified by hand, including in other UI languages; a label DOKK does not know would make a private window look normal.
- A download's page comes from the file's own metadata; macOS does not say whether the download happened in a private window, so that page can be listed even then (while web links are on). Removing the link row removes it.
- The sensitive guard checks at most 300 files per history change and reads the newest first; a large backlog takes several changes to finish. A file it cannot read (a protected folder not allowed) is never flagged.
- Fits scoring matches words, not meaning, until Lookout exposes embeddings to Flix Files.
- A folder granted once and later reset with `tccutil` still counts as allowed, so the watcher could then make macOS ask again. Remove and re-add the folder to reset what DOKK remembers.
- Items moved or renamed outside Flix Files keep their old path until Spotlight or the watcher reports the new one; the old row stays until removed.
- App activations are recorded at most every five minutes per app, so a quick switch back does not move the app up.
- `FlixShortcutCombo` names keys from the current keyboard layout when the recorder draws them; a layout change shows the new layout's character for the same key.

## Analytics

Planned for phase C. Phase A only adds `flix` to the `settings_viewed` section values, which the new Settings section requires.

## Not yet exercised by hand

Phases A and B1 were built and their tests compiled; the app was not launched and the tests were not run. Phase B1's window reading, captures, Apple Intelligence calls, conversions, sensitive checks, browser reading and private-window checks, link triggers, Save this page, and the drag labels have not run against a real window or browser. None of the following has been seen on screen either: the tile and its badge, pop, and Option-drag; the panel's spring, stepping aside, and closing after a drop; the shortcut at the pointer; the menu bar item; Quick Look; drops on favorites, the panel, and the tile; the folder access card and prompts; the Settings page and recorder; Reduce Motion and Reduce Transparency; multiple displays, Spaces, full-screen apps, and sleep. The [acceptance checklist](ACCEPTANCE.md#dee-163-flix-files) lists them.
