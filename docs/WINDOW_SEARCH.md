# Window search

DEE-15 adds **Find a Window** to the DDock menu. Command-Shift-Space opens it globally when macOS grants the hot-key registration. The menu reports a shortcut conflict and remains usable. Command-Shift-F works while DDock is active. Press `/` during Focus Dock to open search from any dock edge.

Opening search reads available window titles and app names. It does not capture pixels, run OCR, or ask a model. Window access can supply titles without Screen Recording. When exact window access fails, ScreenCaptureKit metadata can supply titles if already authorized. App-name cards remain available without either permission. These fallback cards explicitly say that selection opens the app.

## Search scopes

- **Current windows** searches metadata fetched when search opens or you choose Refresh Titles. All substantive query words must occur, ignoring case and diacritics. Common English and German filler words are ignored. Phrase matches rank before scattered words. Duplicate titles retain separate identities and show their app names.
- **Captured context** searches only windows chosen through Choose Windows and Capture Selected. The picker reads metadata; Capture Selected takes screenshots and runs Vision OCR. Each selected window has an image/text availability label and the batch completion time. Literal metadata matches rank before OCR matches of equal strength.
- **Saved capsules** searches user-saved titles, summaries, notes, tasks, and window references. Each result is labeled historical and shows its save time. Selection opens the saved capsule text in search, without launching its applications or claiming the old windows still exist. Delete Saved Capsule removes the persisted capsule through the existing repository and refreshes search and dock tiles.

The words `yesterday` and `gestern` require the Saved Capsules scope and filter by the capsule's creation date in the local calendar. Without a capsule saved yesterday there are no results. Other date phrases are literal terms, not interpreted time ranges. Search never records a desktop history.

Up and Down in the search field select results; Return opens the selected source. Escape closes search, cancels work, and clears captured context. Tab reaches capture choices and the other controls. A successful source activation keeps focus at that source. Escape returns focus to the previous external application.

## Presentation

The window is a fixed search bar, one content area, and a fixed keyboard footer. The bar holds the query field, Refresh Titles, the scope control, and the scope's disclosure text, with the full text in the adjacent info popover. Status messages appear as a single tinted line: failures and the image-search caution are tinted apart from routine notices.

Choose Windows lives in the Captured context scope, either in its empty state or in the captured bar beside Search Images with AI, the capture time, and Clear Captured Context. The capture picker and an opened capsule replace the result list, so only one kind of evidence is on screen at a time.

Each result row is a preview tile, the window title, its app and evidence label, and the excerpt. Metadata hits omit the excerpt because it repeats the title. Image evidence is tinted, and a result that can only open its app still says so.

## Image search and evidence

Search Images with AI is a separate action available after capture. It passes each selected screenshot to a fresh, tool-free, on-device Foundation Models session. The model receives the query and one image, without OCR or title text as a substitute for image evidence. Inferred matches follow literal matches and carry the label **Image interpretation · AI suggestion**. Literal matches are not relabeled as visual proof.

The installed Xcode 27 SDK exposes `Attachment<ImageAttachmentContent>.init(_:orientation:)` for `CGImage`, available on macOS 27. The existing capsule composer already attaches screenshots with this API. Apple's [Attachment reference](https://developer.apple.com/documentation/foundationmodels/attachment) and [macOS 27 overview](https://developer.apple.com/macos/whats-new/) describe multimodal input. The project targets macOS 27 in Swift 5 mode, with MainActor default isolation and approachable concurrency enabled.

API availability establishes that images can be supplied. It does not prove reliable purple-chart matching. Native visual matching acceptance is still unrun. OCR containing the word “purple” produces, at most, a recognized-text match. It cannot prove a chart is purple. Model suggestions are explicitly uncertain and must be checked against the screenshot. Unavailable models, refusals, context errors, and missing images leave metadata/OCR search usable. The model has no tools, and source content is treated as untrusted data rather than instructions.

## Bounds and deletion

| Resource | Bound |
| --- | --- |
| Live search | First 64 regular applications, at most 200 result cards and retained AX handles |
| Query | 200 characters |
| Capture selection | Four windows, captured serially |
| Screenshot | At most 1,200 × 900 pixels, preserving aspect ratio |
| Recognized text | First 6,000 characters per window |
| Image-model input | One image and a 200-character query per fresh session; at most four sessions per explicit action |
| Model output | At most 160 tokens per image; displayed explanation capped at 300 characters |
| Work deadline | 45 seconds, then cancel and reject late results |
| Captured retention | Memory only; 10 minutes from batch completion, or until Clear Captured Context or closing search |
| Saved history | Existing 30-capsule capacity; no new persisted capture store |
| Capsule search fields | First 2,000 characters per field; six tasks and twelve window references per capsule |

