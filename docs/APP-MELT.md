# App Fusion

App Fusion coordinates two distinct ordinary windows from the same or different apps. Each pair has shared
Liquid Glass controls and a group of two adjacent DDock icons. The separate App Compare feature captures window context and creates comparison cards.
Internal `AppMelt` types and localization keys retain their existing names.

## Create a pair

Three entry points supplement the menu-bar setup:

- Drag a window by its title area until an edge is within 32 points of another app's
  window. Hold it still for 1.5 seconds while the indicator fills, release, then click
  **Fuse windows**. This connects the two windows directly. Moving away cancels the
  indicator; the released offer expires after eight seconds. Ambiguous or stale window
  matches are rejected before pairing.
- Drag a running app's DDock icon over the center of another running app's icon. Hold
  for 0.65 seconds, then release to open setup with both apps selected. Icon edges retain
  ordinary reordering behavior. The drop does not change saved pins.
- Choose **Fuse with another app…** from an app icon's context menu. Drag another DDock
  app icon into either side of setup, then choose windows and connect as usual.

Proximity detection reuses the existing pointer monitors. It takes Quartz geometry
snapshots only during a possible title-bar drag, at most once per 120 ms of movement,
plus a final dwell check. There is no idle window polling. It performs no Accessibility
enumeration until the user clicks the offer. Display, Space, sleep, and session changes
cancel pending offers. Fullscreen and unsupported windows are subject to the usual
pairing checks.

The original menu-bar path remains available:

1. Open **App Fusion → Fuse windows** in DDock's menu-bar menu.
2. Choose an app for each side.
3. If needed, choose **Enable Window Access** and grant access in System Settings.
4. Choose **Launch / Refresh**. Both apps receive launch requests. If an app has no
   window, open one in that app and refresh again.
5. Choose a window for each app, then choose **Fuse windows**.

Setup stays open until pairing finishes. A failure keeps Restore and Unpair visible.
Transient AX startup failures are retried within the bounded launch wait; permission advice
is shown only when Window Access is actually denied.

A sole window is selected automatically. With multiple windows, you must choose one.
An app cannot join two pairs. DDock's own windows cannot be paired.

New pairs use the current source-window bounds to choose their display and starting position.
The group stays centered horizontally around those windows and retains their top content
edge where screen bounds allow. App minimum sizes and available screen space still constrain
placement. A short cyan outline traces the accepted outer frame, then fades into the glass
controls. The effect uses Core Animation with no per-frame Accessibility calls, intercepts no
input, and is removed on cancellation. Reduce Motion skips the effect.

The placement and reveal changes compiled successfully in the requested unsigned Debug build on
2026-09-18. The build exposed an async overload ambiguity in the chrome fade; explicitly
selecting the completion-handler overload fixed it. Native acceptance is still pending.

## Pair controls

Drag the shared title area to move the pair. Drag its bottom-right grip to resize it.
The slider sets the left window's share between 25% and 75%; release it to apply the
new proportion. The action menu also offers keyboard-accessible movement and size commands.
App-enforced minimum sizes enlarge the pair and update the split and chrome to match.
If the accepted sizes cannot fit on the chosen display, setup stays open with a size error.
Apps can still refuse a geometry change.

The shared minimize button minimizes both source windows. The two existing app icons move into the trailing
section inside one subtle enclosure, without duplicate icons in the pinned or running
sections. Click either member to restore and raise both. Each member’s context menu offers
Restore, Minimize, Close, and Unpair. These actions also remain in the App Fusion menu when
docks are disabled. Unpair animates the icons back to their ordinary sections. Saved pins
and their order are unchanged; Reduce Motion disables movement animation.

Close requests normal window closure from each app. Save dialogs remain under the
source apps' control. If you cancel closing, use Restore to resume the pair.
Unpair removes the shared controls and dock enclosure, leaving the windows in their current
positions and minimized states. An unavailable source pauses the pair with a recovery
message; Unpair removes it without choosing a replacement window.

## Platform boundaries

The windows remain owned by their apps, including their title bars. DDock adds narrow
panels around them; it does not embed, capture, or replace their content. Source windows
remain directly interactive. Window Access is required; Screen Recording is not.

Actions are sequential cross-process Accessibility requests, not atomic WindowServer
operations. A partial move or minimize can occur when an app refuses a request. DDock
pauses the pair, adds an error badge, and exposes Restore and Unpair. It does not retry
failed mutations automatically. The original apps' system Dock minimize targets remain.

