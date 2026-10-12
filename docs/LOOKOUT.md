# Lookout

Lookout is DOKK's on-device search by content. It finds photos, screenshots, PDFs, and documents in folders you choose by what they show or say. A search for "the dog on the beach" finds the photo, whatever the file is called. Lookout lives in the Hub's Files tab. Spotlight's name matches come first, under **Names · Spotlight**, and Lookout's results follow under **Lookout · by content**. A picture or a file Lookout has read can be the query too: drop or paste one into the search field, or use **Find Similar** on a result or a file in the browser, and Lookout finds pictures that look like it and documents about what it shows ([Searching with a picture](#searching-with-a-picture)).

Implemented on `feature/dee-125` for [DEE-125](https://linear.app/d-zwei/issue/DEE-125). [The user guide](GUIDE.md#lookout) describes how Lookout behaves for a person, and [DOKK Hub](HUB.md#search) covers the Files search around it. The [acceptance notes](ACCEPTANCE.md#dee-125-lookout) list what still needs checking by hand. The approved design is the interactive mockup at `docs/mockups/lookout.html`, and for searching with a picture `docs/mockups/lookout-image-search.html`.

Lookout adapts the indexer, the crawl rules, and the ranking of [DigUp](https://github.com/ARahim3/DigUp) (MIT, © 2026 Abdur Rahim). Adapted files say so in their first line.

## How it is built

Lookout runs in three processes. DOKK.app embeds two XPC services in its bundle, and launchd lets only DOKK.app look them up.

| Process | Job | Memory | Lifetime |
| --- | --- | --- | --- |
| `LookoutIndexService` | The index's only writer. Syncs the chosen folders, extracts text, runs Vision OCR, and embeds with the full model at utility QoS. | About 1 GB while it works | Waits about 60 s with the model loaded after it runs out of work, then exits. The next message relaunches it. |
| `LookoutQueryService` | Embeds search queries with the text model at user-initiated QoS, and pictures with the image encoder, which it loads into the same model only for the first search with a picture. | 215 MB, or about 900 MB once a picture was searched with | Loads the text model on its first call and exits 120 s after its last call, which releases the image encoder too. |
| DOKK.app | Reads the index, ranks results, and shows them. | The vectors, about 30 MB per 20,000 | The app's lifetime |

The services never ask for folder access. The index service skips a chosen folder it can't read and reports it as not permitted. It also skips a folder that isn't there, such as one on an unplugged drive, and keeps what it already indexed from it. Searches show none of those files meanwhile, because a file that isn't there can't be opened, previewed, or dragged (`LookoutSearchFilter.requireExisting`). They come back when the drive does, with nothing to read again. The service checks this before every sync, so an ejected drive never looks like a folder whose files were deleted.

Before every sync, the service and the crawler also check each saved folder again where it really leads, with the rules onboarding uses (`Rules.checkRoots`, see [Onboarding](#onboarding)). The root itself is checked, not only the folders inside it. A chosen folder that has since become a link to `~/Library` resolves there and is skipped, and the next configuration drops its files from the index. Folders inside `/private/tmp` and inside the user's temporary folder may be roots, because people keep scratch files there. The rest of `/private` may not.

A sync or **Read everything again** that arrives while reading is paused, or while no app is connected, waits until reading may go on. Resuming syncs first, so changes made during the pause are found (`IndexRequests`).

A new DOKK version may bring a new model. The index then starts over by itself, and file names stay searchable meanwhile.

### App side

The app code is in `DeeDock/Hub/Files/Lookout/`.

- `LookoutEngine` (`Engine/`) puts the parts together. `HubCoordinator` creates one engine for the app's lifetime, and `DockCoordinator` starts it. It runs whether or not the Hub is open, so new files get indexed. It owns both XPC connections, the folder watcher, the mount and wake monitor, and the power policy. It saves `LookoutSettings` as JSON under the `hub.lookout.v1` defaults key and publishes `LookoutStatus` for the status chip and Settings. Under the test host and in previews, `LookoutEngine.live()` returns an inert engine that never starts.
- `LookoutIndexConnection` (`Services/`) sends the configuration, and a pause, again to a relaunched index service.
- `LookoutIndexReader` (`Search/`) is an actor that owns a read-only `IndexStore` and its `Searcher`. SQLite's write-ahead log lets it read while the service writes, so a search never waits for indexing. Vectors load on the first meaning search or when the Files tab appears. While the service adds vectors, the reader reloads them at most every 2 s. They are released 120 s after the Files tab hides or the Hub closes (`LookoutEngine.vectorReleaseDelay`).
- `LookoutPictureSearch` (`Search/`) searches with a picture or with a file's stored vector. It keeps the current request, so a search that couldn't run runs by itself once Lookout is available (a picture dropped before setup, or Lookout turned off and on), and the engine refreshes it when the settings' folders or types change and when the index first appears. A refresh reuses the vector it has. See [Searching with a picture](#searching-with-a-picture).
- `LookoutSearch` (`Search/`) waits 150 ms after the last keystroke. It then publishes keyword hits first, with the last word matched as a prefix because it is probably half typed. Once the query vector arrives, hybrid results replace them. A generation token drops results that arrive late. If the encoder fails, the final results are keyword-only.
- `LookoutFolderWatcher` (`Monitoring/`) reports FSEvents in the chosen folders and ignores hidden files such as `.DS_Store`. The engine waits 2 s after the last change (`LookoutEngine.syncDebounce`), then asks the service to sync. `LookoutMonitor` also asks for a sync when a volume mounts or ejects and after wake. Nothing polls.
- `LookoutPowerPolicy` (`Monitoring/`) decides when the backfill may run. See [Power policy](#power-policy).
- `LookoutProgressTracker` (`Progress/`) turns the statuses into `LookoutEngine.progress`, where reading stands. See [Progress](#progress).

The code both sides share is in `Lookout/`: `Core` holds the index, the crawl rules, the search, and the ranking. `Indexing` holds the extractors, `Embedding` wraps llama.cpp, and `IndexService`, `QueryService`, `ServiceSupport`, and `Bench` hold the two services and the bench.

### Where the data lives

Lookout keeps everything in `~/Library/Application Support/DDock/Lookout/` (`LookoutPaths.standard`). That folder belongs to the Release app, `de.benjaminkraatz.DeeDock`. Every other app identity gets its own folder beside it, named from its bundle identifier: the Debug app, `de.benjaminkraatz.DeeDock.dev`, uses `DDock/Lookout-dev/`. A development build therefore keeps its own index and downloads its own copy of the model. With one shared index, each app's service would prune the folders the other app chose, and deleting from one app could unlink files the other was writing. The services derive the same folder from their own bundle identifier, which is the app's plus `.LookoutIndexService` or `.LookoutQueryService`. The index service also gets the index and model folders in its configuration.

| Path | Contents |
| --- | --- |
| `index.sqlite`, with `-wal` and `-shm` beside it | The index |
| `Models/` | The two model files, each only after its checksum matched |
| `Partial/` | Downloads in progress, as `<name>.partial` |
| `Logs/` | llama.cpp warnings and errors: `index-service.log` and `query-service.log` |

The crawler never walks `~/Library`, so the index can't index itself.

### From a folder to a result

1. The person chooses folders in onboarding or Settings. The engine sends the index service a `LookoutIndexConfiguration` with the folders, the skips, and the locations of the index and the models.
2. The service syncs. `Crawler` walks the folders and reads metadata only, and `Rules` decides what each file is. One Spotlight query per folder adds last-used dates, so recently used files are read first.
3. The indexer extracts text from documents and PDFs and runs Vision OCR on screenshots. It renders PDF pages that have little text. It embeds text, pictures, and rendered pages with EmbeddingGemma 2.
4. The service writes to SQLite: an FTS5 table with Porter stemming over file names, folder names, OCR text, and page and document text, and one 768-dimension float16 vector per segment.
5. `LookoutIndexReader` reads the index, and `Searcher` ranks files and folders.
6. The Files tab lists the hits in the Lookout section with an excerpt, the kind, and why each one matched.

### What gets read

`Rules` and `IndexOptions` decide. Lookout indexes these kinds:

- Documents: `txt`, `text`, `md`, `markdown`, `rtf`, `docx`, `doc`, `odt`, `html`, `htm`, `xhtml`, `rst`, `adoc`, `asciidoc`, `org`, `textile`, `mdx`, `tex`, `latex`, `srt`, `vtt`, `webarchive`, and `rtfd`.
  - Markup (reStructuredText, AsciiDoc, Org, Textile, MDX) is read as it's written, like Markdown.
  - Subtitles (`srt`, `vtt`) keep only what's said: cue numbers, timings, the WebVTT header, `NOTE`, `STYLE` and `REGION` blocks, and formatting tags are left out, and each cue becomes one line.
  - LaTeX loses its comments, its preamble, and its commands. A command's braced argument stays as words (`\section{Results}` reads "Results"), except for commands whose argument is markup or a name, such as `\usepackage`, `\label`, `\cite`, and `\includegraphics`. Lookout doesn't expand macros.
  - A Safari web archive is a property list. Its main resource's HTML, decoded with the encoding it names, goes through the same HTML stripping as `html` files, and so does XHTML. Nothing goes through WebKit or `NSAttributedString`'s HTML import, which must run on the main thread.
  - An `.rtfd` is a package folder. The crawler indexes the package as one document and never walks into it, also where macOS doesn't call it a package. `QueuedFileGate` reads the `TXT.rtf` inside it (see below).
  - All of these but rtf, rtfd, docx, doc, and odt are read by `DocumentText` (`Core/`), so the app's tests reach them. The Cocoa text system reads the rest (`DocExtractor`).
- PDFs: the text of each page. A page with fewer than 200 characters of text is embedded as a rendered image.
- Images whose longer side is at least 256 pixels.
- Screenshots, recognized by macOS's screen-capture attribute or by a name that starts with "Screenshot", "Screen Shot", "CleanShot", or "SCR-". Vision OCR reads their text.

Lookout skips these:

- Source code and data files. Audio and video are ignored, and Spotlight still finds them by name.
- Keys, certificates, and password files, wherever they are.
- Hidden files and folders, bundles (other than `.rtfd` documents), and symbolic links.
- SVG, although macOS calls it a picture: ImageIO can't decode it. It's ignored like any other type Lookout doesn't handle, and not counted as a problem.
- XML, JSON, YAML, CSV, TSV, property lists, logs, and configuration files, as data. EPUB, mail files, and Pages, Numbers, and Keynote documents aren't read either.
- Folders such as `node_modules`, `DerivedData`, and `Pods`, folders whose names end in `.noindex`, and `~/Library`, except iCloud Drive and cloud storage folders chosen as roots.
- iCloud and cloud storage files that aren't downloaded, because reading a placeholder downloads it.
- Code projects, except the screenshots in them.
- Folders of 300 or more images where at least 70% have machine-made names. They look like datasets. A folder the person chose is never treated as one.

The backfill can read a file hours after the crawl queued it, so `QueuedFileGate` checks each file again just before it's read. The stored path must still pass the settings and the crawl's folder rules. The file must be a regular file and not a link, and `lstat` and the opened descriptor must agree. `F_GETPATH` on the descriptor gives where the open file really is, which catches a folder on the way that became a link. Any other path than the stored one must pass the same rules itself and be the queued inode. Paths are never compared by spelling, because on a case-sensitive volume `Notes` linked to its sibling `NOTES` differs only in case. The extractors read the bytes from that descriptor, never the path, so the check and the read can't race. A file whose inode changed is queued again with its new identity. A file that fails a check is skipped, and the next sync settles it.

An `.rtfd` goes through the same checks as a folder on the way: the package must be a real folder and not a link, it's opened with `O_DIRECTORY | O_NOFOLLOW`, `F_GETPATH` must place it where it was found, and its inode is compared with the row's. `TXT.rtf` is then opened inside that descriptor with `openat` and `O_NOFOLLOW`, checked as a regular file with its data on this Mac, and read under the same size cap. The crawl stores the package's inode, so a save that replaces the package is a new file, and the size and date of `TXT.rtf`, so an edit in place reads as a change.

The bytes are copied into memory in 8 MB reads, never memory-mapped. A mapped file that's cut shorter while it's read would crash the index service with SIGBUS, while a read just returns fewer bytes. Files over 512 MB are skipped (`QueuedFileGate.maxReadBytes`). A long PDF is read again for each step of the later pass.

An index made before these types were added catches up on its next sync, which every launch and every change in the folders starts. Files Lookout ignores were never recorded, so the new types arrive as new files, and nothing already read is read again. An SVG that the old rules took for a picture, and failed to read, is no longer found by the crawl, so the sync removes it. No version number had to change.

Long files are read a step at a time. A PDF over 50 pages gets its first 30 pages in the first pass, and a document gets its first 40 chunks, about 64,000 characters. The rest is read after everything else. Pages or chunks past 5,000 are left out.

## Ranking

`Searcher` ports DigUp's hybrid ranking. Every constant is in `LookoutRanking`, so tuning one is a one-line change. The file values are DigUp's, measured on its evals between 2026-10-07 and 2026-10-09.

1. **Meaning.** `Searcher` scores every stored vector against the query by cosine similarity. It subtracts the average of the vector's modality for this query, because text and image vectors sit at different levels, and divides by the standard deviation of all centered scores. The result is a z-score on this query's own scale. A modality with fewer than 20 vectors uses the overall average. The later pages of long files are scored but don't move the scale. A segment counts as a meaning match at z ≥ 2.0 (`zGate`), and each file keeps its best segment.
2. **Words.** FTS5 finds the files that contain the query's words. The query applies the scope, the kinds, and the settings' folders and file types before its limit. It keeps the 100 best files that the settings filter accepts and that still exist, so files deleted since the last sync can't crowd out a match further down. It steps through at most 4,000 matching segments to find them (`Searcher.wordFiles`, `wordWindow`). Coverage is the share of the query's words found anywhere in a file. A file qualifies by words alone at coverage ≥ 0.5 (`wordGate`). Stopwords and kind words such as "photo" or "pdf" don't count as words.
3. **Score.** A file scores max(z, 0) + 2 × coverage^1.5. A lookup query is made only of codes such as `K7Q2LM` or numbers of four or more digits, and an embedding knows little about those. A lookup scores 0.5 × z + 4 × coverage^1.5 instead. A file of the kind the query names ("screenshot of…", "pdf", "notes") gets +1.
4. **Folders.** DOKK adds folder results. A folder qualifies when three or more of its direct children qualify. Deeper files count only for their own folder. The folder scores the average of its three best files, plus 0.25 for each further matching file, up to +1. Its files stay in the list too. A search inside a folder never returns that folder itself. These values are DOKK's own and haven't been measured yet.
5. **Strong and weak.** Hits that score at least 0.5 × the top score are strong (`strongRatio`). The rest fold under **Weaker matches**. On DigUp's evals, 0.5 cut the list from 26.2 to 5.7 results per query and never folded an expected answer.

Requiring a meaning match to stand out gives Lookout an honest empty state. When nothing passes either gate, the section says "Nothing stands out for this" instead of listing weak guesses.

Each hit records whether meaning, words, or both matched, and which segment it points at: a PDF page, a passage, a picture, or a screenshot. The preview column's **Why it matched** card turns that into one sentence, such as "Page 7 matched by meaning." For a lookup, the card says exact words count double.

`Searcher` can also filter by file kind, but the Files tab doesn't offer that filter yet.

## Searching with a picture

A picture can be the query instead of words. The design is the interactive mockup at `docs/mockups/lookout-image-search.html`.

### Ways in

- **Drop.** While something is dragged over the Hub with the Files tab showing, the search field widens by 90 pt into a drop well. A picture shows "Drop to search with this picture", and a document the index holds shows "Drop to find files like this one". Dropping either searches with it: with its stored vector when the index holds it ("From your index · instant"), else, for a picture, the picture read (`LookoutPictureQuery.dropped`). A document of a kind Lookout reads that the index doesn't hold shows "Lookout hasn't read this file yet" in orange, and anything else "Lookout searches with pictures only". Neither can be dropped there. Whether the index holds a dragged document is one indexed query, asked when the drag enters the Hub; the well opens with the answer (`HubFilesModel.lookUpDraggedDocument`). Only a picture from outside DOKK wakes the picture reader. The Hub only watches drags, and `HubDragObserver` refuses every drop it sees, so dropping anywhere but the field does what it did before. Files moved between the tab's own panes open the well only when they can be searched with: pictures, and documents the index holds. `HubFilesPictureDrag` pieces the drag together from the observer over the Hub, the field, and the tab's AppKit drop regions. It waits 150 ms between regions, so the well doesn't flicker.
- **The field's text.** A file dragged onto the field is never inserted as its path. While a text field edits, AppKit's field editor registers for file URLs, filenames, web URLs, and pictures, and would insert a dropped file's path before the field's drop target saw the drag. `HubPanel.makeFirstResponder` narrows the field editor's drag types to plain text, RTF, and HTML each time editing begins, so file and picture drags fall through to the SwiftUI drop targets. Plain text still drops in as text. This applies to every text field in the Hub.
- **Paste.** ⌘V with picture bytes on the pasteboard and no text searches with them, and so does a picture file copied in Finder. Anything else pastes as text.
- **Find Similar.** A full-width button in the preview column above Open, Quick Look, and Reveal, an item in the context menu, ⌘⇧L, or dragging a search result onto the field. It works on one selected file, in search results and in the browser alike. It's hidden for folders and until Lookout can search (ready, reading files, or paused). It's disabled with "Lookout doesn't read this kind of file" for kinds Lookout doesn't index, by the crawl's own rules (`LookoutSimilarAvailability`). A document the index doesn't hold has nothing to search with, so it's disabled with "Lookout hasn't read this file yet" once the reader says so (`LookoutIndexSearching.indexedPaths`). The reader is asked when the file is selected; a file it doesn't hold is asked about again the next time, because the backfill may have read it since. A picture the index doesn't hold is read like a dropped one. Find Similar works on name results, Lookout results, the results of a search with a picture, so searches chain, and files in the browser, where there were no words, so the results bar has no "Back to".
- **The DOKK tile.** A file dropped on the DOKK tile (or the open Apps tab) opens the Apps tab's file actions. When exactly one file was dropped and Lookout can search with it, a picture Lookout reads or a file the index holds, **Find Similar** comes first in the list, with the same glyph (`LauncherFileSimilar`, wired by `HubCoordinator`). The file actions ask Lookout once per batch. Choosing it ends the batch, switches to the Files tab, and searches with the file as Find Similar does.

The picture becomes a chip in the field: its thumbnail, its name or "Pasted picture", and ✕. ⌫ in the empty field, ✕, and "Back to “…”" in the results bar remove it and bring back the words searched before it. The clear button and Escape remove both. Typing replaces the picture with a search by words. Find Similar on a result of a picture search replaces the picture and keeps the earlier words (`LookoutPictureSession`).

### Reading the picture

DOKK.app reads a dropped or pasted picture itself. A dropped file is opened once, `fstat` on that descriptor must show a regular file of at most 512 MB, and the bytes are read from the same descriptor in `pread`s, never memory-mapped (`LookoutPictureReading.bytes`); a file that can't be checked isn't read. It holds the drag's or the pasteboard's access, and the query service may not be allowed to read where the picture is. `QueryPicture` (`Core/`) sizes it in memory the way the indexer sizes stored pictures. ImageIO decodes straight to at most 1536 px for a screenshot and 1024 px for a photo, upright. The bicubic resize then fills 280 or 140 soft tokens (`ImageSizing`, which moved to `Core/` for this). A pasted picture is sized as a screenshot, and a file as a screenshot when macOS or its name says it is one. The packed RGB pixels go over XPC (`LookoutQueryServing.embedPicture`). Nothing is written to disk on either side, and the vector lives only while its search is current.

The query service loads the image encoder into the text model it already holds (`LlamaEmbedder.attachMedia`), for pictures of up to 280 tokens, which fit its 512-token context. It does so only for the first picture, so a service that only embeds words never loads the 555 MB file. A picture dragged into the Hub from outside DOKK wakes the encoder at once (`warmUpPictureReader`), so it's usually warm by the drop. The idle exit releases both 120 s after the last call. The results bar shows "Waking Lookout's picture reader…" while the encoder loads and "Reading your picture…" while it encodes the picture. Then it says "New picture · read in 0.4 s · not saved".

Find Similar on a file in the index encodes nothing. It reuses a stored vector (`Searcher.similarSource`): the segment a Lookout result matched, such as that PDF page, else the file's picture, else its first segment with a vector. The results bar says "From your index · Page 7 · instant". A picture the index doesn't hold, such as a name result outside the chosen folders, is read like a dropped one.

### Ranking

`Searcher.similar` scores every stored vector against the query vector on the query's own scale, as text search does (`Searcher.meaning`), and keeps each file's best segment. There are no words, so a file qualifies by meaning alone at z ≥ 2.0 and scores its z. A picture query's cosines to other pictures run far above its cosines to text, even after `meaning` centers each modality. So the results come in two groups ranked on their own: pictures and screenshots, and PDFs and documents. Each group splits at its own `LookoutRanking.strongRatio` of its own top score, has its own **Weaker matches** fold, and forms its own folders by the usual rule. A folder that forms in both groups stays in the one where it scores higher. The file searched with never appears in its own results, and its folder doesn't count it.

The query's own kind comes first. An image vector is a picture query, and that includes a screenshot's picture and a rendered PDF page. Its groups are **Looks like it**, then **About what it shows**. A text vector is a document query, with **Says something similar**, then **Pictures of it**. A group with nothing above the gate says "Nothing stands out here." When neither group has a strong hit, the results give the honest message. Rows say **Looks alike** for a picture found with a picture, and **Same subject** otherwise. **Why it matched** shows the picture searched with ≈ the match, one sentence, and a three-step closeness meter from the hit's z: 4 and up is **Very close**, 3 and up **Close**, and the rest **Somewhat alike** (`LookoutPictureWhy`). The preview column is compact for a search with a picture, as in the mockup: a 140 pt well (200 pt for any other search result, 250 pt while browsing), one line of details ("Desktop › Holiday Sylt 2026 · 3.1 MB"), and, while nothing is selected (the picture is still being read, or nothing stood out), the picture searched with. The well is the part that gives: it shrinks to as little as 88 pt (150 pt for a search by words) before a long name or a two-line sentence could push the actions below the fold.

### Words in a dropped screenshot

Not built. Lookout reads the text in screenshots when it indexes them, and the plan was to read a dropped screenshot's text too and match its codes and long numbers as exact words. Vision keeps about 100 MB cached in whatever process runs it. That would be either DOKK.app or the query service, which already holds about 900 MB with the encoder. It would also add 0.1–0.25 s to a picture query. And word matches don't fit the two groups, which rank by meaning alone, or their chips and sentences. Combining a picture with words is Planned ([DEE-126](https://linear.app/d-zwei/issue/DEE-126)).

## Progress

`LookoutEngine.progress` says where reading stands. It's a `LookoutProgressDisplay` (`Hub/Files/Lookout/Progress/`), the one progress type: `LookoutProgressTracker` derives it, Settings' progress card draws it through `LookoutSettingsModel.progress`, and the Files tab's status chip fills to its fraction. It's nil while Lookout isn't set up, is off, or waits for the model: the card has nothing to track then, and the Files tab's download card and chip show the download.

| Field | Meaning |
| --- | --- |
| `phase` | `counting` (walking the folders), `reading`, `upToDate`, `paused(reason:)` (`lowPowerMode`, `thermal`, `onBattery`, `userPaused`), `waitingForDrive(name:)`, `failed(message:)` with the localized sentence |
| `done`, `total` | Files of the current pass read or otherwise settled, and the files it reads. While counting, the total is the files found so far. Up to date or waiting for a drive, both are every file the index knows in the folders that are there. |
| `totalIsFinal` | False while the walk is still counting: the total may grow. |
| `remaining` | Files waiting, plus long files part read. Nil while the first walk counts, and while waiting for a drive, whose files aren't counted. |
| `filesPerSecond` | The smoothed pace while reading files. Nil while it's too early, and while long files finish, which go by pages. |
| `estimatedRemaining` | About how long the files waiting take at that pace, or the pages and chunks left while long files finish. Nil when it can't be said honestly. |
| `kinds` | Read of known, by `FileKind`, for kinds with files. |
| `lastCompleted` | When the index was last up to date, also from before DOKK started. |
| `skipped`, `failed`, `problems` | Files Lookout tried and skipped or couldn't read, and both by reason, most first, already in the app's language (`LookoutProblemReason.title`). |

- **Phases.** Failures, the model, and pauses come from the engine's status (`LookoutStatus`). The rest come from the service's activity: `syncing` is counting, reading files or finishing long files is reading, and idle is up to date, or waiting for a drive while a chosen folder isn't there. The drive's name is the volume's (`/Volumes/Photos/…` → "Photos"), or the folder's.
- **The pass.** A pass starts when files wait while none did, and counts only its own files. An index that has never been up to date is still in its first pass, which counts from the start, also after DOKK relaunched partway. During the first walk, the total is how many files the walk has found so far: the crawler reports every 250 (`Crawler.foundReportInterval`), and the status carries it as `discovered`. Files queued during a pass make its total grow; files removed can't make it go backwards.
- **The pace.** `LookoutRateEstimator` takes the plain average for the first 10 s and 5 files and reports nothing meanwhile. After that it moves toward each new sample's pace by `1 − e^(−Δt/30 s)`, an exponential average weighted by how long each sample covers, so eight images committed at once don't count more than the seconds they took. A pause, a walk, or any other phase that isn't reading forgets the last sample, so the gap never counts as slow reading, and the pace carries on when reading resumes. The time left uses the pending files only; the later pages of long files follow at their own pace and get their own estimate once that pass runs.
- **Publishing.** The engine feeds the tracker every status the service sends, so the pace sees every step, but `progress` changes at most every 500 ms (`LookoutEngine.progressInterval`) within one phase. A phase change shows at once. A trailing publish, the one owned task, makes sure the last status always shows, and `stop()` cancels it. Nothing polls.
- **The service's part.** `LookoutIndexStatus` carries `discovered` and `upToDateAt`, and `IndexStore.Counts.problems`. The service records the time the index was last up to date in the index's `meta` table (`up_to_date_at`) whenever it settles idle with nothing waiting, and sends its counts as soon as a configuration opens the index, before the walk. Problems are counted in SQL by the start of each file's stored reason (`LookoutProblemReason.rules`), so reasons that differ per file, such as "small image 120×90", come back as one row. The stored reasons can name a file and never leave the index.
- **Previews.** `LookoutProgressDisplay.Sample` holds nine deterministic states, shaped as the tracker produces them: counting, reading early, reading midway, a big index, paused for Low Power Mode, paused by the person, waiting for a drive, up to date, and stopped. The card's gallery preview and the tests use all of them.

## Power policy

The backfill is the first pass, and any later sync that queues more than 50 files. `LookoutPowerPolicy` lets it run only when all of these hold:

- Low Power Mode is off.
- The thermal state is nominal or fair, not serious or critical.
- The Mac is on AC power, or **Read files on battery too** is on. That setting is on by default.

The policy re-evaluates on power-source, thermal-state, and Low Power Mode notifications and tells the service through `setBackfillAllowed(_:)`. A sync that queues 50 files or fewer (`IndexWork.newFilesLimit`) indexes them at once on any power source, so a new screenshot is searchable in seconds. Once nothing else waits, the rest of long files follows under the same rule as the backfill.

While reading waits, the status chip says why: **Low Power Mode**, **Mac is warm**, or **On battery**. What's already read stays searchable. The rule also applies during onboarding, so the first pass doesn't move on battery when **Read files on battery too** is off. While reading runs and the pass's total is final, the chip's background fills from the leading edge with `LookoutTheme.accentSoft` to the share `LookoutEngine.progress` reports (`LookoutProgressDisplay.fraction`, the number the Settings ring shows), and its tooltip and VoiceOver label add the percentage.

## Onboarding

Onboarding is five steps on a card over the Files tab. `LookoutSetupCoordinator` runs it, `LookoutSetupDraft` holds what it has gathered, and `LookoutSetupOverlay` draws it (all in `Setup/`). It opens from the status chip, from the **Set up Lookout** card in the search results, or from the **Search by content** switch in Settings, which opens the Hub first.

While the card shows, it holds an anchored Hub open (`HubHoldReason.modal`). The folder picker and macOS's Files and Folders prompt both take key status from the Hub, and without the hold it would close. Sleep, a display change, ⌘W, and opening Settings still close the Hub, and onboarding then ends as if the person had closed it. Return presses the primary button and Escape closes the card. The Hub's ⌘1 to ⌘3 and ⌘F wait until the card closes.

1. **Welcome.** Three example searches, for a photo, a screenshot, and a PDF page, and the privacy line. The buttons are **Not now** and **Continue**.
2. **Choose where Lookout looks.** Desktop, Documents, and Downloads are checked, and Pictures is not. Each row shows its file count, the first pass in minutes, and the index size. `Estimator` works these out from metadata, off the main actor. Desktop, Documents, and Downloads show **Estimate after access**, because reading them here would make macOS ask before the person reached the access step. Folders that read without a prompt, such as Pictures, are checked and estimated as soon as the step appears. **Add folder…** opens an `NSOpenPanel`. Picking a folder there is consent, so DOKK reads it at once. Some folders are refused with a sentence that says why: `/` and `/Volumes`, the home folder and the folders around it, `~/Library` and the folders in it, hidden folders, apps and other bundles, and macOS's own folders such as `/System`, `/Library`, `/Applications`, `/usr`, and `/private`. Two kinds of folder in `~/Library` may be chosen, with everything below them: iCloud Drive (`~/Library/Mobile Documents/com~apple~CloudDocs`) and the cloud storage folders in `~/Library/CloudStorage`, such as Dropbox, Google Drive, and OneDrive (`Rules.isCloudFolder`). `CloudStorage` and `Mobile Documents` themselves, and other apps' folders in `Mobile Documents`, stay refused. A link is checked where it leads, so `~/Dropbox`, which links into `CloudStorage`, is accepted. A folder inside a chosen one adds nothing, and a folder around chosen ones replaces them. A **Lookout never reads** list sits below the folders.
3. **Allow access.** Each protected folder has **Allow…**, which reads the folder, so macOS shows its prompt in context. Protected folders are Desktop, Documents, Downloads, iCloud Drive, cloud storage folders, and anything under `/Volumes` (`LookoutFolderChoice.needsPrompt`). The answer shows as **Allowed** or **Not allowed · Skipped**. A declined folder offers **Open Settings**, which opens Privacy & Security › Files and Folders. When DOKK becomes active again, it reads declined folders again without a prompt, so a folder allowed in System Settings turns to **Allowed**. Folders that read without a prompt are already marked **Allowed**. Continue needs an answer for every chosen folder and at least one allowed. The step is skipped when every chosen folder is already allowed.
4. **Download the model.** Two rows: **Words**, 310 MB, for documents, PDFs, and searches, and **Pictures**, 555 MB, for photos, screenshots, and scanned pages. Each shows its progress, then **Checking…** while its SHA-256 is verified, then **Ready**. **Read files on battery too** is on by default. Continue needs both files.
5. **First pass.** A ring shows the files read out of every file the index knows, from the index service's status. A feed lists the names of files as they are read. The buttons are **Finish in the background** and **Start searching**, which puts the caret in the search field.

Nothing is saved until the first pass starts. Continuing from the download step applies `LookoutSetupDraft.settings(from:)`: the allowed folders, the battery choice, `enabled`, and `setupCompleted`. Setup has to be applied there, because the first pass needs a running engine to show progress. The query encoder warms at the same moment. From then on, both buttons and closing the card only end onboarding, and reading goes on.

Closing the card earlier keeps the draft in memory. Opening onboarding again resumes at `LookoutSetupDraft.resumeStep`: where the person left, unless an earlier step no longer holds. Quitting DOKK forgets the draft. A download keeps running after the card closes. Quitting stops it but keeps the partial file, and the next run continues from that file when onboarding reaches the download step again.

## Model download

`ModelFiles` pins ggml-org's Q8_0 GGUF conversion of EmbeddingGemma 2, `ggml-org/embeddinggemma-2-GGUF` at revision `bfcd298762cc34d0357ece5ebdd31791a3a374d8`.

| File | Bytes | Used for |
| --- | --- | --- |
| `embeddinggemma-2-Q8_0.gguf` | 309,855,456 (310 MB) | Text: documents, PDFs, and queries |
| `mmproj-embeddinggemma-2-Q8_0.gguf` | 554,821,024 (555 MB) | The image and audio encoders |

Lookout never uses the F16 files, because the model's activations overflow float16. Changing the revision or a file changes the vectors, and every index would have to embed again.

`LookoutModelDownloader` (`Download/`) downloads only when onboarding's download step appears. It never downloads under the test host or in previews. A run goes like this:

1. It checks the free space first (`LookoutDiskSpace`): the bytes still to fetch plus 128 MB. A fresh download needs about 1 GB.
2. It fetches the text file, then the media file, with `URLSession` from Hugging Face's `resolve` URL at the pinned revision. Redirects may go only to `huggingface.co`, `hf.co`, or their subdomains, over HTTPS. Any other redirect stops the download.
3. It writes into `Partial/<name>.partial` and resumes with an HTTP `Range` request, also after a relaunch. `If-Range` isn't needed, because the files at one revision never change. A `200` answer starts the partial file over. A `416` deletes it and tries once more from the start.
4. It verifies the size and the SHA-256 in 8 MB pieces, off the main actor. The 555 MB file takes about half a second. Only a verified file moves into `Models/`, so the services never see a partial one. A mismatch deletes the partial file.
5. When both files are in place, it calls `LookoutEngine.modelDidArrive()`. The engine warms the query encoder, so its first launch compiles the Metal shaders, about 5 s, during the first pass and not on the first search. A running index service is asked to sync, and starts embedding.

Every error has a localized sentence: the connection dropped, Hugging Face answered with another HTTP status, a redirect left Hugging Face, the checksum didn't match, the file arrived incomplete, the file couldn't be saved, or there isn't enough free space. Each offers **Try Again**.

While the download runs and setup isn't complete yet, the Files search shows a download card with a progress bar and the chip reads **Downloading model** with the percentage (`HubFilesModel.lookoutDisplayStatus`). A click on the chip resumes onboarding at the download step. If Lookout is set up but the model files are missing, the index service still syncs, so file names stay searchable, and the status is **Downloading model** as well.

## Settings

**Settings → Lookout** sits under the Features heading of the sidebar (`DeeDock/Settings/Lookout/`). `LookoutSettingsModel` sends every change through `LookoutEngine.apply(_:)`, which saves it and tells the index service. Before setup, the page shows only the switch and the privacy line.

- **Search by content.** Off stops the engine and keeps the index. Turning it on before setup opens onboarding over the Hub. The switch stays off until setup completes.
- **The progress card** (`Settings/Lookout/Progress/`). `LookoutProgressCard` draws a `LookoutProgressDisplay`: a value with the phase (counting, reading, up to date, paused with its reason, waiting for a drive, failed), files done and total, whether the total is final, files remaining, the reading rate and estimated time left, per-kind counts, when the last pass finished, and skipped and failed files with their reasons. `LookoutSettingsModel.progress` reads `LookoutEngine.progress` (see [Progress](#progress)), or a pinned sample in previews; what's nil, such as the time left before the pace is steady, the card leaves out. `LookoutProgressFormatting` holds the phrasing: the percentage rounds down and reaches 100 % only when done; the time left rounds to minutes, to five minutes past an hour, and to hours past ten. The summary is one accessibility element with the phase as its label and the numbers as its value. **Pause** and **Resume** call `LookoutEngine.pause()` and `resume()`.
- **Folders.** Each folder shows how many of its files are searchable by content, and the card shows the total. A folder that isn't connected shows **Not connected · results return when it's back**: its index is kept, and its results return once the drive is connected. A folder macOS doesn't let Lookout read shows **Not allowed** with **Open Settings**. **Remove** takes a folder out, and the service drops its files from the index. **Add folder…** reads the picked folder right away, in the foreground, so macOS's prompt appears in context. DOKK adds the folder only when the read is allowed. The refusal rules match onboarding.
- **Read files on battery too.** Its subtitle says that reading still waits in Low Power Mode or when the Mac is warm.
- **Model**, **Index on disk**, and **Memory while searching.** Index on disk is the database plus its write-ahead log. The memory row reads "about 250 MB, about 900 MB after searching with a picture; released 2 min after the Hub closes": the query service holds 215 MB with the text model and about 900 MB once the picture reader is loaded, and the app's vectors add about 30 MB.
- **Read everything again.** Calls `resetIndex()` on the service, which queues every file again and drops their vectors. Names stay searchable meanwhile. The row is disabled while Lookout isn't running.
- **Delete index and model.** Asks first. DOKK then stops a running download and forgets onboarding's draft. The row turns into **Deleting…** while the engine calls `closeIndex(reply:)` and waits up to 30 s (`LookoutEngine.closeTimeout`). The service drops a batch it has read but not committed yet, or finishes the commit it's in, closes its store and the model, and only then answers. Nothing is deleted without that answer: on a timeout or a lost connection, Settings says Lookout is still reading files, and Lookout, its settings, and its files stay as they were. The settings return to their defaults, so Lookout is not set up any more. `LookoutDataRemoval` deletes `index.sqlite` and the files beside it, `Models/`, and `Partial/`. It leaves `Logs/` and the person's own files alone. Setting Lookout up again downloads the model again.
- The privacy line.

`LookoutSettings` also stores skipped subfolders (`excludedFolders`) and skipped file types (`excludedExtensions`), and the index service honors both. Settings has no controls for them yet.

## Privacy

The privacy line in onboarding and Settings reads: "Lookout reads only the folders you pick, on this Mac, and keeps its index here. DOKK downloads the model once from Hugging Face; that request sends nothing about your files."

- Lookout reads only the chosen folders. The services never ask for folder access. macOS's prompts come from DOKK.app, in onboarding's access step or after **Add folder…** in Settings.
- A picture searched with is read in memory and never saved. The app sends its pixels to the query service, which keeps nothing once it has answered.
- The index and the model stay on this Mac, in the folder above.
- The only network request is the one-time model download from Hugging Face. It asks for two fixed files at a pinned revision and sends nothing about the person's files.
- Usage analytics carry counts and closed tokens only, never paths, file names, query text, or scores. [Analytics](ANALYTICS.md) lists the Lookout events.
- The first pass's feed shows file names on this Mac only.
- The index service's own error text can name a file. It goes to the logs only and never to analytics.

## Build llama.cpp

`scripts/build-llama.sh` builds llama.cpp tag `b11461` with `scripts/llama.cpp-no-logits.patch`, copied from DigUp. Without the patch, every input token costs 1 MiB of logits that an embedding model never produces. The Run Script phases of `LookoutIndexService`, `LookoutQueryService`, and `LookoutBench` call the script on every build. A stamp in `Vendor/llama/BUILD` makes it do nothing once the build is there. The stamp holds the tag, the patch's checksum, and the deployment target, and it's written only after a patched build succeeds. When parallel targets run it, one builds and the others wait on a lock.

The patch counts as applied only when it reverses cleanly. Otherwise the script resets `Vendor/llama.cpp` to the tag, removes untracked files there, and applies the patch. If the patch doesn't apply to the tag, the build fails with an error that names it.

The first build needs these:

- Network access and `git`, to clone the tag from GitHub into `Vendor/llama.cpp`.
- CMake on `PATH`. The script adds Homebrew's paths, because Xcode's script phases get a minimal `PATH`. Without CMake, it uses `uv` to create `Vendor/cmake-venv` with CMake and Ninja.
- Ninja, optionally. Without it, CMake uses Unix Makefiles.
- Xcode at `/Applications/Xcode.app`, unless `DEVELOPER_DIR` is set.

The script builds arm64 static libraries for macOS 27 with Metal on, and combines them into `Vendor/llama/lib/libllamacpp.a`. It copies the headers into `Vendor/llama/include` and writes `llama-build.h` with the tag. `Vendor/` is in `.gitignore`. `Lookout/CLlama/module.modulemap` exposes the headers to Swift. The Metal shaders are embedded and compile on first use, so the build needs no Metal toolchain.

Move to a new tag only if `LookoutBench reference` passes on it. If it fails, keep the tag, or bump `LlamaEmbedder.vectorVersion` and write new reference vectors. Every index then embeds again.

During development, the query service can load the model from another folder when the installed `Models/` folder has no text model. It reads the `LOOKOUT_MODELS` environment variable, then the `LookoutModelsFolder` default in the service's own domain:

```sh
defaults write <app identifier>.LookoutQueryService LookoutModelsFolder <folder>
```

XPC services don't inherit the app's environment, so the default is the practical override for a service the app launches.

## LookoutBench

`LookoutBench` is a command-line developer tool with its own scheme. It isn't part of DOKK.app.

```
LookoutBench reference --models <folder> --refs <folder>
LookoutBench bench --models <folder> [--refs <folder>] [--image <file>]
LookoutBench index --models <folder> --index <folder> --root <folder>... [--exclude <folder>]...
LookoutBench estimate --root <folder>...
```

- `--models` is the folder with both GGUF files.
- `--refs` is DigUp's `Tests/LlamaRuntimeTests/Reference` folder, with `photo.jpg`, `screen.png`, `speech.wav`, and `vectors.json`. Those files are not in this repository.
- `--index` is the folder `index.sqlite` goes in. It is created when missing and is never the app's folder unless you pass that.
- `--root` and `--exclude` can be repeated.
- `--image` is the picture the picture-search probe searches with. Without it, the probe uses macOS's Sonoma wallpaper (`/System/Library/Desktop Pictures/Sonoma.heic`).

The commands:

- `reference` embeds DigUp's fixed inputs the way DigUp's indexer hands them over and compares each vector with `vectors.json`. The inputs are queries in English, Bengali, and Arabic, a short document, a document of about 1,800 tokens, a screenshot at 280 tokens, a photo at 140 tokens and as a 70-token video frame, and a 16 kHz WAV. It exits 0 when every cosine is at least 0.99 and also reports whether DigUp's 0.999 holds.
- `bench` runs each probe in a child process, so one probe's memory doesn't show in the next one's figures. The text probe runs first, so a run right after a build also shows the first start before Metal's shader cache holds the binary's pipelines. It prints the measurements and a decision gate: warm query p95 at most 150 ms, encoder cold start at most 2 s, query encoder memory at most 600 MB, the slowest image embed's median at most 1,500 ms, indexer memory at most 2,000 MB, and every reference cosine when `--refs` is given. For searching with a picture, it adds a warm picture query p95 of at most 600 ms, a cold picture search (encoder load plus first picture) of at most 2.5 s, and the query service with the encoder at most 1,000 MB. It exits 0 when every gate passes. A gate it can't measure without `--refs` counts as not passed.
- The picture-search probe (`probe-image`) starts as the query service does, with the text model only. It then loads the image encoder into it on the first picture and embeds pictures prepared the way the app prepares them (`QueryPicture`), at 280 and 140 tokens.
- `index` does what the index service does for one sync, in one process, without XPC and without the power policy. It prints each file, the counts, the timings, and the peak memory.
- `estimate` prints what onboarding shows for each folder, with its subfolders one level down. It reads metadata only.

## Measured performance

Phase 0 measured the encoder figures on an M4 with a Release build. The indexing figure comes from phase 1a's bench run on a test folder. The picture-search figures come from four `LookoutBench probe-image` and `bench` runs on the same M4 with a Release build on 2026-10-12, with Sonoma.heic and 10 warm runs per size.

| Measure | Result |
| --- | --- |
| Warm query, median | 10–15 ms |
| Query encoder cold start | 0.33–0.50 s. About 5 s (4.8 s measured) once, on the very first launch, while Metal compiles its shaders. |
| Query encoder memory | 215 MB |
| Full model | 967 MB, about 1 GB |
| One image embed | 0.24–0.58 s |
| Indexing a test folder | 2.9 files/s, 1.0 GB peak |
| Reference cosine | At least 0.999999 |
| Picture search, warm, 280 tokens (screenshots, pasted pictures) | 529–575 ms median, 553–644 ms p95 |
| Picture search, warm, 140 tokens (photos) | 226–237 ms median, 238–255 ms p95 |
| Picture search, cold (encoder load plus first picture) | 0.71–0.78 s. 1.21 s once, right after a build, while Metal compiles the encoder's shaders. The text model's own first shader compile (5.6 s) comes before that, as it does for words. |
| Image encoder load into a running query service | 0.16–0.20 s, or 0.59 s with the shader compile |
| App: sizing the picture (Sonoma.heic, 6K) | 116–180 ms at 280 tokens, 60–85 ms at 140 |
| Query service with the image encoder | 898–916 MB peak |
| One picture at 280 against 140 tokens | Cosine 0.94–0.96 |

The estimates in onboarding use DigUp's per-file costs, measured on an M4 Pro (`Estimator.Costs`).

## Known limitations

- The XPC services have not been exercised hands-on inside DOKK.app: idle exit, relaunch, and the replayed configuration.
- Onboarding, macOS's Files and Folders prompts, and a real model download have not been exercised live.
- Audio, video, and code are not indexed. Indexing them is Planned.
- Combining a picture with words in one search is Planned ([DEE-126](https://linear.app/d-zwei/issue/DEE-126)), and so is reading the words in a dropped screenshot.
- Searching with a picture has not been exercised hands-on: real drags from Finder, browsers, and Photos, pasting, the drop well, the query service's encoder loading inside DOKK.app, and its idle exit. A Photos drag that carries only a file promise isn't read.
- Find Similar in the browser and from the DOKK tile, dropping indexed documents on the field, and the field no longer inserting a dragged file's path have not been exercised hands-on. A picture dragged out of a browser that also carries its address as plain text may still insert that address while the field is being edited: it's text to the field editor.
- The new document types have been read only in tests, on made-up files. Real LaTeX with heavy macros, subtitles with unusual cue settings, and web archives from other browsers than Safari may read less cleanly.
- The progress card and the chip's wash have been rendered from samples only, never seen following a real first pass.
- The engine can pause reading, but no control offers it yet.
- Settings has no controls for skipped subfolders or file types yet.
- Release signing and notarization of the nested XPC services, and a CMake step in CI, are pending with Esi.

## Credits

**Settings → General → Acknowledgements** credits all three with their verbatim license texts, bundled from `DeeDock/Resources/Lookout/`.

- [DigUp](https://github.com/ARahim3/DigUp), MIT, © 2026 Abdur Rahim. Lookout adapts its indexer, its ranking, and its crawl rules. `DigUpLicense.txt`.
- [llama.cpp](https://github.com/ggml-org/llama.cpp), MIT, © 2023–2026 the ggml authors. The embedding runtime built into both services. `LlamaCppLicense.txt`.
- [EmbeddingGemma 2](https://huggingface.co/google/embeddinggemma-2), Apache 2.0, by Google DeepMind. The model Lookout downloads. `EmbeddingGemmaLicense.txt`.
