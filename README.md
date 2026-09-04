# DeeDock

A native macOS Dock alternative. It should look like the Dock, behave like the Dock, and feel like the Dock—with the flexibility macOS should have shipped.

Familiar by default. Precise when you want control.

## Status

The native dock and the first three customization slices are implemented for macOS 27: native Liquid Glass, pointer magnification, pinned and running applications, folder stacks, Session Capsules, a Shelf tile, a Trash tile, Window Peek, Dock Modes, window-aware application menus, position/appearance settings, and one dock per connected desktop display. Each dock can sit on the bottom, top, left, or right edge. Apps and folders can be arranged by drag-and-drop, imported from Finder, and copied between display docks. Named Dock Modes switch every display's pins and app visibility together. Display-independent appearance and behavior settings still use shared defaults with optional per-display overrides. A first-launch tour introduces the dock and guides hiding the macOS Dock. See [acceptance notes](docs/ACCEPTANCE.md) for what has been checked and what still needs hands-on validation.

## What we are building

The macOS Dock is the reference for visual quality, interaction, and responsiveness. DeeDock should earn its place through everyday use: recognizable app icons, predictable activation, clear running state, natural hover and motion, and reliable drag interactions.

The product roadmap includes:

- **A dock per monitor (implemented):** independent pins, shared defaults, per-setting overrides, and remembered disconnected displays.
- **Precise placement, implemented:** bottom, top, left, or right edge; alignment, along-edge offset, and distance from the chosen reference edge.
- **Activation zones (implemented):** choose dock-position or screen-edge triggering, length, depth, along-edge offset, and reveal timing.
- **Size and appearance (implemented):** icon size, spacing, magnification, running indicators, background visibility, and configurable idle fading.
- **Behavior:** auto-hide, reveal/hide delays, and ten animation styles are implemented; broader interaction preferences remain planned.

These are product goals, not a finished feature specification. Exact options, ranges, defaults, and delivery order will be decided slice by slice.

## What good feels like

- Useful defaults before opening Settings; advanced controls stay discoverable without making normal use complicated.
- A dock that responds immediately without stealing focus just because the pointer entered it.
- Materials, spacing, shadows, labels, menus, and animation that belong on macOS.
- Consistent behavior across display arrangements, scaling, Spaces, full-screen apps, and sleep/wake.
- Keyboard access, VoiceOver labels, and respect for Reduce Motion and Reduce Transparency.
- Low idle resource use and smooth pointer interaction. Performance claims require measurement.
- A clear way to quit and return to the system Dock. Coexistence and replacement behavior need an explicit design.

## Technical direction

Use Swift and Apple's native frameworks. Keep the existing Xcode app project as the build entry point.

- **SwiftUI** for declarative presentation and Settings.
- **AppKit** for precise dock window/panel placement, activation policy, pointer handling, and desktop lifecycle integration where SwiftUI alone is insufficient.
- **Small, explicit models** for dock items, display configuration, placement, and visibility behavior, separated from rendering and OS integration.
- **Local preferences** for configuration. A core Dock experience should not depend on a server or account.

This is a direction, not an instruction to scaffold every subsystem now. Introduce boundaries when the first consuming feature needs them. Prefer public APIs and document platform limitations rather than promising full parity before proving feasibility.

## Open the project

Open `DeeDock.xcodeproj` in Xcode, select the `DeeDock` scheme and **My Mac**, then run when you want to inspect the dock.

Current configuration:

| Setting | Value |
| --- | --- |
| Platform | macOS only |
| Deployment target | macOS 27.0 |
| Swift language mode | Swift 5 (`SWIFT_VERSION = 5.0`) |
| Default actor isolation | MainActor |
| Approachable concurrency | Enabled |
| App Sandbox | Enabled |
| External package dependencies | None |

Use Xcode 27 and macOS 27. The app retains the original Swift language mode, App Sandbox, and signing configuration. Distribution and broader OS support are not part of this slice. DeeDock requests Accessibility or Screen Recording access only after an explicit Enable or Allow action; it never asks at startup. DeeDock does not change the system Dock’s preferences.

## Working in this repository

Read [AGENTS.md](AGENTS.md) for implementation guidance, scope boundaries, and validation expectations.

Three project-local agent skills are installed under `.agents/skills`: SwiftUI Expert, Swift Concurrency, and Swift Testing. See [docs/SKILLS.md](docs/SKILLS.md) for their purpose, pinned sources, and update instructions. They add development guidance, not app dependencies.

## Using DeeDock

DeeDock starts as a menu-bar app, without a normal document window or a second icon in the system Dock. By default, each dock is centered above its display’s usable bottom edge, leaving room for the system Dock when macOS reserves that space. If the system Dock auto-hides, its transient reveal can overlap DeeDock; dedicated coexistence controls are future work.

