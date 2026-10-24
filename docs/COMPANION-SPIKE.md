# Window companion spike

Status: research spike, 2026-10-24. Nothing here ships. The throwaway lab and probes live in `spikes/companion-lab/` and are reference only.

The idea: a small face that sits in a tab on top of whichever window has focus, in any app. The tab takes the window's title-bar color. The face sleeps while idle, wakes on hover, and on click enters selection mode, where its eyes follow the pointer. The user hands it a text selection, a dragged region, or the whole window. The tab then turns into a prompt bar, an agent answers, and where possible it acts inside that app.

All numbers below were measured on Benn's Mac: macOS 27.0 (Darwin 27), Xcode 27A266a, with Ghostty, Claude Desktop, Helium, T3 Code, Finder, Xcode, WhatsApp and System Settings running. The probes ran from a shell that inherits T3 Code's Accessibility and Screen Recording grants. No grants were changed.

## Verdict

It's buildable with public APIs plus one long-stable private call, and it can feel attached. The lab does the full loop on macOS 27:

1. It tracks the focused window and matches its title-bar color.
2. It wakes on hover, opens the selection overlay on click, and takes a dragged region.
3. It answers with the on-device model, which now accepts images.
4. It writes back by replacing the selection through Accessibility.

The hard limits are a one-frame lag that public APIs can predict away, an on-device model that is fast but not smart, and app actions that are only as good as each app's accessibility tree and menu bar.

## What the lab measured

### Tracking the focused window

| Signal | Result |
|---|---|
| Focused window through AX (`kAXFocusedWindowAttribute`) | 8 to 38 ms first query, works in every app tested |
| AX window to `CGWindowID` (private `_AXUIElementGetWindow`) | Worked for all 6 apps tested |
| One-window bounds read (`CGWindowListCreateDescriptionFromArray`) | 78 µs p50, 130 µs p95 |
| AX `kAXMovedNotification` during a real title-bar drag | 9 of 60 steps (about 10 Hz), 37 ms behind |
| SkyLight event 806 (moved) / 807 (resized) for another process's window | Every drag step, 23 ms after the event, from a normal process with SIP on |

During a title-bar drag the window server moves the window, not the app. The app only learns about it later, which is why AX lags. These are the distances the tab trailed a window dragged at 360 pt/s, read from the window server's bounds for both windows:

| Tracking mode (`LAB_TRACKING`) | p50 | p95 |
|---|---|---|
| `ax`, AX notifications only | 24 pt | 42 pt |
| `sls`, SkyLight 806/807 | 6 pt | 12 pt |
| `poll`, 120 Hz bounds read while a mouse button is down | 6 pt | 6 pt |
| `predict`, move from the drag events, check against bounds on mouse-up | **0 pt** | 6 pt |

`predict` is public API only (global `NSEvent` mouse monitors, which need no extra permission). It has to stop predicting when a title-bar drag doesn't move the window, for example a tab tear-off in a browser. The lab checks the real bounds on the fourth drag event and snaps back. The default mode is `predict` for drags plus SkyLight for every other move (keyboard snapping, window managers). AX remains the fallback.

True attachment, where the window server moves our window with another app's window, is not possible. yabai needs a Dock scripting addition with SIP partly disabled to order or group other apps' windows. JankyBorders and AltTab only move their own windows in response to these notifications, as the lab does.

### Looking like part of the window

- A one-shot ScreenCaptureKit capture of a 5 pt strip under the tab's footprint gives the tint in 80 to 140 ms. Sampled tints: Ghostty `#363A42`, Claude `#1B1B1B`, T3 Code `#090909`, light Cocoa window `#FFFFFF`.
- Sample under the tab, not across the title bar. Helium's tab strip is `#3E455A` at the left and `#222A3E` in the center.
- Liquid Glass toolbars (Finder) are translucent, so the tint follows the content behind them. The lab resamples on every wake.
- Maximized and full-screen windows leave no room above. The lab flips the tab into an "inside" placement that hangs from the top edge like a notch ([screenshot](../spikes/companion-lab/inside-helium.png)). It looks native, but on Helium it covered part of the tab title. That needs a design decision.
- The light-mode result ([screenshot](../spikes/companion-lab/awake-light.png)) is close to the Figma: white tab, concave flares into the title bar, dark face pill.

