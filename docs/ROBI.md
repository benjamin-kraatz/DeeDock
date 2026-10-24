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
| `Panels/` | `RobiPanel`, the non-activating panel, and `RobiSelectionSheet`, the sheet laid over the window in selection mode. |
| `State/` | `RobiModel`, `RobiEyes`, `RobiContext`, and `RobiIntent`. |
| `Context/` | Reading the selection, the window's accessibility text, and pictures, plus waking Electron and Chromium accessibility. |
| `Answering/` | `RobiAgent`, the menu-command tool, the actions that put answers back, and the ⌥⇧⌘R shortcut. |
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

## Reading context

1. **Selection.** `RobiSelectionReader` reads `kAXSelectedTextAttribute` from the focused element. Web content falls back to `AXSelectedTextMarkerRange` and `AXStringForTextMarkerRange`. Clicking Robi's non-activating panel leaves the app frontmost, so the selection is still the person's. Replace Selection writes the same attribute and works in native text views and Electron text areas.
2. **Web apps.** Electron and Chromium build their accessibility tree only for assistive apps. Robi sets `AXManualAccessibility` (Electron, no side effects) and, for apps that ship `chrome_100_percent.pak`, `AXEnhancedUserInterface` (Chromium). It reads the selection again 300 ms later. Chromium returns -25208 for that flag but builds the tree anyway: Helium went from 43 to 1,303 elements. Rectangle and Hammerspoon document that the flag can disturb window animations and adds Chromium work, so Robi restores it when the interaction ends.
3. **Whole window.** `RobiWindowText` walks the focused window's tree off the main actor, bounded to 0.4 s and 16,000 characters. A full walk of Finder or System Settings took over a second in the spike. Ghostty keeps the visible terminal, Claude Code included, in one `AXTextArea`. When the tree has under 200 characters, Robi captures the window and recognizes its text.
4. **Region.** The selection sheet takes the drag, so the app underneath never sees it. `RobiCapture.image` captures only the target window (`desktopIndependentWindow`), so Robi's panels and overlapping windows never appear. Pictures are capped at 1,568 px on the long side.

Vision's first recognition in a process took 13–27 s; later ones take 50–150 ms. `RobiCapture.prewarm()` runs once in the background when Robi starts.

## Answering

Both models run through one `LanguageModelSession`:

- **On-device** is `SystemLanguageModel.default`. On macOS 27 it reported an 8,192-token context, vision, and tool calling, and it answered a screenshot question in 1.5–2.2 s. It explains poorly but translates and summarizes well. Robi sends up to `(contextSize − 3,000) × 2.5` characters of context.
- **Claude** is `ClaudeLanguageModel(name: .sonnet5_5, auth: .apiKey(key), fixedEffort: .medium or .high)` from Anthropic's `ClaudeForFoundationModels` package, pinned to exactly 0.2.3 while it is in beta. Robi sends up to 60,000 characters. The key comes from the Keychain per request and is never kept in `RobiSettings`.

Each question gets a fresh session with no history. The instructions quote the context as untrusted data. For **Do It** and typed questions, the session also gets the app's enabled menu commands (up to 140, read off the main actor within 0.5 s) and `propose_menu_command`. That tool only accepts paths from the list and only proposes; the command runs when the person clicks **Run**, through `AXPress`.

Private Cloud Compute is not used. Apple grants its entitlement only to App Store developers in the Small Business Program, and a Sparkle build without it fails with ModelManager error 1046. Running the person's `claude -p` or the Agent SDK on their Claude subscription is not allowed for third-party products, so Claude needs an API key. A DOKK back end that owns keys and cost can come later through the package's `.proxied` mode.

## Focus and input

- Robi's panel is borderless and non-activating, and its hosting view accepts the first click. Hovering and clicking never activate DOKK.
- For typing, the panel becomes key without activating DOKK. The spike confirmed that keystrokes reach the field while the app stays frontmost and keeps the menu bar.
- Dismissing resigns key, so the keyboard goes back to the app.
- **Paste into** puts the answer on the clipboard, posts ⌘V to the app's process, and restores the person's clipboard 0.9 s later, unless they copied something new in the meantime.
- The ⌥⇧⌘R shortcut is a Carbon hot key with ID 17 under the signature Radar and Find a Window use. If another app owns the combination, Settings says so and clicking Robi still works.

## Settings, analytics, and Discovery

`RobiStore` keeps `RobiSettings` under `robi.settings.v1`, apart from `DockSettings`, because no display can override Robi. Every field decodes leniently. `RobiAPIKeyStore` keeps the key as a this-device-only generic password that is not synchronized.

Analytics are count-only: `robi_opened`, `robi_answered`, `robi_action`, and `setting_changed` with `area = robi`. See [ANALYTICS.md](ANALYTICS.md). Robi never calls `AIObservability`, which would send prompts and answers in full.

The Discovery callout `robi` announces Robi once on launch. **Turn On** enables it and opens Settings when Accessibility is still missing.

## Privacy

Robi reads a window only after a click or the shortcut. Text and pictures live in memory for one request and are dropped when the card closes. Nothing is written to disk or logged. With the on-device model nothing leaves the Mac. With Claude, the question and its context go from the Mac straight to Anthropic with the person's key. DOKK runs no server in between.

## Known limitations

- Robi trails a window by about one frame when SkyLight is unavailable and the window is resized by its edges. AX notifications arrive at about 10 Hz.
- During a Space switch animation the panel can be visible for a moment before it moves to the new focused window.
- Apps that draw text without accessibility, such as games and canvases, give Robi only the region picture and recognized text.
- Menu commands cover what an app puts in its menu bar. Actions that exist only as buttons inside a window are not proposed.
- Inside placement on a maximized window covers the middle of its title bar. Benn accepted this on 2026-10-24.

## Not yet exercised by hand

The build compiles and the geometry and settings tests compile. DOKK was not launched while building Robi. These still need a hands-on run:

- Real hover, clicks, drags, and resizes on Ghostty, Claude Desktop, a Chromium browser, Xcode, and Finder, on displays with different scales.
- Spaces, full screen, Mission Control, Stage Manager, sleep and wake.
- Selection-first flow in Electron and Chromium apps, Replace Selection, Paste into a terminal, and Run on a proposed command.
- Claude with a real key at both effort levels, and the key prompt in the card.
- VoiceOver on the face and the selection sheet, Reduce Motion, and Reduce Transparency.