- Click an icon to open or activate its application. Click the foreground application's icon to hide all of its windows; click again to show and activate it.
- Hover to magnify nearby icons and see an app-name label. Running applications have a dot toward the selected screen edge by default. In Appearance, choose Dot, Bar, Square, Target Lock, Orbit, Stardust, Power Badge, Glitch, Plasma, Hologram, Solar Flare, Prism, Lava Chrome, Singularity, or Hidden from the Running indicators gallery, in shared defaults or for an individual display.
- Keep the pointer over a running app to open Window Peek, or press Space on an app while using Focus Dock. With usable Window Access, cards select individual windows. Screen Recording supplies fresh thumbnail images and can still enumerate preview cards when sandboxed Window Access fails; those capture-only cards activate the app. Without either permission, Peek keeps an app-level Show App action.
- Plasma, Hologram, Solar Flare, Prism, Lava Chrome, Singularity, and Glitch are Metal layer effects that read the app's own artwork: the light follows the icon's real silhouette and borrows its colours, and each app draws a different figure from a seed derived from its bundle identifier, so the same app always looks the same. Lava Chrome melts the icon's own corners and edges, Singularity puts an orbiting black hole that lenses and swallows part of the artwork, and Glitch slips its rows sideways and separates its colour channels. **Animate indicators** switches motion on for those seven and for Stardust; it is on by default, honours Reduce Motion, and stops while a dock is hidden or has faded out.
- Neon and Aura were withdrawn. A saved preference naming either migrates to Plasma and Solar Flare respectively, rather than failing to load.
- Right-click an app for opening and Finder commands, running-app commands, and **Pin** or **Unpin**. Running-app commands include Hide or Show, Bring All to Front, and cooperative Quit. One icon represents every matching regular process, so those commands apply to all matching instances. Pins belong to that display and persist across restarts; unpinned running apps remain visible on every dock until they quit.
- Initially pinned apps are Finder, Safari, Mail, Calendar, and System Settings when installed. Newly opened regular apps join the running section automatically.
- Choose **Focus Dock** from the DeeDock menu-bar item or app menu. It targets the enabled dock under the pointer, falling back to the primary enabled dock and then the first enabled display in Settings. Left/right arrows select an app on top and bottom docks; up/down arrows select an app on side docks. Return opens it, Space opens Window Peek for a running app, and Escape returns focus to the previous app. An outline marks the keyboard-selected icon, independently of running indicators. Only one dock has keyboard focus at a time; the command is disabled when all docks are disabled.
- Choose a named configuration from **Dock Mode** in the menu-bar item, or press M in Focus Dock to open the keyboard mode picker. A mode changes every display's pins and App Visibility together; it does not launch, quit, hide, or reorder running-only apps.
- Choose **Quit DeeDock** from the menu-bar item or app menu to close it.

The default icons are 48 points, with 4-point item spacing and 6-point glass padding. Crowded docks reduce icon size to 32 points before scrolling along the dock, horizontally above or below, or vertically beside the display. Reduce Motion disables magnification, and Reduce Transparency uses an opaque native background.

Enabled docks stay visible by default; auto-hide is opt-in under Behavior. Folder stacks, Session Capsules, the Shelf, Trash, and Window Peek are implemented.

## Dock Modes

Open **Settings → Modes** to create, rename, duplicate, reorder, activate, or delete named configurations. DeeDock keeps at least one mode. New modes copy the active mode, while names must be non-empty and unique without regard to capitalization. Deleting the active mode selects the nearest remaining configuration.

Each mode owns the ordered app and folder pins for every remembered display, plus the shared App Visibility choice and any display-specific App Visibility overrides. Pinning, unpinning, reordering, folder presentation changes, and App Visibility edits apply directly to the active mode. Appearance, placement, auto-hide, Trash, Window Peek, and other controls remain independent.

The menu-bar **Dock Mode** submenu switches configurations across all connected docks after the new choice has saved successfully. **Previous Mode** toggles between the last two configurations. During Focus Dock, press M, use Up or Down, then Return; Escape closes the picker without switching. Switching is unavailable while a native menu, file picker, or drag operation is active, and closes open Window Peek and folder panels before changing the docks.

Existing installations migrate their current display pin lists and App Visibility values into an initial **Default** mode. The older preference keys remain for rollback but are no longer authoritative. If the modes document is corrupt, DeeDock continues with the recoverable legacy layout, blocks persistent mode and pin edits, and offers an explicit reset in Settings rather than silently overwriting the stored evidence.

## Launch at login

Open **Settings → General → Launch at Login** to start DeeDock automatically when you sign in. General sits above Shared Defaults and applies to the whole app. Appearance remains the initial Settings pane. Search for login, startup, or automatic launch to find General.

The toggle reflects macOS’s registration status. It stays off until approval is granted. If approval is required, use **Open System Settings…** to open Login Items, or **Cancel Request** to withdraw the registration. Returning to the Settings window refreshes the status, including changes made outside DeeDock. An unavailable status provides Refresh and the System Settings link. Errors appear in General without automatic retries.

Turning off Launch at Login prevents future automatic launches and leaves DeeDock running. Login startup follows normal startup: configured docks and the menu-bar item appear without opening Settings or deliberately taking foreground focus. General remains usable if display settings have a storage error, and Restore Defaults does not change login registration.