### Reading context

| Source | Result |
|---|---|
| Selected text, Cocoa (`kAXSelectedTextAttribute`) | Read and replaced across processes. Selection bounds come back for highlighting. |
| Selected text, T3 Code (Electron) | `AXSelectedText` and `AXValue` both settable |
| Ghostty terminal | `AXTextArea` holds the visible screen (54 lines, 3.3k chars) with `AXSelectedText` and `AXReplaceRangeWithText`. Claude Code's output is readable without OCR. |
| Claude Desktop (Electron) | 893 elements, 14k chars already exposed |
| Helium (Chromium) | 43 elements until `AXEnhancedUserInterface` is set, then 1,303 elements, 25k chars, and an `AXWebArea` with 34 text-marker APIs. The call returns -25208 but works. `AXManualAccessibility` is Electron-only (-25205 here). |
| Full AX tree walk in Finder and System Settings | Over 1 s, so walks must be bounded |
| Region capture (ScreenCaptureKit `sourceRect`) | 116 ms |
| OCR (Vision `RecognizeTextRequest`) | 13 to 27 s for the first call in a process, then 50 to 150 ms. Prewarm when the feature is enabled. |

Rectangle and Hammerspoon document side effects of `AXEnhancedUserInterface` in Chromium (wrong frames during animated moves, extra accessibility cost). Turn it on only for an explicit whole-window request and restore it afterwards, as the lab does.

### Answering

