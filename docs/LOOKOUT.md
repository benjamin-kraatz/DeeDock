# Lookout

Lookout is DOKK's on-device search by content. It finds photos, screenshots, PDFs, and documents in folders you choose by what they show or say. A search for "the dog on the beach" finds the photo, whatever the file is called. Lookout lives in the Hub's Files tab. Spotlight's name matches come first, under **Names · Spotlight**, and Lookout's results follow under **Lookout · by content**.

Implemented on `feature/dee-125` for [DEE-125](https://linear.app/d-zwei/issue/DEE-125). [The user guide](GUIDE.md#lookout) describes how Lookout behaves for a person, and [DOKK Hub](HUB.md#search) covers the Files search around it. The [acceptance notes](ACCEPTANCE.md#dee-125-lookout) list what still needs checking by hand. The approved design is the interactive mockup at `docs/mockups/lookout.html`.

Lookout adapts the indexer, the crawl rules, and the ranking of [DigUp](https://github.com/ARahim3/DigUp) (MIT, © 2026 Abdur Rahim). Adapted files say so in their first line.

## How it is built

Lookout runs in three processes. DOKK.app embeds two XPC services in its bundle, and launchd lets only DOKK.app look them up.

| Process | Job | Memory | Lifetime |
| --- | --- | --- | --- |
| `LookoutIndexService` | The index's only writer. Syncs the chosen folders, extracts text, runs Vision OCR, and embeds with the full model at utility QoS. | About 1 GB while it works | Waits about 60 s with the model loaded after it runs out of work, then exits. The next message relaunches it. |
| `LookoutQueryService` | Embeds search queries with the text model only, at user-initiated QoS. | 215 MB | Loads the model on its first call and exits 120 s after its last call. |
| DOKK.app | Reads the index, ranks results, and shows them. | The vectors, about 30 MB per 20,000 | The app's lifetime |

The services never ask for folder access. The index service skips a chosen folder it can't read and reports it as not permitted. It also skips a folder that isn't there, such as one on an unplugged drive, and keeps what it already indexed from it. The service checks this before every sync, so an ejected drive never looks like a folder whose files were deleted.

Before every sync, the service and the crawler also check each saved folder again where it really leads, with the rules onboarding uses (`Rules.checkRoots`, see [Onboarding](#onboarding)). The root itself is checked, not only the folders inside it. A chosen folder that has since become a link to `~/Library` resolves there and is skipped, and the next configuration drops its files from the index. Folders inside `/private/tmp` and inside the user's temporary folder may be roots, because people keep scratch files there. The rest of `/private` may not.

A sync or **Read everything again** that arrives while reading is paused, or while no app is connected, waits until reading may go on. Resuming syncs first, so changes made during the pause are found (`IndexRequests`).

A new DOKK version may bring a new model. The index then starts over by itself, and file names stay searchable meanwhile.

### App side

The app code is in `DeeDock/Hub/Files/Lookout/`.

- `LookoutEngine` (`Engine/`) puts the parts together. `HubCoordinator` creates one engine for the app's lifetime, and `DockCoordinator` starts it. It runs whether or not the Hub is open, so new files get indexed. It owns both XPC connections, the folder watcher, the mount and wake monitor, and the power policy. It saves `LookoutSettings` as JSON under the `hub.lookout.v1` defaults key and publishes `LookoutStatus` for the status chip and Settings. Under the test host and in previews, `LookoutEngine.live()` returns an inert engine that never starts.
- `LookoutIndexConnection` (`Services/`) sends the configuration, and a pause, again to a relaunched index service.
- `LookoutIndexReader` (`Search/`) is an actor that owns a read-only `IndexStore` and its `Searcher`. SQLite's write-ahead log lets it read while the service writes, so a search never waits for indexing. Vectors load on the first meaning search or when the Files tab appears. While the service adds vectors, the reader reloads them at most every 2 s. They are released 120 s after the Files tab hides or the Hub closes (`LookoutEngine.vectorReleaseDelay`).
- `LookoutSearch` (`Search/`) waits 150 ms after the last keystroke. It then publishes keyword hits first, with the last word matched as a prefix because it is probably half typed. Once the query vector arrives, hybrid results replace them. A generation token drops results that arrive late. If the encoder fails, the final results are keyword-only.
- `LookoutFolderWatcher` (`Monitoring/`) reports FSEvents in the chosen folders and ignores hidden files such as `.DS_Store`. The engine waits 2 s after the last change (`LookoutEngine.syncDebounce`), then asks the service to sync. `LookoutMonitor` also asks for a sync when a volume mounts or ejects and after wake. Nothing polls.
- `LookoutPowerPolicy` (`Monitoring/`) decides when the backfill may run. See [Power policy](#power-policy).

The code both sides share is in `Lookout/`: `Core` holds the index, the crawl rules, the search, and the ranking. `Indexing` holds the extractors, `Embedding` wraps llama.cpp, and `IndexService`, `QueryService`, `ServiceSupport`, and `Bench` hold the two services and the bench.

### Where the data lives

Lookout keeps everything in `~/Library/Application Support/DDock/Lookout/` (`LookoutPaths.standard`). Debug and Release builds share it, so a development build doesn't download the model again.

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

- Documents: `txt`, `text`, `md`, `markdown`, `rtf`, `docx`, `doc`, `odt`, `html`, and `htm`.
- PDFs: the text of each page. A page with fewer than 200 characters of text is embedded as a rendered image.
- Images whose longer side is at least 256 pixels.
- Screenshots, recognized by macOS's screen-capture attribute or by a name that starts with "Screenshot", "Screen Shot", "CleanShot", or "SCR-". Vision OCR reads their text.

Lookout skips these:

- Source code and data files. Audio and video are ignored, and Spotlight still finds them by name.
- Keys, certificates, and password files, wherever they are.
- Hidden files and folders, bundles, and symbolic links.
- Folders such as `node_modules`, `DerivedData`, and `Pods`, folders whose names end in `.noindex`, and `~/Library`, except iCloud Drive and cloud storage folders chosen as roots.
- iCloud and cloud storage files that aren't downloaded, because reading a placeholder downloads it.
- Code projects, except the screenshots in them.
- Folders of 300 or more images where at least 70% have machine-made names. They look like datasets. A folder the person chose is never treated as one.

The backfill can read a file hours after the crawl queued it, so `QueuedFileGate` checks each file again just before it's read. The stored path must still pass the settings and the crawl's folder rules. The file must be a regular file and not a link, and `lstat` and the opened descriptor must agree. `F_GETPATH` on the descriptor gives where the open file really is, which catches a folder on the way that became a link. Any other path than the stored one must pass the same rules itself and be the queued inode. Paths are never compared by spelling, because on a case-sensitive volume `Notes` linked to its sibling `NOTES` differs only in case. The extractors read the bytes from that descriptor, never the path, so the check and the read can't race. A file whose inode changed is queued again with its new identity. A file that fails a check is skipped, and the next sync settles it.

The bytes are copied into memory in 8 MB reads, never memory-mapped. A mapped file that's cut shorter while it's read would crash the index service with SIGBUS, while a read just returns fewer bytes. Files over 512 MB are skipped (`QueuedFileGate.maxReadBytes`). A long PDF is read again for each step of the later pass.

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

## Power policy

The backfill is the first pass, and any later sync that queues more than 50 files. `LookoutPowerPolicy` lets it run only when all of these hold:

- Low Power Mode is off.
- The thermal state is nominal or fair, not serious or critical.
- The Mac is on AC power, or **Read files on battery too** is on. That setting is on by default.

The policy re-evaluates on power-source, thermal-state, and Low Power Mode notifications and tells the service through `setBackfillAllowed(_:)`. A sync that queues 50 files or fewer (`IndexWork.newFilesLimit`) indexes them at once on any power source, so a new screenshot is searchable in seconds. Once nothing else waits, the rest of long files follows under the same rule as the backfill.

While reading waits, the status chip says why: **Low Power Mode**, **Mac is warm**, or **On battery**. What's already read stays searchable. The rule also applies during onboarding, so the first pass doesn't move on battery when **Read files on battery too** is off.

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
- **Folders.** Each folder shows how many of its files are searchable by content, and the card shows the total. A folder that isn't connected shows **Not connected · stays searchable**. A folder macOS doesn't let Lookout read shows **Not allowed** with **Open Settings**. **Remove** takes a folder out, and the service drops its files from the index. **Add folder…** reads the picked folder right away, in the foreground, so macOS's prompt appears in context. DOKK adds the folder only when the read is allowed. The refusal rules match onboarding.
- **Read files on battery too.** Its subtitle says that reading still waits in Low Power Mode or when the Mac is warm.
- **Model**, **Index on disk**, and **Memory while searching.** Index on disk is the database plus its write-ahead log. The memory row reads "about 250 MB, released 2 min after the Hub closes".
- **Read everything again.** Calls `resetIndex()` on the service, which queues every file again and drops their vectors. Names stay searchable meanwhile. The row is disabled while Lookout isn't running.
- **Delete index and model.** Asks first. DOKK then stops a running download and forgets onboarding's draft. The row turns into **Deleting…** while the engine calls `closeIndex(reply:)` and waits up to 30 s (`LookoutEngine.closeTimeout`). The service drops a batch it has read but not committed yet, or finishes the commit it's in, closes its store and the model, and only then answers. Nothing is deleted without that answer: on a timeout or a lost connection, Settings says Lookout is still reading files, and Lookout, its settings, and its files stay as they were. The settings return to their defaults, so Lookout is not set up any more. `LookoutDataRemoval` deletes `index.sqlite` and the files beside it, `Models/`, and `Partial/`. It leaves `Logs/` and the person's own files alone. Setting Lookout up again downloads the model again.
- The privacy line.

`LookoutSettings` also stores skipped subfolders (`excludedFolders`) and skipped file types (`excludedExtensions`), and the index service honors both. Settings has no controls for them yet.

## Privacy

The privacy line in onboarding and Settings reads: "Lookout reads only the folders you pick, on this Mac, and keeps its index here. DOKK downloads the model once from Hugging Face; that request sends nothing about your files."

- Lookout reads only the chosen folders. The services never ask for folder access. macOS's prompts come from DOKK.app, in onboarding's access step or after **Add folder…** in Settings.
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
LookoutBench bench --models <folder> [--refs <folder>]
LookoutBench index --models <folder> --index <folder> --root <folder>... [--exclude <folder>]...
LookoutBench estimate --root <folder>...
```

- `--models` is the folder with both GGUF files.
- `--refs` is DigUp's `Tests/LlamaRuntimeTests/Reference` folder, with `photo.jpg`, `screen.png`, `speech.wav`, and `vectors.json`. Those files are not in this repository.
- `--index` is the folder `index.sqlite` goes in. It is created when missing and is never the app's folder unless you pass that.
- `--root` and `--exclude` can be repeated.

The commands:

- `reference` embeds DigUp's fixed inputs the way DigUp's indexer hands them over and compares each vector with `vectors.json`. The inputs are queries in English, Bengali, and Arabic, a short document, a document of about 1,800 tokens, a screenshot at 280 tokens, a photo at 140 tokens and as a 70-token video frame, and a 16 kHz WAV. It exits 0 when every cosine is at least 0.99 and also reports whether DigUp's 0.999 holds.
- `bench` runs each probe in a child process, so one probe's memory doesn't show in the next one's figures. The text probe runs first, so a run right after a build also shows the first start before Metal's shader cache holds the binary's pipelines. It prints the measurements and a decision gate: warm query p95 at most 150 ms, encoder cold start at most 2 s, query encoder memory at most 600 MB, the slowest image embed's median at most 1,500 ms, indexer memory at most 2,000 MB, and every reference cosine when `--refs` is given. It exits 0 when every gate passes.
- `index` does what the index service does for one sync, in one process, without XPC and without the power policy. It prints each file, the counts, the timings, and the peak memory.
- `estimate` prints what onboarding shows for each folder, with its subfolders one level down. It reads metadata only.

## Measured performance

Phase 0 measured the encoder figures on an M4 with a Release build. The indexing figure comes from phase 1a's bench run on a test folder.

| Measure | Result |
| --- | --- |
| Warm query, median | 10–15 ms |
| Query encoder cold start | 0.33–0.50 s. About 5 s (4.8 s measured) once, on the very first launch, while Metal compiles its shaders. |
| Query encoder memory | 215 MB |
| Full model | 967 MB, about 1 GB |
| One image embed | 0.24–0.58 s |
| Indexing a test folder | 2.9 files/s, 1.0 GB peak |
| Reference cosine | At least 0.999999 |

The estimates in onboarding use DigUp's per-file costs, measured on an M4 Pro (`Estimator.Costs`).

## Known limitations

- The XPC services have not been exercised hands-on inside DOKK.app: idle exit, relaunch, and the replayed configuration.
- Onboarding, macOS's Files and Folders prompts, and a real model download have not been exercised live.
- Audio, video, and code are not indexed. Indexing them is Planned.
- Searching with an image as the query is Planned.
- The engine can pause reading, but no control offers it yet.
- Settings has no controls for skipped subfolders or file types yet.
- Release signing and notarization of the nested XPC services, and a CMake step in CI, are pending with Esi.

## Credits

**Settings → General → Acknowledgements** credits all three with their verbatim license texts, bundled from `DeeDock/Resources/Lookout/`.

- [DigUp](https://github.com/ARahim3/DigUp), MIT, © 2026 Abdur Rahim. Lookout adapts its indexer, its ranking, and its crawl rules. `DigUpLicense.txt`.
- [llama.cpp](https://github.com/ggml-org/llama.cpp), MIT, © 2023–2026 the ggml authors. The embedding runtime built into both services. `LlamaCppLicense.txt`.
- [EmbeddingGemma 2](https://huggingface.co/google/embeddinggemma-2), Apache 2.0, by Google DeepMind. The model Lookout downloads. `EmbeddingGemmaLicense.txt`.