The glass controls hide when another app or another document has focus. Native title-bar
moves and resizes reconcile after a short notification debounce; the shared title area
is the coordinated drag control. Fullscreen, modal sheets, missing metadata, permission
loss, and unsupported window control can pause the pair. Space, display, sleep, and
session changes hide the chrome and require an explicit Restore.

Pairs are session-only. Quitting DDock removes the controls and leaves the source windows
in place. It does not quit their apps or restore a saved layout. No app-pair preferences,
window titles, or document contents are persisted by App Fusion.

## Acceptance status

The macOS target is built during implementation. Builds establish compilation only.
No automated tests or automated visual suites were run. Live Xcode/My Mac checks with
App Store and Stocks reproduced the original failure: requested sizes below app minimums
prevented chrome presentation. Accepted-size reconciliation now presents the shared glass
header and combined dock item. Shared minimize was observed to retain the combined icon
with the minimized status. Restore exposed an AX timeout; the final build increases the
App Fusion service timeout to one second. After unlocking the Mac, the live check passed:
shared minimize showed “Paar minimiert,” clicking the combined dock icon restored
“Verbundene Fenster,” and the pair context menu contained no failure message.
The pair was left restored.

Native acceptance remains required for:

- Shared and native title-bar dragging, grip resizing, proportion limits, and app minimum sizes.
- Source-app initiated minimize/restore, cooperative close, save cancellation, and Unpair.
- Keyboard and VoiceOver controls, Reduce Transparency, and Reduce Motion.
- Negative display origins, vertical display arrangements, display removal, Spaces, fullscreen,
  sleep/wake, app termination, and revoked Window Access.
- Tight glass alignment, focus and stacking, and responsiveness during continuous dragging.

The adjacent-icon update preserves app render and keyboard identity across section changes.
Its focused macOS build is checked; native animation acceptance is tracked separately.

## Shared-chrome drag performance

Source inspection found that every pointer update ran the full resize path: six capability
checks, repeated window-list validation and geometry reads, followed by a refresh of every
dock store. Chrome waited for that work and forced immediate panel drawing.

Translation now preflights exact handles once per gesture and writes only the two positions
on the Accessibility actor. Pending input keeps only the newest frame. Dock refreshes and
geometry reconciliation are deferred until needed; chrome no longer forces synchronous
redrawing. Each position request has a 50 ms response budget. A timeout is reconciled on
release without retrying an old position. Resize and proportion changes retain the full
minimum-size negotiation. Cached handles are released on gesture completion and teardown.

The performance changes have not been built, tested, or profiled, per the user's instruction.
No measured FPS improvement is claimed. The adjacent-icon change compiled before that
instruction; its final animation adjustment and native visual acceptance are unverified.

The proximity offer, icon-to-icon drop, and setup drop entry points have not been built
or tested, per the user's instruction. CPU cost, native drag routing, focus, keyboard
access, multi-display placement, and window matching still need hands-on acceptance.

Latest compilation: `xcodebuild -project DeeDock.xcodeproj -scheme DeeDock -configuration Debug
-destination 'platform=macOS' -derivedDataPath /tmp/DeeDock-melt-build CODE_SIGNING_ALLOWED=NO build`
succeeded on 2026-09-18, including the proximity and dock entry points and drag performance
changes previously marked unbuilt above. Log: `/tmp/DeeDock-melt-build.log`. No tests or live
interaction checks were run.

Pairing readback now waits briefly for asynchronous AX size/position changes instead of
classifying the first stale bounds as a refusal. Mutations are not resent after an AX timeout;
only readback is repeated. The initial reveal remains pending through failed placement and
runs on the first successful Restore. Height mismatch and refused position have separate
localized recovery messages. This addresses identified code paths; the reported Stocks +
System Settings failure has not been reproduced or verified live.

Finder identity correction: a read-only live AX probe on 2026-09-18 found valid standard
Finder windows with exact AXWindows membership, but NSRunningApplication.launchDate was nil.
The mandatory launch-date guard therefore reported those windows as stale before pairing.
Window-control identity now falls back to the kernel process start time when AppKit supplies
no launch date; discovery, validation, movement, and close activation use the same identity.
The live fallback was non-nil and stable across two reads. The unsigned Debug app build
succeeded. A complete Finder pairing interaction has not been exercised with the rebuilt app.

Same-app pairs are supported through setup (choose the app on both sides) and window
proximity. Discovery enumerates each process once, and selection rejects duplicate window
handles. Same-app dock members have distinct render and keyboard identities. This change
has been statically reviewed but has not been built or tested.