Ranking runs outside the UI actor with a 100 ms debounce. Capture/OCR and model work run through actors. Search owns and cancels its work, ranking, deadline, and expiry tasks. Query/scope changes invalidate image suggestions; clear/close rejects late callbacks before releasing content. Framework calls already in flight may retain their inputs until their cancellation completes. No content is logged, sent to a cloud provider, or written by search to disk. Capsules retain the existing user-approved text until deletion or the collection's capacity eviction.

## Navigation and platform limits

AX cards use the original session-scoped native window handle and revalidate the process launch date. A window may have changed its title since metadata discovery; Refresh Titles updates the displayed evidence. Missing or unusable handles report a stale source rather than choosing a similarly named window.

Captured results check the current window number, process, bundle identifier, and title, then require one AX window with the same title and bounds. Moved, closed, changed, ambiguous, or inaccessible windows can fail conservatively and ask for fresh capture. Capture itself rechecks process, title, and frame before taking a screenshot. Public APIs cannot make discovery and capture atomic or guarantee Space/full-screen navigation. ScreenCaptureKit-only metadata cards explicitly activate the app, never claim exact-window navigation.

The standalone search window is centered and clamped to the pointer display's visible frame, including negative screen origins. It opens only from an explicit keyboard/menu action. Hover does not open it or take focus. Search adds no motion; the background respects Reduce Transparency. Native controls and Window Peek cards expose keyboard and accessibility semantics. Very small display configurations, Spaces, full-screen presentation, and display disconnection still need hands-on acceptance.

## Validation status

Focused unsigned Debug app builds passed during implementation. The initial build reported an explicit-self warning in search ranking; that warning was corrected. An existing unused launcher variable warning appeared during the clean build. App Intents metadata extraction was skipped because this target has no AppIntents.framework dependency. The final command was:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/deedock-dee15-build \
  build CODE_SIGNING_ALLOWED=NO
```

It returned `BUILD SUCCEEDED`; the local log is `/tmp/deedock-dee15-build-final.log`. Catalog JSON and whitespace checks passed, and the built German resource contains the new search title, image-evidence label, and deletion action.

No tests, previews, automated visual checks, app launches, capture actions, or model inference were executed. Compilation does not establish native acceptance or visual matching quality. DEE-15 must remain open pending acceptance.

### Model and state cases worth testing

- Literal phrase versus scattered terms; case, diacritics, filler words, empty query, punctuation, and query length clipping.
- Duplicate titles across apps and within one app; deterministic ties and session-scoped identity.
- “Yesterday” with no saved history, no yesterday entries, midnight/time-zone boundaries, and unrelated live titles.
- OCR unavailable, truncated text, partial capture failures, and literal color words without visual evidence.
- Image output refusal, false match, empty explanation, unavailable model, oversized context, and partial batch failure.
- Query/scope replacement during ranking or model generation; stale results cannot repopulate cleared context.
- Four-window selection limit, expiry, clear, close, timeout, repeated open/close, and late framework completion.
- Capsule deletion failure versus success; deletion while another capsule panel is open; stale historical selection.
- Closed/reused PID, consumed AX session, changed title, moved captured window, ambiguous AX match, and denied permissions.

### Manual acceptance checklist, not yet executed

- [ ] Open using the menu, global shortcut, app shortcut, and Focus Dock `/`. Test a global shortcut conflict.
- [ ] Search identical window titles in different apps and two identical titles in one app; verify labels and navigation.
- [ ] Deny both permissions; search app names. Enable only Window Access and verify title search. Revoke permission while search is open.
- [ ] Open the capture picker and cancel without capturing. Select four windows and verify a fifth is unavailable.
- [ ] Capture an invoice with no “invoice” in its title. Verify the OCR excerpt and capture time. Include a protected or closed window and check its unavailable-content label.
- [ ] Put a purple chart and a green chart in separate windows. Explicitly search images. Verify the model's suggestion against each screenshot. Repeat with text saying “purple chart” beside a green chart to expose false visual matches.
- [ ] Turn Apple Intelligence off or use an unavailable model. Verify literal title and OCR search still work.
- [ ] Search `yesterday invoice` with no saved history, then with a capsule saved yesterday. Verify no current window is presented as historical evidence.
- [ ] Open a saved result, inspect the checkpoint, cancel deletion, then delete it. Reopen search and confirm it is absent.
- [ ] Change or close a result's source before selecting it. Verify conservative failure, Refresh Titles, and successful selection after refresh.
- [ ] Change queries rapidly, cancel image work, clear context, close/reopen search, and wait through expiry. Verify no old evidence returns.
- [ ] Exercise Return during capture selection and in-flight work. Verify it does not open a hidden result.
- [ ] Verify keyboard selection, scrolling, Tab order, VoiceOver labels, Escape focus restoration, Reduce Motion, and Reduce Transparency in English and German.
- [ ] Exercise all dock edges, multiple displays with negative origins, unplug/replug, different scales, Spaces, full-screen apps, and sleep/wake.