The implementation uses `SMAppService.mainApp`; it stores no duplicate preference and installs no helper or launch-agent plist. Registration is opt-in. Real registration and logout/login acceptance require a consistently signed installed copy; see [acceptance notes](docs/ACCEPTANCE.md#launch-at-login).

## Window-aware application menus

Open **Settings → Features → Permissions** to manage Window Access and Screen Recording. Each row reports Enabled, Not Enabled, or Unavailable. The Enable buttons are the only actions that ask macOS for consent; **Open System Settings…** and **Check Again** manage and refresh the external grants. Permissions and the Window Peek controls below them apply to the app as a whole. DeeDock stores no copy of permission state.

Application-level actions do not need Accessibility access. For a running app, its context menu can Hide or Show every matching instance, Bring All to Front, or request a cooperative Quit. Available app bundles also offer Open, Open Files, and Show in Finder. These commands remain available when window access is off.

When window access is enabled, a menu opens immediately with **Loading Windows…**, then replaces that row with the app's top-level standard windows and dialogs. Select a row to restore a minimized window when supported, activate its owning app, and raise that exact window. Main windows are marked, untitled windows receive a localized fallback, and duplicate titles stay separate. The same commands are exposed as VoiceOver actions.

Window discovery and selection use the public macOS Accessibility API. Moving between Spaces and full-screen transitions is best-effort because public APIs do not expose complete Space ownership or guarantee activation. Windows owned by unusual helper processes may not appear under the regular app represented by the icon.

Window Peek uses one-shot ScreenCaptureKit screenshots only while a Peek is visible. It keeps images in memory for that presentation and never records audio, shows the pointer, or writes window contents to disk. Accessibility and Screen Recording windows are matched conservatively by process, title, and bounds. When Accessibility discovery is unavailable, ScreenCaptureKit metadata supplies capture-only cards; selecting one activates the app because no exact AX handle exists. Minimized, protected, ambiguous, and unavailable captures keep a card with app artwork instead of risking the wrong image. Current-Space filtering is not offered because public APIs do not expose dependable Space identity.

## First launch

The first time DeeDock runs, a tour opens over the desktop. The docks are already live behind it, so every page describes something you can see. Seven pages: what DeeDock is, a guide to hiding the macOS Dock, placement, running indicators, auto-hide, one dock per display, and a closing page with the launch-at-login toggle.

Closing the window counts as finishing. The tour does not reappear on the next launch, whether you completed it or dismissed it on the first page. Choose **Welcome to DeeDock** from the menu-bar item or the app menu to see it again; reopening never changes what is stored.

One page changes a setting; the rest only demonstrate. **Put it where you want it** lets you click a screen edge, which sets **Edge** in shared defaults and moves the docks immediately. It writes shared defaults only and leaves per-display overrides alone, so a display already overriding that control keeps its own value, and the change is reversible in Settings.

That page carries a prompt line under its illustration and its handles respond to the pointer. The prompt is the only signal that a page is interactive; pages without one do nothing when clicked.

The macOS Dock page opens **System Settings → Desktop & Dock** and reports whether the Dock is still holding desktop space, updating as you change it. DeeDock never writes the system Dock's preferences; the page asks and then observes. The reading compares each screen's full and visible frames, because an App Sandbox cannot read another application's preferences: turning on *Automatically hide and show the Dock* releases the space and clears the status, while moving the Dock to another edge does not. The page can be skipped.

The illustrations use production code, not artwork. Placement runs the same `DockPlacement` calculation as a real dock, the running indicators are drawn by `DockIconIndicator` and `DockRunningIndicator`, and the auto-hide page is driven by the real `DockVisibilityController`. Reduce Motion holds a single frame on every page and cross-fades between them instead of sliding; Reduce Transparency uses opaque backgrounds. Only the visible page animates.

## Arrange pins with drag-and-drop

- Drag a pinned app along the dock to reorder it. Drag a running app into the pinned section to pin it at that position. Running-only order remains automatic.
- Drop one or more application bundles or ordinary folders from Finder into the pinned section. Mixed app-and-folder batches are accepted in Finder order. The whole batch must be pinnable: plain files, packages, aliases, unreadable items, and DeeDock itself reject the pin operation. Existing pins move into the dropped block; duplicate app identities and resolved folder locations appear only once.
- Drag an app onto another display’s DeeDock to pin it there without removing the source pin. An existing destination pin moves to the chosen position.
- Drag a pin at least 64 points outside its dock to see **Unpin**, then release to unpin it. Returning closer or pressing Escape cancels removal. Releasing over another DeeDock that rejects the drop keeps the source pin. Running apps remain in the running section after unpinning; applications are never quit or deleted.
- During dragging, magnification settles to resting icon sizes and a live gap shows insertion. Overflowing docks scroll near their viewport edges. A hidden dock uses its existing activation zone and reveal delay; the source and revealed destination stay visible during the relevant interaction.
- Pin edits save only when a drop completes. Cancelled drags restore the saved arrangement. Invalid batches are rejected together, and save errors appear on the affected dock.

Right-click a pin for **Move Left** and **Move Right** on a top or bottom dock, or **Move Up** and **Move Down** on a side dock. **Pin on Display…** works with every edge. With **Focus Dock** active, hold Option with the corresponding arrow key to reorder the selected pin; ordinary arrows navigate. VoiceOver exposes equivalent move and destination actions. The Pin on Display menu appends a new pin and leaves an existing destination pin in place.

Finder imports retain read-only security-scoped bookmarks so user-selected application bundles and folders can remain accessible after restart. Application-only lists migrate once to typed v3 pins; the older bytes remain untouched for rollback and recovery. DeeDock uses app-scoped bookmarks for persistent pins; the separate Trash drop path requests read/write access only to items the user explicitly supplies. No Accessibility grant or system Dock preference changes are involved. Trash commands use a separate Finder Automation grant described below. Missing applications and unresolved folders remain visible as unavailable pins.

Selecting multiple pins within DeeDock remains outside this slice. File and folder opening is described below. Runtime acceptance for dragging, focus, auto-hide, cross-display copying, and sandbox access remains pending; see the latest acceptance entry.

## Folder stacks

Click a pinned folder to open one transient stack inward from its dock icon. Only one stack can be open across all displays. The header shows the Finder folder name and a per-pin Grid/List/Smart choice. Grid and List sort visible children by localized name. Smart uses Apple Intelligence on file metadata to build a grouped list without reading file contents. It organizes the 60 most recently modified children and keeps any remainder in More Items.

The stack shows the current folder's immediate children. Click a child to select it, then press Space for Quick Look without opening an app. Space or Escape closes the preview; arrow keys switch the preview to another child. Double-click or press Return to open a file, package, or alias. Opening a subfolder browses it inside the same stack. Use Back or Delete to return to its parent. The context menu also provides Quick Look and Show in Finder.

Hold a dragged file over a pinned folder to spring-open its stack, then hover over subfolders to browse deeper. Drop onto a subfolder or the current folder's background to copy the files there. The copy cursor identifies the operation; source files stay in place. Existing names cause an error, with no replacement, and a failure reports how many items were copied before it occurred. Copies run off the main actor and keep their file access until completion, even if the panel closes. Packages, aliases, symbolic links, and file promises are not spring-loaded folders.

Drag one child to Finder or another app through the native file-drag session; that destination and modifier keys negotiate copy or move. A cancelled outgoing drag leaves a manually opened stack open. A stack opened by a drag closes when that drag ends without a drop into it.

The source dock stays revealed and suppresses fading and tooltips while its stack is open. The panel closes after a successful open or drag, outside click, Escape, another stack opening, source removal/hiding, display removal, sleep, or shutdown. Failed opens remain visible with a retryable inline error. Directory changes are watched only while the panel is open.

Focus Dock can open a stack with Return. Arrow keys navigate its children, Return opens, Space previews, Delete goes back, and Escape closes the preview before returning focus to the source folder. Tab reaches the Grid/List/Smart control. VoiceOver exposes opening, Finder reveal, presentation, move, display-copy, and unpin actions.

Fan and Automatic presentations, search, multi-selection, file promises, move operations into stacks, and persistent utility windows remain planned.

## Features

**Settings → Features** collects DeeDock's opt-in capabilities: Session Capsules, the Shelf, the Trash tile, and Window Peek with its Window Access and Screen Recording permissions. It sits beside General and Modes, above the Defaults section, because everything in it is app-wide.

That is the distinction the sidebar draws. Panes under **Defaults** describe how a dock looks and where it sits, so each display can override them individually. A feature is either on or off for DeeDock as a whole; no display holds its own copy. Appearance, Position, and Behavior keep their per-display overrides exactly as before.

## Session Capsules

Session Capsules save mental context without restoring window geometry. Open the shared Capsules tile, choose up to twelve visible windows, and create a draft. DeeDock captures those windows once with ScreenCaptureKit, runs on-device Vision OCR, and gives the images plus window metadata to the system default Apple Intelligence model. Foundation Models produces typed structured output for the title, summary, and unfinished tasks; the prompt never asks for JSON. If the model is unavailable or generation fails, DeeDock creates a plain editable draft from the selected window metadata instead.

Nothing is saved until you review the draft and choose **Save Capsule**. Raw screenshots and recognized text remain in memory only for draft creation and are discarded afterward. Each saved checkpoint then appears beside the collection tile as its own temporary, title-bearing Dock item until you delete it. The persisted capsule contains the approved text, optional personal note, application bundle identities, and window titles. **Resume** reopens missing applications and uses Accessibility to raise the first exact title match when available, otherwise it activates a referenced app. It deliberately does not move, resize, or rearrange windows.

The underlying window-context service is feature-neutral: its public values contain current window identity, application identity, bounds, one-time imagery, and OCR. The planned Window Scout can reuse that capture boundary without depending on the Capsules repository or UI.

## Shelf

The Shelf is a staging area for files you are carrying somewhere else. Drop files on it, walk to another Space, display, or full-screen app, and drag them back out. It appears before Trash in the trailing utility area, shares that divider, and is enabled by default. Under **Features → Shelf**, turn it off for the whole app.

One Shelf is shared by every dock, so an item staged on one display is immediately on all of them. Its contents are independent of the active Dock Mode. The tile stays visible when empty, so the target never moves; a badge shows the item count once something is staged.

**The Shelf never touches the filesystem.** An item is a security-scoped reference to a file that stays exactly where it was. Dragging an item out hands other applications an ordinary file URL, exactly as Finder would, and the item deliberately stays on the Shelf: taking something out is a copy of the reference, not a hand-off. Nothing is moved, copied, or deleted.

Click the tile, press Return while it is selected in Focus Dock, or choose **Open Shelf** to open the panel. Each item shows its Quick Look thumbnail — the same artwork Finder draws, not a generic type icon — with the enclosing folder and when it was staged. Drag the tile itself to take every staged reference at once. Items animate as they arrive and leave, unless Reduce Motion is on.

Double-click an item to open it with its default application. Right-click for **Open**, **Show in Finder**, **Copy**, **Select All**, **Remove from Shelf**, and **Clear Shelf**; each command names how many items it acts on and applies to the whole selection. The header carries an **Arrange** menu with Date Added, Name, and Smart. Smart uses Apple Intelligence to group the Shelf's available file metadata in a list and keeps missing references in Unavailable. The List/Grid switch returns with its previous choice when you leave Smart. Both choices persist with the Shelf itself.

Keyboard, while the panel is open: Up and Down select, Return opens, ⌘R shows in Finder, ⌘C copies, ⌘A selects everything, Delete removes the selection, and Escape drops a multiple selection before it closes the panel.

Select items the way a Finder list does: click to replace the selection, Command-click to toggle one, Shift-click to extend from the last, and drag across empty space to sweep a rubber band. The band never starts on an item or over the scroller, so pressing an item still drags it and the list still scrolls. Dragging any selected item carries the whole selection at once; dragging an unselected one carries just that item.

Removal is always explicit. Use a row's Remove, **Clear Shelf…** from the tile menu or the panel header, or drag an item onto the dock's Trash tile — that drop reads **Remove from Shelf**, discards the reference, and leaves the file on disk. A Finder batch dropped on Trash still reads **Move to Trash** and still trashes; the two paths stay distinct because a Shelf drag also carries a private pasteboard type that only DeeDock reads.

The Shelf holds at most 50 items; a larger drop is accepted up to the limit and reports the rest on the initiating dock. A file that is moved or deleted stays listed as unavailable rather than disappearing, so you can see what happened and remove it yourself. Unreadable stored bytes are reported and never overwritten.

Keyboard, while the panel is open: Up and Down select, Return shows the selected item in Finder, Delete removes it, and Escape returns focus to the dock. Only one dock popover is open at a time, so opening the Shelf closes an open folder stack and the reverse.

Select a Shelf item and press Space, or choose Quick Look from its context menu, to preview it inside the panel. Space or Escape returns to the list. Up and Down preview the previous or next item. A preview holds the file access until its native view closes.

Reordering, auto-expiry, and multiple named shelves remain planned.

## Trash

Trash appears as the final tile after its own divider and is enabled by default. Under **Features → Trash**, turn it off for the whole app. The tile is independent of the pinned and running sections, including their hidden and collapsed states.

Click Trash, press Return while it is selected in Focus Dock, or choose **Open Trash** from its menu to open Trash in Finder. VoiceOver exposes its name, status, hint, and actions. The first explicit Open or Empty command asks for permission to automate Finder. DeeDock does not read the protected Trash directory directly. After permission exists, a serialized Finder item-count check every two seconds keeps the empty/full artwork synchronized with changes made by Finder or the system Dock.

Drop one or more files, folders, or packages from Finder directly on the tile to move the complete batch to Trash through `NSWorkspace`. The exact tile highlights and shows **Move to Trash**. Security-scoped access remains alive until macOS completes the operation; failures are reported on the initiating dock. Internal pin drags cannot target Trash, and dropping onto Trash never alters DeeDock's pin configuration.

The context menu and VoiceOver offer **Empty Trash…** only when Trash contains items. **Features → Trash → Confirm before emptying Trash** controls DeeDock's native destructive warning. Confirmation is on by default and applies to every display. DeeDock then asks Finder to empty Trash. Finder owns the protected home and mounted-volume Trash locations. DeeDock's sandbox entitlements allow Apple events only for Finder, with the Finder Trash scripting access group plus a Finder-only compatibility exception for opening and counting. It receives no general home-directory access and uses no deprecated workspace operation, Finder UI scripting, or private API.

## Open files and folders in an app

Drag files, document packages, or folders from Finder onto an available app icon. The outlined target shows **Open in {app}**. Releasing sends the complete batch to that app. DeeDock lets the receiving app decide which document types it supports. Files are opened in place; DeeDock does not move, copy, or save them.

Application bundles still use the pinning behavior above. Mixing applications and documents rejects the whole batch. Web links, pasted content, and promised files are not supported. While **Checking items…** is visible, the batch is not yet ready to drop. Missing or inaccessible items reject the batch before handoff.

Hover over a collapsed pinned or running section for half a second to expose its apps. The previous expansion state returns after the drag ends. Drop onto an app, not the section button. Completely hidden sections remain hidden. Auto-hidden docks use their configured activation zone and reveal delay; overflow scrolling remains available during dragging.

Spring-loading uses the macOS hover and Force Click preferences. Dwelling on an app can activate it or launch it if closed, without sending the files. You can then continue dragging into its window. Leaving an icon cancels pending activation, but a launch already submitted to macOS cannot be undone. A completed spring activation does not quit or hide the app when the drag ends.

Known limitation on the development Mac: Escape cancels a Finder drag before switching apps, but did not cancel after spring activation. The same failure occurred when switching with Command-Tab without using DeeDock. Escape cancellation after an app switch is therefore not guaranteed in this environment.

Right-click an available app and choose **Open Files…** to select files and folders in a native picker. VoiceOver exposes the same action. With **Focus Dock**, select an app and press **⌘O**. One picker is shared by all displays; it retains the app selected when it opened. Cancelling restores the originating dock selection or previous app when DeeDock still owns focus.

Each completed drop or picker confirmation submits its own batch, including consecutive drops onto an app that is still launching. Failures appear on the initiating dock. A successful macOS handoff does not prove that the receiving app displayed every item. Document access is temporary, with no saved bookmarks or document history. See the [acceptance record](docs/ACCEPTANCE.md) for build evidence and outstanding runtime checks.

## Position and appearance settings

Choose **Settings…** from the menu-bar item or app menu (⌘, while DeeDock is active). The single native Settings window applies valid edits immediately and saves them automatically.

| Control | Range / options | Default |
| --- | --- | --- |
| Icon size | 32–96 points | 48 |
| Maximum magnification | 1.0×–2.0×, in 0.05 steps | 1.4× |
| Item spacing | 0–24 points | 4 |
| Edge | Bottom / Top / Left / Right | Bottom |
| Alignment | Left / Center / Right above or below; Top / Center / Bottom beside | Center |
| Along-edge offset | −1,000 to +1,000 points | 0 |
| Edge distance | 0–300 points | 8 |
| Position relative to | Usable desktop / Screen edge | Usable desktop |

Numeric controls support sliders and locale-aware typed values. Invalid drafts never enter layout calculations; leaving the field restores the last accepted value. **Restore Defaults** on the Defaults page resets shared configuration only and preserves display overrides, visibility, and pins. Unreadable saved settings are left intact and reported in Settings; Restore Defaults explicitly replaces them.

Positive along-edge offsets move right on top and bottom docks and down on side docks. Edge distance measures from the reference frame to the outer edge of the glass. Placement keeps the magnification envelope on the display, so alignment and large offsets can be constrained near an edge. Requested values remain saved across geometry changes. Crowded docks may use smaller icons than requested before scrolling; the requested size returns when space is available.

Top placement always uses **Usable desktop**. Its **Position relative to** picker is disabled and explains the menu-bar and notch restriction. The saved reference choice, including a display override or inheritance, returns when another edge is selected. Top icons stay upright, with indicators above, magnification and labels below, and outward animations moving upward. Activation remains a separate setting; a physical top-edge activation zone can also reveal the menu bar.

A 1.0× maximum disables magnification; Reduce Motion also disables it without changing the saved preference. Glass thickness stays fixed during hover. Icons magnify inward and labels remain upright in a separate inward area. Screen-edge positioning can overlap the system Dock; neither mode changes macOS preferences. Settings resolve separately for each display. Auto-hide and activation behavior can be configured separately in the Behavior pane.

Changing edges reuses the same alignment, offset, edge distance, and activation dimensions. Both side docks order pins and running apps from top to bottom. Pin order and keyboard selection survive edge changes. Switching between horizontal and vertical layout resets scrolling to the start unless keyboard focus requires revealing the selected app; switching between edges on the same axis preserves scrolling. Edge changes apply immediately and cancel obsolete drag and visibility work. Old settings load as bottom placement.

## Background and idle fading

Appearance includes background and idle controls in shared defaults and per-display overrides. Existing installations keep their visible background and do not fade until **Fade when idle** is enabled.

| Control | Range / options | Default |
| --- | --- | --- |
| Show background | On / Off | On |
| Fade when idle | On / Off | Off |
| Fade target | Entire dock / Background only / Icons and indicators only | Entire dock |
| Idle opacity | 0–100% of normal appearance, in 5% steps | 40% |
| Idle delay | 0–30 seconds, in 1-second steps | 3 seconds |
| Fade-out duration | 0–2 seconds, in 0.05-second steps | 0.3 seconds |
| Restore duration | 0–0.5 seconds, in 0.05-second steps | 0.1 seconds |

Turning off the background leaves floating icons with the same geometry and hit regions. When enabled, the background uses native Liquid Glass without a steady opacity modifier. The former Background opacity preference remains stored for compatibility but no longer changes the material; its slider has been removed.

Idle means no interaction with that display's dock. Working elsewhere allows it to fade. Idle opacity multiplies normal appearance. At 50% idle opacity, Entire dock temporarily fades the background and icons to 50%. This intentionally weakens the glass while idle; Icons and indicators only preserves native glass throughout the idle period. Labels, keyboard outlines, launch progress, and error feedback retain full opacity.

Pointer entry, keyboard focus, VoiceOver focus, dragging, menus, mouse-button interaction, and errors restore visibility and prevent further fading during interaction. Even at 0% idle opacity, the dock retains its hit regions and restores on pointer entry. Auto-hide takes precedence; hidden docks do not schedule idle fading, and every reveal starts at normal opacity. Sleep, display refreshes, and teardown cancel stale deadlines. Each dock owns its own idle timing.

Reduce Motion restores instantly and caps fade-out at 0.1 seconds. Reduce Transparency suppresses idle fading and uses an opaque background when enabled, while preserving saved preferences. A hidden background stays hidden. The Normal and Idle samples show the effective appearance; **Play Preview** includes the configured idle delay and cancels when settings change or the view closes.

Compilation is verified; hands-on acceptance for material opacity, restoration timing, and native interaction remains pending in the [acceptance record](docs/ACCEPTANCE.md).

## App visibility and section buttons

Under **Behavior → App visibility**, choose **Show all**, **Hide running apps**, **Collapse running apps**, **Hide pinned apps**, or **Collapse pinned apps**. Each display can override the shared default independently. Only one section can be hidden or collapsed at a time. Show all is the default.

Pinned apps remain in the pinned section while running. The running section contains only unpinned running apps. Hiding a section removes its icons from the dock without changing saved pins or quitting apps.

Collapse replaces a section with a group button showing its app count, including zero. Click the button to expand or collapse the section. The button stays before its apps when expanded. Expansion survives auto-hide, pointer exit, app launches, and sleep while that dock remains alive. Restarting, recreating the dock, or changing its effective visibility choice starts it collapsed.

Group buttons participate in Focus Dock navigation. Press Return or Space to toggle the selected group. VoiceOver announces its action, count, and expanded state. Hidden apps are excluded from navigation and hit testing. Groups follow the dock's icon fading settings while keyboard outlines stay visible.

Hold a valid app drag over a collapsed pinned-group button for 0.5 seconds to expose insertion positions. The section returns to its previous expansion state when the drag ends. Dropping directly on the button appends pins. Completely hidden pins reject direct drops; **Pin** and **Pin on Display** remain available through app menus.

## App-name tooltip presets

Under **Appearance → App names**, choose one complete preset. Every choice combines its design, placement, hover delay, and entrance. Shared defaults and independent per-display overrides work like running indicators. **Classic** preserves the original rounded material label; **Off** hides visual labels while keeping accessible app names.

| Preset | Design | Placement | Hover delay and entrance |
| --- | --- | --- | --- |
| Classic | Rounded material | Inward | Immediate, instant |
| Glass pill | Bordered material capsule | Inward | 0.15 seconds, fade |
| Compact | Small material label | Inward | 0.35 seconds, fade |
| Plain | Text with contrast shadow | Inward | Immediate, instant |
| Bold | Larger semibold text on an opaque plate | Inward | 0.15 seconds, fade |
| Outline | Opaque plate with a fine outline | Inward | 0.20 seconds, fade |
| Accent | Accent-colored capsule | Inward | 0.15 seconds, fade |
| Speech bubble | Material bubble with a pointer | Inward | 0.20 seconds, lift |
| Name card | App icon and up to two name lines | Inward | 0.40 seconds, fade |
| Leading tag | Material label with an accent rule | Before icon | 0.15 seconds, slide |
| Trailing tag | Material label with an accent rule | After icon | 0.15 seconds, slide |
| Leading outline | Compact outlined label | Before icon | 0.30 seconds, fade |
| Trailing pill | Accent-tinted material capsule | After icon | 0.30 seconds, fade |
| Dock caption | Material capsule | Dock center | Immediate, crossfade |
| Dock title | Larger text on an opaque plate | Dock center | 0.20 seconds, crossfade |
| Lift | Rounded material | Inward | 0.20 seconds, lift |
| Pop | Accent-bordered material | Inward | 0.15 seconds, restrained scale |
| Spectrum | Static multicolor border | Inward | 0.20 seconds, fade |

Inward means toward the desktop, adapting to each dock edge. Before and after follow app order within the inward label area. Dock-centered captions stay anchored to the visible resting dock. Labels stay upright and fit within the display and viewport. Before and after try the opposite side when space is limited, then fall back to the icon's inward position.

Keyboard-selected entries show their label immediately. Pointer exit, dragging, menus, hiding, and error feedback clear labels and pending delays. Tooltips remain click-through, do not steal focus, and do not extend auto-hide retention. Showing one does not resize the dock. Section buttons use the chosen design for their localized action label.

The gallery uses the same renderer as the dock. **Play Preview** demonstrates the selected delay and entrance on an inert sample. Reduce Motion substitutes short fades for movement and scale; Reduce Transparency uses opaque backgrounds. No preset runs a continuous animation.

Compilation is checked separately from hands-on appearance and interaction. See the [acceptance record](docs/ACCEPTANCE.md) for the outstanding runtime scenarios.

## Displays and inheritance

The Settings sidebar retains the appearance/position panes, search, cards, and live previews, and adds connected and remembered displays. App-wide General, Modes, and Features sit above them. **Defaults** changes the shared values. Selecting a display exposes **Show Dock** and the same controls. Editing a control creates an explicit override; **Use Default** restores inheritance for that control. **Use Defaults** clears all appearance, position, and behavior overrides on that display while preserving its pins and visibility.

With multiple connected desktop displays, selecting a display in the active Settings window outlines that monitor and shows its name. The marker stays across settings categories, works when that display’s dock is disabled, and disappears on Defaults, disconnected profiles, or leaving Settings. Mirrored followers do not receive separate markers.

New displays start enabled and copy the primary display’s current pins once, including an empty list. Later pin changes remain local. Disconnected displays remain editable and recover their settings on reconnect. You can disable every dock and reopen Settings from the menu-bar item to recover.

Display profiles use public ColorSync UUIDs, independent of screen order, names, and primary-display changes. Mirroring renders one dock using the mirror source’s profile; follower profiles remain saved. If macOS supplies missing or duplicate identity, affected docks use temporary state for that connection and Settings reports the limitation. Temporary profiles never replace saved profiles.

Existing settings remain shared defaults under their original preferences key. Legacy pins are retained and migrated to the initial primary profile; each display’s pins are stored separately. Malformed data is reported without silently replacing saved bytes. Unreadable display metadata blocks profile edits; unreadable pins block pin writes for that display. This slice adds no profile deletion or repair screen.

## Auto-hide and activation zones

Choose **Behavior** under Defaults or a display to configure automatic hiding. Every control supports an independent per-display override. Existing installations remain always visible until you turn auto-hide on.

| Control | Range / options | Default |
| --- | --- | --- |
| Automatically hide | On / Off | Off |
| Activation location | Dock position / Screen edge | Dock position |
| Activation length | Dock length / Custom length | Dock length |
| Custom length | 32–8,192 points | 320 |
| Activation depth | 1–90 points | 8 |
| Along-edge offset | −4,096 to +4,096 points | 0 |
| Reveal delay | 0–2 seconds | 0.10 |
| Hide delay | 0–5 seconds | 0.40 |
| Animation duration | 0–1 second | 0.20 |

A dock-position zone starts at the resting glass outer edge; a screen-edge zone starts at the selected physical display edge. Length follows the dock axis and depth extends inward. Dock length follows the resting glass, independently of hover magnification. Geometry fits to the current display without rewriting requested dimensions. The Settings diagram illustrates the zone and the safe approach area. **Show Zone** draws a click-through outline for 10 seconds on the selected connected, enabled desktop display. It updates during edits and closes with Settings or a changed selection.

Resting the pointer in the zone starts the reveal delay; leaving cancels it. The revealed dock stays visible while the pointer is over it or in the connecting approach area, and while you use a mouse button, its context menu, keyboard focus, or VoiceOver focus. After interaction ends and the pointer leaves, the hide delay begins. Re-entering cancels the delay or reverses an ongoing hide. Trigger and approach areas never capture clicks.

**Focus Dock** reveals its target immediately and preserves existing keyboard navigation. Hidden docks have no invisible click targets or accessibility elements. A launch error reveals only its initiating dock and holds it until dismissed; pending launches alone do not prevent hiding.

### Animation styles

All ten are available immediately, grouped in Settings with a descriptive subtitle. The table describes bottom placement:

| Group | Name | Effect |
| --- | --- | --- |
| Smooth Operators | **Glide & Seek** (default) | Slide down and fade |
| Smooth Operators | Slip Away | Slide down |
| Smooth Operators | Ghost Mode | Fade |
| Taking the Scenic Route | Up, Up & Away | Lift and fade |
| Taking the Scenic Route | Exit Stage Left | Slide left and fade |
| Taking the Scenic Route | Right on Cue | Slide right and fade |
| A Little Drama | Mini Me | Scale and fade |
| A Little Drama | Curtain Call | Vertical wipe |
| A Little Drama | Squeeze Play | Horizontal wipe |
| A Little Drama | Boing Voyage | Bounce and fade |

On side docks, slides move outward through the selected edge; lift and bounce move inward. The former left/right effects move up/down and are named Up & Out and Down & Out. The inward lift is named Into the Room. Wipes close across the thickness or along the length, and scaling anchors at the outer-edge midpoint. Settings previews and descriptions follow the selected edge.

Reveal reverses the selected hiding sequence. **Play Preview** runs an inert sample; selecting a style does not repeatedly trigger live docks. A zero duration makes transitions instant. Reduce Motion replaces movement, scaling, and wipes with a fade lasting at most 0.10 seconds, including in previews. Glass remains fixed-thickness during hover, and visibility effects use a separate presentation transform and clipping envelope.

Auto-hide does not inspect overlapping app windows, use pressure gestures, modify the system Dock, or request permissions. Screen-edge triggering may also reveal the system Dock. Runtime acceptance for these interactions is still pending.

## Implementation and validation

One application catalog owns workspace observation, running order, icon caching, and duplicate-suppressed launches. A coordinator reconciles display snapshots and owns global pointer monitoring and exclusive keyboard focus. Each panel keeps its own pins, selection, hover, scroll state, geometry, and error feedback. Removing a dock invalidates its launch callbacks without cancelling shared work; quitting cancels pending tasks and removes observers, monitors, and panels. Geometry, identity resolution, ordering, focus routing, and visibility policy are independent of native windows. Each panel owns a cancellable visibility controller with monotonic deadlines and finite animation ticks; idle settled docks schedule no visibility work. Drawing and native click passthrough share the same animation sample, while context-menu tracking is scoped to the owning dock.

The shared `DeeDock` scheme includes `DeeDockTests`, an unhosted Swift Testing target compiling the same model, ordering, persistence, and geometry sources used by the app. Its tests cover geometry, magnification, overflow, ordering, favorites persistence, display identity and focus policy, migration, empty-pin seeding, per-setting inheritance, stale launch/cancellation behavior, auto-hide deadlines and reversals, ten animation styles and masks, behavior migration, and temporary preview lifetimes without launching DeeDock. Drag coverage adds batch insertion, cross-display pin independence, deliberate unpinning, cancellation, insertion geometry, import validation, bookmark compatibility, blocked writes, and visibility holds. Tests have been compiled, but not executed. Follow `AGENTS.md` before running them.

## Source organization

- `DeeDock/App` owns the app entry point and native lifecycle composition.
- `DeeDock/Dock/Models` defines application references, render snapshots, and ordering.
- `DeeDock/Dock/Layout` contains platform-independent placement and magnification calculations.
- `DeeDock/Dock/Persistence` and `Services` isolate preferences and workspace operations.
- `DeeDock/Displays` supplies display snapshots, persistent identity resolution, and selection policies.
- `DeeDock/Dock/Coordination` owns panel reconciliation and application-wide event/focus routing.
- `DeeDock/Dock/State` holds the shared application catalog and per-panel stores and interaction geometry.
- `DeeDock/Dock/Windowing` owns each AppKit panel, native context menu, and local focus/handler lifecycle.
- `DeeDock/Dock/Dragging` separates pin-editing policy, temporary insertion slots, native sessions, Finder validation, and drag feedback.
- `DeeDock/Dock/Visibility` separates activation geometry, animation samples, visibility state, scheduling, and temporary zone outlines.
- `DeeDock/Dock/Popover` owns the transient panel shell shared by folder stacks and the Shelf: its window, dismissal monitors, animation, inward placement geometry, and pointer shape, plus the presenter that keeps only one open.
- `DeeDock/Dock/Shelf` holds the staged-item model, its repository, the shared controller, security-scoped access, the panel state and view, the native drag sources, and the coordinator.
- `DeeDock/Dock/SemanticStacks` owns metadata-only grouping, streamed result repair, process-lifetime caching, and the Foundation Models adapter shared by folder stacks and the Shelf. Identical live requests share one generation. When Smart is selected, Shelf edits silently prepare the next grouping after a short debounce unless Low Power Mode is active.
- `DeeDock/Dock/Views` separates live-store wiring, scrolling, surface composition, app buttons, material, and errors.
- `DeeDock/Dock/PreviewSupport` provides deterministic fixtures with inert actions, compiled only in Debug.
- `DeeDock/Settings` groups shared settings, display profiles and persistence, sidebar navigation, and focused native controls. `General` contains the app-owned login-item controller, service boundary, and presentation. `Features` holds the app-wide pane for the Shelf, Trash, and Window Peek.
- `DeeDock/Onboarding` holds the first-launch tour: step and reservation models, the completion record, navigation and screen-observation state, its AppKit window, and views. The models stay free of SwiftUI so the test target does not pull in the settings view layer.
- `DeeDockTests` contains the focused model tests. The Xcode **Test Model Sources** group references the app's source files for the unhosted test target; it does not contain copies.

Useful previews live beside their views: pinned/running/unavailable apps, launch progress, empty content, error text, and dark appearance with reduced motion/transparency. Open the canvas for `DockContentView`, `DockAppButton`, `DockBackgroundView`, or `DockErrorBanner`. Settings previews include multiple displays, per-setting overrides, and a disconnected display using isolated in-memory stores. Previews do not construct live workspace services, read saved pins, or launch applications. Production accessibility values are read from SwiftUI's environment and passed into the same presentation components used by previews.

## UI copy and translation

All app-owned UI copy lives in [Localizable.xcstrings](DeeDock/Resources/Localizable.xcstrings): menu commands, Pin/Unpin actions, accessibility text, empty-state guidance, and errors. Edit the English values there and add translations in Xcode. Stable keys generate typed Swift symbols automatically; translator comments explain each string and named placeholder.

Use generated `LocalizedStringResource` symbols in SwiftUI and defer error-message localization until display. Use `String(localized:)` for AppKit APIs that require a resolved string. Application names and underlying system error descriptions are supplied by macOS and are displayed as provided. Keep persistent storage keys separate from translated UI copy.

## Action Tiles

Open **Settings → Features → Action Tiles**, choose **Load Shortcuts**, and pin a shortcut. Tiles appear in the same order on every display, independently of Dock Modes. Settings provides Run, Cancel, Unpin, and ordering controls. Up to 30 tiles can be pinned.

Click a tile or select it in Focus Dock and press Return to run it. Drop files onto a tile to pass them as shortcut input. Each tile allows one run at a time and shows progress, a completion checkmark, or an error. Saved shortcut identifiers survive renames; shortcuts that are removed or unavailable report the helper's error. DeeDock never retries a run automatically.

Shortcuts may show their own permission or input dialogs. Configure the shortcut itself to save or display its output; DeeDock does not retain output files. Cancel stops the CLI invocation and cannot undo actions already performed. Shortcut discovery and execution use Apple's documented `shortcuts` command, with arguments passed directly rather than through a shell.

## Focus Sessions

Choose **Dock Mode → Start Focus Session → [mode]** from the menu bar, or use the timer button beside a mode in **Settings → Modes**. DeeDock activates that mode and starts a shared timer. You can also start from the already-active mode. Only one session can run or pause at a time; switching modes later does not replace its timer.

The timer tile appears on every display. Its ring shows time remaining. Click it for **Pause**, **Resume**, **Add 5 Minutes**, and **Finish**. A finished session keeps a checkmark tile until dismissed or replaced by a new session. **Save Session Capsule** opens the usual window-selection and draft-review flow; finishing never captures or saves anything automatically.

Set the next session's duration, from 1 to 180 minutes, in **Settings → Features → Focus Sessions**. The default is 25 minutes. Completion animation is optional and off by default, and Reduce Motion suppresses it. There are no streaks or history scores.

Running timers use a saved wall-clock deadline, so sleep and app downtime count. Paused timers retain their remaining duration. Reopening DeeDock after the deadline marks the session finished without replaying a celebration. Changing focus defaults does not restart the current session. Renaming or deleting a Dock Mode does not erase a timer already started from it.
