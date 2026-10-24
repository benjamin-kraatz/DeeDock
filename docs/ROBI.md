# Robi on your windows

Robi is DOKK's assistant. In the Launcher it suggests apps for a task. This document covers the other half: a small face that sits on the focused window of any app, takes what the person picks there, and answers with Apple's on-device model or, if they choose, Claude. For how it behaves, see the [user guide](GUIDE.md#robi-on-your-windows). The design is in [docs/mockups/robi.html](mockups/robi.html), and the Linear issue is DEE-142.

The feasibility spike lives on branch `codex/window-companion-spike` (`docs/COMPANION-SPIKE.md` and the `spikes/companion-lab/` lab and probes). That branch is reference only and is never merged. The numbers below come from its probes on macOS 27.0.

## How it is built

Everything is in `DeeDock/Robi/`. `DockCoordinator` owns one `RobiController`, starts it with the dock and stops it with the dock.

| Folder | What lives there |
| --- | --- |
| `RobiController.swift` | Lifecycle, phases, and the flow from a click to an answer. The only writer of `RobiModel`. |
| `Tracking/` | `RobiWindowTracker` follows the focused window. `RobiDragPrediction`, `RobiWindowServer` and `RobiWindowServerEvents` supply its geometry. |
| `Layout/` | `RobiLayout` and `RobiScreenSpace`: pure geometry and coordinate conversion. |
| `Panels/` | `RobiPanel`, the non-activating panel, `RobiSelectionSheet`, the sheet laid over the window in selection mode, and `RobiSpotlight`, the click-through overlay that points at a landmark. |
| `State/` | `RobiModel`, `RobiEyes`, `RobiContext`, `RobiLandmark`, and `RobiIntent`. |
| `Context/` | Reading the selection, the window's accessibility text, and pictures, plus waking Electron and Chromium accessibility. |
| `Answering/` | `RobiAgent`, `RobiReferencedAnswer`, the menu-command tool, the actions that put answers back, and the ⌥⇧⌘R shortcut. |
| `Views/` | The tab, face, prompt bar, suggestions, and answer card. |
| `Settings/` | `RobiSettings`, `RobiStore`, the Keychain wrapper, and the Settings page. |

Robi moves through six phases: `idle`, `awake`, `selecting`, `prompting`, `thinking`, and `answered`. While idle it runs window tracking and nothing else. Pointer monitors and the blink timer run only from `awake` on, and every task, monitor, timer, and observer ends in `RobiController.halt()`.

## Following the window

`RobiWindowTracker` takes focus from `NSWorkspace` activation notifications and an AX observer on the frontmost app (focused window, main window, focused element, window created). It keeps a window only if it is a standard window, not minimized, at least 240 × 140 pt, and not in a secure text field, a system UI process, DOKK, or an excluded app.

Geometry comes from three sources. Distances are how far the tab trailed a window dragged at 360 pt/s, measured from the window server's bounds for both windows:

| Source | Covers | Trail, median / p95 |
| --- | --- | --- |
| Drag prediction from global mouse monitors | title-bar drags | 0 / 6 pt |
| SkyLight window-server events 806 and 807 | edge resizes, tiling, window managers | 6 / 12 pt |
| AX `kAXMovedNotification` and `kAXResizedNotification` | fallback when SkyLight is unavailable | 24 / 42 pt |

The window server moves a dragged window itself and tells the app later, which is why AX lags. Prediction moves the tab by the pointer's delta from the drag's start, clamps the top edge at the menu bar the way the window server does, and checks real bounds after four drag events. If the window has not moved by then, the drag started on a tab or a control, and prediction stops. On mouse-up the tracker reads real bounds, because tiling can put the window somewhere else.

`RobiPanel` uses `.canJoinAllSpaces`, `.fullScreenAuxiliary`, and `.transient`. It can follow the focused window to any Space or full-screen app, and Mission Control hides it instead of leaving it floating.

### Private interfaces

| Interface | Used for | How it is guarded |
| --- | --- | --- |
| `_AXUIElementGetWindow` | AX window to `CGWindowID` | Resolved with `dlsym`. If it is missing, Robi falls back to matching pid and frame against `CGWindowListCopyWindowInfo`, and refuses ambiguous matches. AltTab, Rectangle, and Hammerspoon have used it for years. |
| `SLSMainConnectionID`, `SLSRegisterConnectionNotifyProc`, `SLSRequestNotificationsForWindows`, events 806 and 807 | Moves and resizes of another app's window | Resolved with `dlsym` and gated to macOS major version 27, like `LaunchServicesBackgroundReader`. The event numbers come from reverse engineering, and AltTab and JankyBorders agree on them. SkyLight has no unregister call, so the process registers once and routes to the current listener. |

Before widening the SkyLight gate on a new macOS, rerun the spike's `track` and `drag` probes. Check that 806 fires once per drag step for a window of another process, and that 807 fires on resize.

## Looking like part of the window

`RobiCapture.tint` takes a 5 pt strip, starting 2 pt below the window's top edge, across the tab's footprint, and uses its median colour. Sampling under the tab matters: Helium's tab strip measured `#3E455A` behind the active tab and `#222A3E` in the middle. A sample takes 80–140 ms and runs when Robi moves to a window and when it wakes, because translucent toolbars change colour with what is behind them. Without Screen Recording the tab keeps the system window colour.

`RobiLayout.placement` puts the tab above the window when 42 pt fit below the menu bar, and inside the top edge otherwise or in full screen. The tab overlaps the window's edge by 1 pt so no seam shows. The panel is transparent around the tab. It grows before a morph that needs more room and shrinks 450 ms after one that needs less, so its empty margin never sits over the window longer than necessary.

The tab can be dragged along the top edge. A position is the tab centre's fraction of the window's width, so it survives moves and resizes. `RobiLayout.tabX` turns it into a centre clamped to `tabTrack`, the part of the edge on the window's display inset by half the tab plus 16 pt, which keeps the flares off the rounded corners. `position(forTabX:)` is the inverse used while dragging. Lookup goes from the window's own position this session (`[CGWindowID: Double]` in the controller), to the app's last position (`RobiSettings.tabPositions`, by bundle identifier), to centred. A drop stores both, through `RobiStore.setTabPosition`, which saves without reapplying every setting mid-answer.

The face's press is one `DragGesture(minimumDistance: 0)` in `RobiFaceHandle`. It reports only that something happened. The controller reads `NSEvent.mouseLocation` itself, because the panel and the gesture's coordinate space move under the pointer. A press that stays within 4 pt is a click. Past that, it is a drag in every phase except `selecting`, and the tab keeps its grip offset, so the face stays under the pointer even at the bar's leading end. Past the track's ends the tab rubber-bands by up to 18 pt and springs back on release, stepped by a task that lays out the panel each frame. Reduce Motion has no rubber band. Tracker frame updates during a drag use the drag's position. A drag of the tab never moves the window, and global mouse monitors do not see DOKK's own events, so drag prediction stays out of it. The cursor does not change while dragging, because an app that is not frontmost cannot reliably set it.

## Reading context

1. **Selection.** `RobiSelectionReader` reads `kAXSelectedTextAttribute` from the focused element. Web content falls back to `AXSelectedTextMarkerRange` and `AXStringForTextMarkerRange`. Clicking Robi's non-activating panel leaves the app frontmost, so the selection is still the person's. Replace Selection writes the same attribute and works in native text views and Electron text areas.
2. **Web apps.** Electron and Chromium build their accessibility tree only for assistive apps. Robi sets `AXManualAccessibility` (Electron, no side effects) and, for apps that ship `chrome_100_percent.pak`, `AXEnhancedUserInterface` (Chromium). It reads the selection again 300 ms later. Chromium returns -25208 for that flag but builds the tree anyway: Helium went from 43 to 1,303 elements. Rectangle and Hammerspoon document that the flag can disturb window animations and adds Chromium work, so Robi restores it when the interaction ends.
3. **Whole window.** `RobiWindowText` walks the focused window's tree off the main actor, bounded to 0.4 s and 16,000 characters. A full walk of Finder or System Settings took over a second in the spike. Ghostty keeps the visible terminal, Claude Code included, in one `AXTextArea`. Besides text, the walk keeps headings, fields, and labelled controls (buttons, links, checkboxes, pop-ups, images with a description) as landmarks, up to 500. A labelled control is read by its title or description without its children; an unlabelled one is descended into, so a web link's text still counts. When the tree has under 200 characters, Robi captures the window and recognizes its text, and Vision's lines become the landmarks if they found more. With **Attach picture** on in the prompt bar (`RobiSettings.attachWindowPicture`), the picture goes with every whole-window question, beside the accessibility text; the switch only adds a picture, so the fallback for thin text still applies when it is off. Flipping it after the window was read adds the picture or drops one the switch added, without reading again. A fallback picture stays.
4. **Region.** The selection sheet takes the drag, so the app underneath never sees it. `RobiCapture.image` captures only the target window (`desktopIndependentWindow`), so Robi's panels and overlapping windows never appear. Pictures are capped at 1,568 px on the long side. The lines Vision recognizes become landmarks, placed in the window by the region's origin.

### Landmarks

A `RobiLandmark` is a number, a kind, its text, and a frame in window-local top-left points: the window's top-left corner, as AX and the window server report it, is the origin. AX frames are global top-left points, so `RobiLandmark.windowLocal` subtracts the window's origin (displays left of or above the primary one have negative coordinates) and clips to the window, which drops content scrolled out of view. Vision boxes are normalized with a lower-left origin; `RobiLandmark.recognized` flips them into the captured rect. Pixels never enter: the boxes are fractions of the picture, which was captured from that rect.

Vision's first recognition in a process took 13–27 s; later ones take 50–150 ms. `RobiCapture.prewarm()` runs once in the background when Robi starts.

## Answering

Both models run through one `LanguageModelSession`:

- **On-device** is `SystemLanguageModel.default`. On macOS 27 it reported an 8,192-token context, vision, and tool calling, and it answered a screenshot question in 1.5–2.2 s. It explains poorly but translates and summarizes well. Robi sends up to `(contextSize − 3,000) × 2.5` characters of context.
- **Claude** is `ClaudeLanguageModel(name: .sonnet5_5, auth: .apiKey(key), fixedEffort: .medium or .high)` from Anthropic's `ClaudeForFoundationModels` package, pinned to exactly 0.2.3 while it is in beta. Robi sends up to 60,000 characters. The key comes from the Keychain per request and is never kept in `RobiSettings`.

Both models stream in bursts: many characters at once, then nothing for a few hundred milliseconds. `RobiTextPacer` sits between `RobiModel.answer` and the card and reveals the answer word by word at an even pace. It waits 0.14 s before the first word, follows a smoothed arrival rate, and keeps about 0.2 s of text in reserve, so a short gap between bursts is covered by text that has already arrived. When the answer finishes or is stopped, the rest appears within 0.3 s. The newest words fade in over 0.24 s. With Reduce Motion the answer appears as it arrives, without fading. This only changes what the card shows; Copy, Replace and Paste use the full answer, and an answer brought back from another window appears in full at once.

**Stop** cancels the answer's task, which ends the response stream. On the Mac that ends generation. For Claude, the package then cancels its `URLSession` task, which closes the streaming connection. The Messages API has no call to cancel one request, so closing the stream is the only way to stop it. Anthropic's documentation does not say whether generation and billing stop the moment the connection closes; the hands-on check below covers it.

When the context has landmarks, the model reads them instead of the plain text, one per line as `[#12 button @ 812,44] Send`, where the position is the element's centre in window points, and the instructions give the window's size. It is asked to link what it mentions as `[the Send button](#12)`, to use only listed numbers, and to add no links to a rewrite or translation. The listing is cut to the same character budget as plain text.

Each question gets a fresh session with no history. The instructions quote the context as untrusted data. For **Do It**, typed questions, and suggested questions, the session also gets the app's enabled menu commands (up to 140, read off the main actor within 0.5 s) and `propose_menu_command`. That tool only accepts paths from the list and only proposes; the command runs when the person clicks **Run**, through `AXPress`.

### Pointing at the window

`RobiReferencedAnswer` takes the links out of the answer: their words stay and become references, and the syntax goes. A link to a number the context doesn't have keeps its words and points nowhere, so a made-up number can't ring the wrong thing. While the answer streams, text from a `[` that may still become a link is held back until it closes as one or turns out not to be (a newline, a second `[`, or 200 characters ends it), so the card never shows half the syntax and the pacer's text only grows. The card gives each revealed reference a private `x-dokk-robi-landmark:` link with a dotted underline, and its `openURL` action calls the controller. Copy, Replace, and Paste use `RobiModel.answerText`, with every link reduced to its words.

`RobiSpotlight` is a click-through `RobiPanel` laid over the target window, ordered just under Robi's panel, so it never takes a click, the keyboard, or focus. `RobiSpotlightView` dims the window by 20 % with a rounded cut-out around the landmark (5 pt of room, at least 28 × 22 pt, corners between 6 and 12 pt by its size) and a 2 pt accent ring on the cut-out's edge, with a glow on the dimmed side only, so the landmark stays sharp. A show lands the ring from 8 pt out and sends one pulse 14 pt outwards; both are distances, not scale factors, so a checkbox and a paragraph move the same. Another reference slides the cut-out and ring there. It fades after 5 s, when a new question is asked, and when the interaction ends, and it follows the window through `layout()`. Reduce Motion fades in place; Reduce Transparency drops the glow and dims by 32 %. VoiceOver hears "Showing “…” in the window" instead, and the overlay itself is hidden from it. A landmark that no longer falls inside the window, after a resize, gives a short "No longer in the window" note.

### Actions and suggested questions

`RobiIntent.actions(canReplace:)` orders the eleven built-in actions. An editable selection leads with Proofread, Improve, Translate, and Make Shorter; read-only selections, regions, and windows lead with Explain, Summarize, Translate, and Do It. `RobiSuggestionRow` shows as many leading actions as fit the row (four in English and German) through `ViewThatFits`, and the rest go in a More pill. Each action has its own prompt in `RobiAgent.ask(for:)`. Rewrites keep the text's language and return only the result, so Replace Selection can use them as they are. More opens an `NSMenu` popped up from the pill's own view. A SwiftUI `Menu` draws its label as a pop-up button on macOS and ignores `RobiPillStyle`.

`RobiSuggester` asks the on-device model for up to three questions about the context, through guided generation (`@Generable` with `.maximumCount(3)`). It starts only in `.prompting`, once the context is read, so only after a click or the shortcut. Robi does not suggest before the click, because that would mean reading a window the person never offered. Suggestions always run on the Mac, even when Claude answers. The context is capped at 4,000 characters and quoted as untrusted data, and the request is cancelled after 4.5 s or as soon as the prompt closes. Output is trimmed, and empty, repeated, overlong (over 48 characters), and built-in-action suggestions are dropped. A failure or a refusal shows nothing. The panel reserves the second row's height up front, so it does not resize when suggestions arrive. Suggestions that don't fit their row go under **Suggested** in the More menu. A suggested question is asked like a typed one and is counted as `suggested`. **Suggest questions** in Settings turns them off, and the switch is disabled when the on-device model is unavailable. Suggestions are not cached: each prompt asks again.

Private Cloud Compute is not used. Apple grants its entitlement only to App Store developers in the Small Business Program, and a Sparkle build without it fails with ModelManager error 1046. Running the person's `claude -p` or the Agent SDK on their Claude subscription is not allowed for third-party products, so Claude needs an API key. A DOKK back end that owns keys and cost can come later through the package's `.proxied` mode.

## Setting an answer aside

When focus leaves the pinned window while an answer is being written or shown, the tracker reports `.switchedAway` and `RobiController.park()` moves the card's `RobiExchange`, the answer's task, and its selection into one `RobiParked`. The task keeps running. Every answer has a generation number, and its updates go to the card if that generation is on screen, to `RobiParked` if it was set aside, and nowhere otherwise. Robi then follows focus with `RobiParkedBadge` on its face.

When the set-aside window is focused again, `show(_:)` restores the card and pins the window. A window that closed or was minimized while pinned ends the interaction (`.windowGone`). A set-aside window that closes is noticed on the next focus change through `RobiWindowServer.exists`, since the tracker watches only the focused window. A new question, `halt()`, or ten minutes drop it, and dropping a running answer cancels it like Stop.

The card is not kept on screen for the background window. Robi's panel floats above every app, so it would cover the window in front.

## Focus and input

- Robi's panel is borderless and non-activating, and its hosting view accepts the first click. Hovering and clicking never activate DOKK.
- For typing, the panel becomes key without activating DOKK. The spike confirmed that keystrokes reach the field while the app stays frontmost and keeps the menu bar.
- Dismissing resigns key, so the keyboard goes back to the app.
- **Paste into** puts the answer on the clipboard, posts ⌘V to the app's process, and restores the person's clipboard 0.9 s later, unless they copied something new in the meantime.
- The ⌥⇧⌘R shortcut is a Carbon hot key with ID 17 under the signature Radar and Find a Window use. If another app owns the combination, Settings says so and clicking Robi still works.

## Settings, analytics, and Discovery

`RobiStore` keeps `RobiSettings` under `robi.settings.v1`, apart from `DockSettings`, because no display can override Robi. Every field decodes leniently. `RobiAPIKeyStore` keeps the key as a this-device-only generic password that is not synchronized.

Product analytics are count-only: `robi_opened`, `robi_answered`, `robi_action` (including `point` for a clicked reference), and `setting_changed` with `area = robi`. Model calls go to PostHog LLM analytics through `AIObservability`, like DOKK's other model calls: `robi_answer` for both models, with token usage, errors, and stopped answers, and `robi_suggest_questions`, under one trace per interaction. They carry the prompt, the instructions, and the answer in full. The API key is never part of them, and pictures are noted, not sent. See [ANALYTICS.md](ANALYTICS.md#ai-observability).

The Discovery callout `robi` announces Robi once on launch. **Turn On** enables it and opens Settings when Accessibility is still missing.

## Privacy

Robi reads a window only after a click or the shortcut. Text and pictures live in memory for one request and are dropped when the card closes. Nothing is written to disk. Suggested questions always come from the on-device model. With Claude, the question and its context go from the Mac straight to Anthropic with the person's key. DOKK runs no server in between. When the person shares usage statistics, each request and answer also goes to PostHog in full, as for DOKK's other AI features; Robi's settings, the Privacy card, and the tour say so.

## Known limitations

- Robi trails a window by about one frame when SkyLight is unavailable and the window is resized by its edges. AX notifications arrive at about 10 Hz.
- During a Space switch animation the panel can be visible for a moment before it moves to the new focused window.
- Apps that draw text without accessibility, such as games and canvases, give Robi only the region picture and recognized text.
- Menu commands cover what an app puts in its menu bar. Actions that exist only as buttons inside a window are not proposed.
- Inside placement on a maximized window covers the middle of its title bar. Benn accepted this on 2026-10-24.
- The tab moves along the top edge only. The side and bottom edges would need the prompt bar and card to open sideways or upwards.
- The prompt bar and card stay centred on the tab, so with the tab near a corner they overhang the window's side, kept on the display. Shifting them back over the window would make the tab jump sideways as it widens into the bar.
- Landmarks are read once, when the context is picked. Content that scrolls or reflows afterwards leaves the spotlight on the old spot, and a resize moves elements anchored to the right or bottom edge away from where it rings them.
- Only text, headings, fields, and labelled controls become landmarks. Unlabelled icons, canvas content, and pictures inside a web page can be pointed at only when Vision reads text in them.
- Tab positions are saved per app, so two windows of an app share one position after DOKK restarts. Per-window positions last until DOKK quits.

## Not yet exercised by hand

The build compiles and the geometry and settings tests compile. DOKK was not launched while building Robi. These still need a hands-on run:

- Real hover, clicks, drags, and resizes on Ghostty, Claude Desktop, a Chromium browser, Xcode, and Finder, on displays with different scales.
- Spaces, full screen, Mission Control, Stage Manager, sleep and wake.
- Selection-first flow in Electron and Chromium apps, Replace Selection, Paste into a terminal, and Run on a proposed command.
- Claude with a real key at both effort levels, and the key prompt in the card.
- Switch windows while an answer streams, then come back: the card returns, still streaming or complete, and Replace and Paste still reach the first window. Close that window from another one and check that the dot goes away on the next focus change.
- Stop during a long Claude answer: the Anthropic Console's usage for that request should show fewer output tokens than an unstopped answer to the same question.
- VoiceOver on the face and the selection sheet, Reduce Motion, and Reduce Transparency.
- The More menu from the non-activating panel, with the app staying in front. Suggested questions on a selection, a region, and a window, including how often the first one after launch misses the 4.5 s timeout.
- Pointing: references in answers from both models, the spotlight on windows on displays with different scales and on a display left of the primary one, following a moved window, Reduce Motion and Reduce Transparency, and the VoiceOver announcement.
- Attach picture: on, off, and flipped after the window was read; without Screen Recording; and the fallback picture with the switch off.
- LLM analytics: `robi_answer` and `robi_suggest_questions` arriving in PostHog with token counts for Claude, a failed request's `$ai_error`, and a stopped answer.
- Dragging the tab, above and inside, idle and with the bar open: clicks still click, the tab follows the pointer without lag, rubber-bands at the corners, and comes back in the same spot after switching windows and after relaunching.
