# DDock Discovery

Discovery suggests unused capabilities using local signals. **Settings → Features → DDock Discovery → Suggest useful features** disables the engine and closes its callout immediately. Discovery defaults to on. Museum capture remains a separate opt-in.

## Catalog and scheduling

`DiscoveryProposal.catalog` owns each recipe's signal, threshold, calm interval, localized copy, destination, and snooze interval. v0 ships one recipe: three observed clipboard changes followed by at least five seconds without another observed change suggest Clipboard Museum.

The queue is FIFO and deduplicated by proposal ID. Only its first proposal is considered, so a snoozed or uncalm head also holds later entries. The first presentation can happen as soon as its calm window and native gates permit it. Each actual presentation starts a 69-second cadence. Subsequent opportunities occur at 69-second intervals; blocked slots are skipped, and delayed timer delivery never produces a catch-up burst. Actual presentation time restarts the cadence so timer delays cannot shorten minimum spacing. These intervals are lower bounds, subject to main-run-loop delivery.

There is one panel globally, with caps of two presentations per process session and three per local calendar day. Daily counts and the most recent presentation time persist across launches. The queue and signal counts do not persist. Disabling Discovery clears pending signals and the queue while retaining usage, dismissals, snoozes, and caps.

**Tomorrow**, Escape, automatic timeout, and interruption snooze that proposal for 24 hours. Another three observed changes are required to qualify again. **Don't show again** suppresses it permanently. Opening Museum through any current entry point, or enabling collection, permanently records Museum use even with Discovery disabled. An existing collection or enabled capture also suppresses the tip on upgrade. An old Museum visit that left no collection and disabled capture cannot be reconstructed.

## Presentation and local signals

The callout is a nonactivating AppKit panel with native SwiftUI buttons and English and German copy. It appears in the upper trailing corner of the usable frame of an enabled dock display, preferring the display under the pointer. It never activates DDock on presentation. An explicit click can give the panel keyboard focus. The CTA opens the existing Museum window without enabling capture.

Discovery blocks presentation during DDock drag, menu, file-picker, popover, keyboard Dock focus, or Focus Session activity. It also blocks while DDock has an ordinary window or sheet open, while mouse buttons are held outside the callout, and until system input has been idle for two seconds. Sleep and inactive sessions stop metadata observation. Space changes, application activation, and drag events dismiss an existing callout. Visible callouts also recheck native gates each second.

Like Atmosphere, Discovery conservatively treats another process's layer-zero window covering the target display as fullscreen. This uses public Quartz bounds with the AppKit-to-Quartz coordinate conversion. Missing window-list data blocks presentation. No Accessibility permission is requested. Public window bounds cannot reliably identify another application's modal sheets, and v0 does not claim to detect those. DDock has no general system Focus/DND preference to reuse; Discovery suppresses all active DDock Focus Sessions.

The panel has no motion. Reduce Transparency uses an opaque system background. After 20 seconds the callout snoozes unless the pointer is inside it, it owns keyboard focus, or VoiceOver is enabled.

The reused `ClipboardMuseumWatcher` polls only `NSPasteboard.changeCount`, never clipboard contents. This works while Museum collection is off. AppKit has no public clipboard-change notification. Several writes between polls count as one observation, and metadata alone cannot distinguish a copy command from another clipboard write. Discovery stores no clipboard content or source application and makes no network requests. Observation stops when disabled, suspended, permanently dismissed, or Museum use is recorded.

Local preferences live in `discovery.state.v1`. Unreadable data disables Discovery without overwriting it. Explicitly changing the Discovery switch repairs that preference document.

## Backlog

File-drop tips for Throw or Window Peek, heavy-use Launcher tips, Modes tips, and long-unused pin tips remain planned. They have no active triggers in v0.

## Acceptance still required

- With an unused Museum and capture off, copy three separate items. Confirm no callout before five seconds after the last observed change. Confirm the CTA opens Museum without enabling capture.
- Snooze, dismiss forever, open Museum independently, and toggle Discovery. Confirm persistence across relaunch and no stacked panels.
- With a second injected catalog recipe, confirm FIFO ordering, blocked 69-second slots, minimum presentation spacing, and session and daily caps. No second production recipe is enabled merely for validation.
- Exercise drag, menus, sheets, file pickers, Focus Sessions, sleep, screen lock, Spaces, fullscreen windows, and monitor removal while a proposal is queued and visible.
- Check German copy, keyboard access and Escape, VoiceOver, Reduce Transparency, and display layouts with negative origins. Confirm presentation does not steal focus.

Automated tests and native interaction checks have not been run for this slice. Build evidence is recorded in `ACCEPTANCE.md`.