Focus-loop correction: passive AX refresh no longer raises either member. Raising from a
focus notification could trigger another notification and cancel the refresh before its
foreground state was recorded, repeatedly raising the two windows. Explicit creation and
Restore still raise the group, with the exact previously focused member last (PID ordering
alone cannot preserve focus within a same-app pair). This change has not been built or
verified live.

## Finder folder tools

Finder + Finder pairs expose a folder button in the shared header. Its glass popover shows
both current paths and a Left → Right / Right → Left selector. **Open folder on other side**
changes only the destination window's folder. **Preview sync** compares regular file contents
recursively, including hidden files, and lists missing folders/files, differing files, and
unsupported entries. **Apply previewed changes** performs a one-shot merge. Replacement of
differing destination files is opt-in; destination-only files are never deleted. This is not
continuous synchronization, bidirectional conflict resolution, or a mirror/delete operation.
Symbolic links, source packages, and file/directory type conflicts are listed as skipped. Finder automation is
limited to folder/disk targets; virtual views and ambiguous window matches are rejected.

The selected direction animates a small cyan indicator while work is active. Reduce Motion
keeps it static, and Reduce Transparency removes the translucent indicator backing/glow.
Folder access can be granted with a folder picker restricted to the displayed location.
The existing Finder automation permission is reused; no entitlements were added.

Before applying, the two retained AX windows must still resolve to the preview's Finder IDs
and target paths. Source and destination root identities, path resolution, and previewed file
hashes are rechecked during copying. Coordinated file writes stage a sibling temporary copy
before replacement. Cancellation stops between cancellable steps, preserves completed copies,
and requires a new preview before retrying. Closing the popover, minimizing/closing/unpairing
the pair, or suspending it cancels pending work. File data and Finder scripts execute off the
main actor. No recurring polling or automatic file operations run outside user actions.

This implementation has not been built or tested. Finder scripting/Automation prompts,
folder-access prompts, cloud and external volumes, partial failures, cancellation, keyboard
and VoiceOver interaction, and the native glass animation require acceptance. Sync is a
content merge; metadata-only differences are not synchronized.

Finder tools follow-up: the live read-only script probe reproduced failed alias coercions
from unresolved Finder target references. Enumeration now materializes Finder's window list,
explicitly gets each target, and reads its file URL instead of coercing the reference to an
alias. The exact corrected query returned both reported folders. Navigation uses the same
explicit target resolution. Popover presentation is now tracked by the pair's tools state;
visibility recognizes DDock/Finder focus during interaction and schedules normal focus
validation on dismissal. Switching to another app still releases visibility. No file-copy or
navigation mutation was performed during this check; the updated native popover behavior
has not been exercised, and no build or automated tests were run.

Folder access picker follow-up: the picker is now an asynchronous sheet owned by the Melt
header rather than an unowned runModal panel. A separate interaction hold spans popover
closure, folder selection, and popover restoration. Pair suspension or teardown invalidates
the pending callback before dismissing the picker. Selected folder grants remain in the
pair's observable state and show an Access granted label when reopening the tools. Grants
are session-only, matching the pair lifetime; they do not promise access across app relaunch.
This change has been statically reviewed only; no build or live picker acceptance was run.

Window Peek cards now offer Fuse with another app in their context menu and accessibility
actions, in both ordinary and split previews. It closes Peek and opens Melt setup with the
source app selected. Windows are selected in setup: preview discovery tokens are not reused
after Peek closes, and the implementation does not guess a replacement by frame or title.
No build or tests were run for this menu addition.

## Finder-style frame and toolbar

The shared chrome now has a system-material header, straight side borders, and continuous
rounded outside corners at the top and bottom. Separate noninteractive border panels leave
both source windows clickable. The source apps retain their native title bars and rounding;
Fusion does not clip or replace another app's window. Its outer contour uses a shared
16-point continuous radius, not a private WindowServer corner-radius API.

The toolbar offers Finder folder tools, Compare with AI, Swap sides, and Tile presets.
Presets include 25/75, one-third/two-thirds, 50/50, two-thirds/one-third, and 75/25. The custom
slider stays inside the preset popover and applies only when requested. App minimum sizes
can change the accepted proportion. Fit expands the pair to its display's usable area;
Restore previous size returns to the saved layout. The green control performs this fit action,
not native fullscreen.

Undo layout restores the last completed Fusion toolbar or shared-drag layout change.
It does not undo file copies or moves made through the source apps' title bars. Move to display
lists connected displays when more than one is available. Narrow toolbars keep secondary
actions in the overflow menu. Unpair leaves the source windows open in place.