- The on-device `SystemLanguageModel` on this Mac reports an 8,192-token context, vision and tool calling. It has no reasoning. Apple's docs still say 4,096, so read `contextSize` at runtime.
- With an image attached it answered in 1.5 to 2.2 s total, first token at 1.0 to 1.6 s.
- Quality matches the size. It translated well (one wrong verb), but its "explain" of a pangram was poor. Explanation-heavy use needs a stronger model.
- `PrivateCloudComputeLanguageModel` (32k, vision, tools, reasoning) reports available, but a request without the `com.apple.developer.private-cloud-compute` entitlement fails with ModelManager error 1046. Apple only grants it to App Store Small Business Program developers, so DOKK's Sparkle build can't use it. [Apple](https://developer.apple.com/private-cloud-compute/)
- Anthropic's [Claude for Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models) package (beta, OS 27) is a drop-in `LanguageModel` for the same `LanguageModelSession`, with tools, images and streaming. Auth is App Attest, a proxy, or an API key for development. Swapping the lab's model is one line.
- Running the user's `claude -p` or the Agent SDK on their Claude subscription is not allowed for third-party products without approval. [Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview), [legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)

### Acting in the app

- Replace the selection through AX: works (Cocoa text, Electron text areas).
- Paste through the clipboard plus ⌘V posted to the target pid. This is how dictation tools reach terminals and canvases. Built in the lab but not exercised.
- The menu bar is a command list every app exposes. 150 to 761 items per app, read in 100 to 230 ms (Ghostty 2.2 s, Xcode 0.9 s, so cache per app). The lab's model gets a `propose_menu_command` tool that only proposes. The user confirms with a button and the lab presses it with `AXPress`. Built but not exercised on a real app.
- macOS has no public API to read another app's App Intents or on-screen entities. AppleScript works for scriptable apps but prompts for Automation per app.

### Focus and input

- A borderless `.nonactivatingPanel` never activates DOKK on hover or click (`acceptsFirstMouse`), so the target app keeps its selection.
- Made key for the prompt, the panel received typed keys while the target app stayed frontmost and kept the menu bar. On dismiss, DOKK went inactive again.
- Selection mode puts a transparent sheet over the target window. It swallows the drag, so the app never sees it, and needs no event tap. A modifier plus drag anywhere, without clicking the face first, would need a `CGEventTap`. DOKK already holds Accessibility. Not built.

## Decisions so far (Benn, 2026-10-24)

- **Models.** The on-device model is the default. Claude is opt-in, through Anthropic's Claude for Foundation Models package or a direct Messages API client. The user supplies their own API key. A DOKK back end that owns the keys and the cost can come later. The package's `.proxied` mode already fits that.
- **Mockup.** [`docs/mockups/window-companion.html`](mockups/window-companion.html) reuses the lab's constants and measured tracking lag.

## Private APIs and their risk

| Call | Used for | Risk |
|---|---|---|
| `_AXUIElementGetWindow` | AX window to window ID | Low. Used for years by AltTab, Rectangle, Hammerspoon. DOKK's Atmosphere tracker avoids it with frame matching today. |
| `SLSRegisterConnectionNotifyProc` + `SLSRequestNotificationsForWindows`, events 806/807 | Non-drag moves and resizes | Medium. Event IDs come from reverse engineering, and AltTab reports per-window opt-in has been required since Sequoia. Gate it to macOS 27 like the Launch Services SPI, keep AX as fallback. |

Drag tracking needs neither of these.

## Suggested shape in DOKK

- **Tracker.** Grow `AtmosphereFocusedWindowTracker` into a shared focused-window service: AX for focus and semantics, drag prediction, gated SkyLight for other moves.
- **Panel.** One non-activating panel per focused window, SwiftUI content, above and inside placements, hidden for Mission Control (Dock `AXExpose*` notifications), secure input, and excluded apps.
- **Context.** AX selection first, then AX window text (terminal, Electron, Chromium on request), then region capture with OCR and the image. Reuse `ScreenCaptureWindowContextService` and `WindowMarkupLiveTextView`. Live Text over a frozen capture would also let users select text in apps with no AX text.
- **Agent.** `LanguageModelSession` with the on-device model by default (private, free, offline). Claude through Claude for Foundation Models as an opt-in with its own privacy copy. The Translation framework for translation.
- **Actions.** Copy, replace selection, paste, confirmed menu commands. Per-app adapters where it pays off: terminals (Claude Code) read AX text and paste into the prompt.
- **Another route.** DOKK could expose the focused window's context and these actions as an MCP server, so the user's own Claude Desktop or Claude Code can use them. Usage stays in Anthropic's apps.

## Not exercised

- Real hardware hover and drags on third-party windows. Drags and clicks were synthetic, on the lab's own throwaway window.
- Menu-command press and ⌘V paste into a real app.
- Spaces, full-screen transitions, Mission Control, Stage Manager, sleep and wake.
- Displays with different backing scales during a drag.
- Whether App Attest works for a Developer ID macOS app.
- Whether single `SCScreenshotManager` captures trigger the screen-capture indicator, and the effect of the monthly Screen Recording re-confirmation.

## Running the lab

Run it from T3 Code's terminal, which already holds the grants. Running it from another terminal makes macOS ask that terminal for Accessibility and Screen Recording.

```sh
spikes/companion-lab/lab/build.sh
spikes/companion-lab/lab/CompanionLabBin                         # predict + SkyLight
LAB_TRACKING=ax spikes/companion-lab/lab/CompanionLabBin         # compare: sls, poll, ax
```

It attaches to the frontmost app's focused window. Hover to wake it, click to select (drag a region, click for the whole window, Esc to cancel), then type or pick a suggestion. Ctrl-C quits. `LAB_TARGET_PID` or `LAB_TARGET_BUNDLE` pins a target without activating it. `LAB_DEMO=awake|select|prompt|answer` drives the states without input, for screenshots.

The probes in `spikes/companion-lab/probes/` are single-file `swiftc` programs (`-parse-as-library` for `inventory` and `fm`). The drag, focus and end-to-end probes post synthetic input against the throwaway `target` app only. They wait for 20 s of hardware idle and abort if the cursor leaves their path.