Swapping changes visual order without changing retained window or dock identities. Finder
paths and pending sync previews are invalidated when toolbar layouts change. Layout actions
cannot overlap Finder work or its folder picker. The existing open-folder-on-other-side action
remains inside Finder tools; a separate toolbar shortcut is deferred.

Compare opens a comparison tray owned by this pair, with fresh window metadata matched to
both visible sources. It keeps the existing explicit capture, input review, and generation
steps. Reopening preserves that tray's reviewed input or draft. Pair suspension releases
captured input, and unpairing closes the tray. The ordinary App Compare tray is unaffected.

This toolbar change received static source and localization review only. No build, app launch,
tests, or visual automation were run. Native acceptance is still required for the frame's
corner alignment and material seams, narrow toolbar overflow, keyboard/VoiceOver operation,
Finder sync after swapping, Compare selection after moving, undo, minimum-size constraints,
multiple displays, focus changes, and sleep/wake. No measured performance claim is made.

Toolbar reference refinement: related actions now share Liquid Glass capsules, with inset
hover/pressed/active fills, monochrome icons, and a divider before Unpair. Layout retains a
chevron; overflow shows only the ellipsis. Reduce Transparency uses an opaque capsule.
The change is presentation-only and has not been built or checked in the running app.

Toolbar focus follow-up: visibility now treats the shared header or resize panel holding
key focus as interaction with that pair, including the handoff when the tile popover closes.
Scoped key/resign notifications schedule the existing debounced visibility check and are
removed on teardown. Passive refresh still never raises or activates source windows, and
a different frontmost app still hides the chrome. This addresses a source-level cause of
chrome disappearing after a successful preset; the reported interaction needs native recheck.
No build, app launch, or tests were run.

## Change a side's window

Choose **Change window** in the toolbar, select **Left: [app]** or **Right: [app]**, and open
**Choose window…**. App submenus list discoverable ordinary windows, including minimized
windows. Windows already paired are disabled; apps owned by another pair are labeled and
disabled. The replaced window stays open in its existing position. The other side and split
are retained, subject to the new window's minimum sizes. Unsupported windows report an error.

App order uses activations observed during this DDock session, followed by the active app
and alphabetical fallback. This is not a historical per-window MRU list. Discovery happens
only on opening or refreshing the chooser, runs outside the main actor, and is canceled on
dismissal. An app that fails discovery does not discard results from the others.

Replacement transfers the chosen exact handle into the pair's lifetime before releasing
chooser handles. Finder tools, observers, dock identities, and chrome are updated for the new
membership. Layout undo and the pair's Compare tray are cleared because their sources changed.
Unfinished comparison work blocks replacement until it is saved or discarded.
A partial layout failure retains the new pair for explicit Restore or Unpair. No source app
is closed or launched. The change is statically reviewed only; no build, run, or tests were
performed. Native checks remain required for same-app replacements, swapped sides, minimized
windows, stale choices, minimum sizes, Finder-tool transitions, focus, and dock updates.

Monitor submenu follow-up: the overflow now uses a native NSMenu snapshot for each opening.
The pair retains interaction ownership across the entire tracking loop, including movement
into and out of the monitor submenu. Actions execute after tracking ends; dismantling the
button cancels tracking. Monitor IDs are resolved again by the existing move action. No
polling or repeated window activation was added. Static review only; no build, launch, or
tests were run. Native acceptance must check pointer movement into every monitor row, Escape,
click-away dismissal, and switching apps while the menu is open.

## Shared window picking in setup and the dock

The toolbar and setup now use `AppMeltWindowPickerState` and the same grouped SwiftUI picker.
Each setup side can select an open window directly; the application picker and launch/refresh
flow remain available for apps without an open window. Selecting the same retained window
for both sides is rejected even if discovery assigned it different tokens.

The dock's Fuse with another app entry now has an app/window submenu driven by the same
picker state, with a native menu adapter. Choosing a partner prefills the right side of setup;
the dock app is preferred in the left-side chooser. Open App Fusion remains a fallback.
Discovery starts only when that submenu opens. Setup adopts selected handles before the
menu releases its sessions, so closing or refreshing a chooser does not invalidate selections.
Ordinary dock window discovery does not rebuild the root while this submenu is tracking.

Static review only. No build, launch, or tests were run. Native checks remain for submenu
loading/tracking, same-app windows, duplicate selection, setup reopening, cancellation during
discovery, app-launch fallback, and transfer from the dock submenu into setup.
