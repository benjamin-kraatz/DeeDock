# DOKK user guide

This guide describes every DOKK feature in detail. For a short overview, see the [README](../README.md). The [acceptance notes](ACCEPTANCE.md) record which behavior has been checked by hand and what still needs validation.

## Contents

- [Get started](#get-started)
- [Use the dock](#use-the-dock)
- [Arrange pins with drag-and-drop](#arrange-pins-with-drag-and-drop)
- [Open files and folders in an app](#open-files-and-folders-in-an-app)
- [Folder stacks](#folder-stacks)
- [Downloads and utility order](#downloads-and-utility-order)
- [Shelf](#shelf)
- [Trash](#trash)
- [External drives](#external-drives)
- [Windows](#windows)
- [Dock Modes](#dock-modes)
- [Focus Sessions](#focus-sessions)
- [Local History](#local-history)
- [Session Capsules](#session-capsules)
- [Action Tiles](#action-tiles)
- [App Launcher](#app-launcher)
- [App badges](#app-badges)
- [Atmosphere](#atmosphere)
- [DOKK Discovery](#dokk-discovery)
- [Settings](#settings)
- [App updates](#app-updates)
- [Deprecated features](#deprecated-features)

## Get started

DOKK starts as a menu-bar app without an icon in the macOS system Dock. DOKK appears in its own running-app section while Settings, Welcome, Window Search, Badge Memory, or an update window is open, including minimized windows. Closing the last of these windows removes the running entry; dock panels and hover previews do not count. Clicking DOKK's icon brings an existing window forward. Your running-section visibility settings still apply. By default, each dock is centered above its display’s usable bottom edge, leaving room for the system Dock when macOS reserves that space. If the system Dock auto-hides, its transient reveal can overlap DOKK; dedicated coexistence controls are future work.

### BIG DIKK

For the week around 14 February, 21 July, 22 August, and 14 November, DOKK calls itself BIG DIKK. The week is that date and the three days on either side, in the Mac's local time. Menus, settings, About, release notes, and the menu-bar wordmark use BIG DIKK. The app file stays `DOKK.app`, and folders such as Pictures/DOKK Markups keep their names. A launch keeps the name it started with.

### First launch

The first time DOKK runs, a tour opens over the desktop. The docks are already live behind it, so every page describes something you can see. Seven pages: what DOKK is, a guide to hiding the macOS Dock, placement, running indicators, auto-hide, one dock per display, and a closing page with the launch-at-login toggle.

Closing the window counts as finishing. The tour does not reappear on the next launch, whether you completed it or dismissed it on the first page. Choose **Welcome to DOKK** from the menu-bar item or the app menu to see it again; reopening never changes what is stored.

One page changes a setting; the rest only demonstrate. **Put it where you want it** lets you click a screen edge, which sets **Edge** in shared defaults and moves the docks immediately. It writes shared defaults only and leaves per-display overrides alone, so a display already overriding that control keeps its own value, and the change is reversible in Settings.

That page carries a prompt line under its illustration and its handles respond to the pointer. The prompt is the only signal that a page is interactive; pages without one do nothing when clicked.

The macOS Dock page opens **System Settings → Desktop & Dock** and reports whether the Dock is still holding desktop space, updating as you change it. DOKK never writes the system Dock's preferences; the page asks and then observes. The reading compares each screen's full and visible frames instead of reading the Dock's preferences. Turning on *Automatically hide and show the Dock* releases the space and clears the status. Moving the Dock to another edge does not. The page can be skipped.

The illustrations use production code, not artwork. Placement runs the same `DockPlacement` calculation as a real dock, the running indicators are drawn by `DockIconIndicator` and `DockRunningIndicator`, and the auto-hide page is driven by the real `DockVisibilityController`. Reduce Motion holds a single frame on every page and cross-fades between them instead of sliding; Reduce Transparency uses opaque backgrounds. Only the visible page animates.

## Use the dock

- Click an icon to open or activate its application. Click the foreground application's icon to hide all of its windows; click again to show and activate it.
- Hover to magnify nearby icons and see an app-name label. Running applications have a dot toward the selected screen edge by default. In Appearance, choose Dot, Bar, Square, Target Lock, Orbit, Stardust, Power Badge, or Hidden from the Running indicators gallery, in shared defaults or for an individual display.
- **Animate indicators** switches Stardust motion on. It is on by default, honours Reduce Motion, and stops while a dock is hidden or has faded out.
- Neon, Aura, and the withdrawn Metal styles (Plasma, Hologram, Solar Flare, Prism, Lava Chrome, Singularity, Glitch) load as Dot, rather than failing to load.
- Choose **Appearance → App launch animation** for Classic Bounce, Spring, Pulse, Wobble, Flip, or Indicator only. Classic Bounce is the default. Select a preset to preview it; shared defaults and per-display overrides are supported. Reduce Motion keeps the loading indicator.
- Right-click an app for opening and Finder commands, running-app commands, and **Pin** or **Unpin**. Running-app commands include Hide or Show, Bring All to Front, and cooperative Quit. One icon represents every matching regular process, so those commands apply to all matching instances. Pins belong to that display and persist across restarts; unpinned running apps remain visible on every dock until they quit.
- Initially pinned apps are Finder, Safari, Mail, Calendar, and System Settings when installed. Newly opened regular apps join the running section automatically.
- Choose **Focus Dock** from the DOKK menu-bar item or app menu. It targets the enabled dock under the pointer, falling back to the primary enabled dock and then the first enabled display in Settings. Left/right arrows select an app on top and bottom docks; up/down arrows select an app on side docks. Return opens it, Space opens Window Peek for a running app, and Escape returns focus to the previous app. An outline marks the keyboard-selected icon, independently of running indicators. Only one dock has keyboard focus at a time; the command is disabled when all docks are disabled.
- Choose **Quit DOKK** from the menu-bar item or app menu to close it.

The default icons are 48 points, with 4-point item spacing and 6-point glass padding. Crowded docks reduce icon size to 32 points before scrolling along the dock, horizontally above or below, or vertically beside the display. Reduce Motion disables magnification, and Reduce Transparency uses an opaque native background.

Enabled docks stay visible by default; auto-hide is opt-in under Behavior.

## Arrange pins with drag-and-drop

- Drag a pinned app along the dock to reorder it. Drag a running app into the pinned section to pin it at that position. Running-only order remains automatic.
- Drop one or more application bundles or ordinary folders from Finder into the pinned section. Mixed app-and-folder batches are accepted in Finder order. The whole batch must be pinnable: plain files, packages, aliases, unreadable items, and DOKK itself reject the pin operation. Existing pins move into the dropped block; duplicate app identities and resolved folder locations appear only once.
- Drag an app onto another display’s DOKK to pin it there without removing the source pin. An existing destination pin moves to the chosen position.
- Drag a pin at least 64 points outside its dock to see **Unpin**, then release to unpin it. Returning closer or pressing Escape cancels removal. Releasing over another DOKK that rejects the drop keeps the source pin. Running apps remain in the running section after unpinning; applications are never quit or deleted.
- During dragging, magnification settles to resting icon sizes and a live gap shows insertion. Overflowing docks scroll near their viewport edges. A hidden dock uses its existing activation zone and reveal delay; the source and revealed destination stay visible during the relevant interaction.
- Pin edits save only when a drop completes. Cancelled drags restore the saved arrangement. Invalid batches are rejected together, and save errors appear on the affected dock.

Right-click a pin for **Move Left** and **Move Right** on a top or bottom dock, or **Move Up** and **Move Down** on a side dock. **Pin on Display…** works with every edge. With **Focus Dock** active, hold Option with the corresponding arrow key to reorder the selected pin; ordinary arrows navigate. VoiceOver exposes equivalent move and destination actions. The Pin on Display menu appends a new pin and leaves an existing destination pin in place.

Finder imports retain read-only security-scoped bookmarks so user-selected application bundles and folders can remain accessible after restart. Application-only lists migrate once to typed v3 pins; the older bytes remain untouched for rollback and recovery. DOKK uses app-scoped bookmarks for persistent pins; the separate Trash drop path requests read/write access only to items the user explicitly supplies. No Accessibility grant or system Dock preference changes are involved. Trash commands use a separate Finder Automation grant described below. Missing applications and unresolved folders remain visible as unavailable pins.

Selecting multiple pins within DOKK is not supported yet. Runtime acceptance for dragging, focus, auto-hide, cross-display copying, and bookmark access remains pending; see the latest acceptance entry.

## Open files and folders in an app

Drag files, document packages, or folders from Finder onto an available app icon. With Window Peek enabled, a running app shows **Hold to choose a window** and opens Peek after its configured delay. Dropping on the icon opens destination selection; dropping on a card opens the explicit [file handoff](WINDOW-FILE-HANDOFF.md). For a closed app or with Peek disabled, **Open in {app}** submits the batch at app level. The receiving app decides which types it supports. DOKK does not move or overwrite the source files.

Application bundles still use the pinning behavior above. Mixing applications and documents rejects the whole batch. Web links, pasted content, and promised files are not supported. While **Checking items…** is visible, the batch is not yet ready to drop. Missing or inaccessible items reject the batch before handoff.

Hover over a collapsed pinned or running section for half a second to expose its apps. The previous expansion state returns after the drag ends. Drop onto an app, not the section button. Completely hidden sections remain hidden. Auto-hidden docks use their configured activation zone and reveal delay; overflow scrolling remains available during dragging.

File hover on an app no longer spring-activates or launches it. A deliberate Peek dwell keeps the original application in front. Folder spring-loading still follows the macOS hover and Force Click preferences.

Known limitation on the development Mac: Escape cancels a Finder drag before switching apps, but did not cancel after spring activation. The same failure occurred when switching with Command-Tab without using DOKK. Escape cancellation after an app switch is therefore not guaranteed in this environment.

Right-click an available app and choose **Open Files…** to select files and folders in a native picker. VoiceOver exposes the same action. With **Focus Dock**, select an app and press **⌘O**. One picker is shared by all displays; it retains the app selected when it opened. Cancelling restores the originating dock selection or previous app when DOKK still owns focus.

Each direct app-level drop or **Open Files…** picker confirmation submits its own batch, including consecutive drops onto an app that is still launching. The Peek file picker instead retains files for destination selection. Failures appear on the initiating dock. A successful macOS handoff does not prove that the receiving app displayed every item. Document access is temporary, with no saved bookmarks or document history. See the [acceptance record](ACCEPTANCE.md) for build evidence and outstanding runtime checks.

## Folder stacks

Click a pinned folder to open one transient stack inward from its dock icon. The folder is resolved and its directory watch starts before the panel appears, so a volume that does not respond cannot freeze the dock. Closing the stack during that wait leaves the panel hidden. Only one stack can be open across all displays. The header shows the Finder folder name and a per-pin Grid/List/Smart choice. Grid and List sort visible children by localized name. Smart uses Apple Intelligence on file metadata to build a grouped list without reading file contents. It organizes the 60 most recently modified children and keeps any remainder in More Items.

The stack shows the current folder's immediate children. Click a child to select it, then press Space for Quick Look without opening an app. Space or Escape closes the preview; arrow keys switch the preview to another child. Double-click or press Return to open a file, package, or alias. Opening a subfolder browses it inside the same stack. Use Back or Delete to return to its parent. The context menu also provides Quick Look and Show in Finder.

Hold a dragged file over a pinned folder to spring-open its stack, then hover over subfolders to browse deeper. Drop onto a subfolder or the current folder's background to copy the files there. The copy cursor identifies the operation; source files stay in place. Existing names cause an error, with no replacement, and a failure reports how many items were copied before it occurred. Copies run off the main actor and keep their file access until completion, even if the panel closes. Packages, aliases, symbolic links, and file promises are not spring-loaded folders.

Drag one child to Finder or another app through the native file-drag session; that destination and modifier keys negotiate copy or move. A cancelled outgoing drag leaves a manually opened stack open. A stack opened by a drag closes when that drag ends without a drop into it.

The source dock stays revealed and suppresses fading and tooltips while its stack is open. The panel closes after a successful open or drag, outside click, Escape, another stack opening, source removal/hiding, display removal, sleep, or shutdown. Failed opens remain visible with a retryable inline error. Directory changes are watched only while the panel is open.

Focus Dock can open a stack with Return. In a list, the arrow keys move one child and wrap at the ends. In a grid, Left and Right move one child and Up and Down move one row. That row is however many columns the grid lays out, about five at its ideal width and two at its minimum. A search that stays in the grid uses the same stride. Movement stops at the first and last child. Return opens, Space previews, Delete goes back, and Escape closes the preview before returning focus to the source folder. Tab reaches the Grid/List/Smart control. VoiceOver exposes opening, Finder reveal, presentation, move, display-copy, and unpin actions.

Fan and Automatic presentations, search, multi-selection, file promises, move operations into stacks, and persistent utility windows remain planned.

## Downloads and utility order

List and Smart items show file type, size, and last-modified date below the name, plus image dimensions, PDF page counts, and audio or video duration when those headers are available. Folders show a visible-item count and contents size once measured, or an explicit calculating or incomplete state. Grid shows the current sort detail. Hover over an item for its full name, path, extra media details, and exact modification and creation timestamps. Folder hover also includes the item count and total contents size. Unavailable metadata is omitted. A folder never uses its directory-entry size as a total. Cloud-only files that are not already on disk stay unread.

The folder stack header has a Sort by menu with Recency, Alphabetical, and Size. Recency puts the most recently modified items first, Alphabetical starts with A, and Size puts the largest items first. The choice is saved per folder and display. Downloads initially uses Recency. Smart mode sorts within its groups. Size sorts files by filesystem metadata and folders by a finished contents total. Folders still being measured sort last, then by name.

Downloads appears to the left of Capsules and Shelf by default. Click it to browse the Downloads folder in a stack, or use its context menu to open it in Finder and choose grid or list presentation.

Drag Downloads, Capsules, or Shelf within their section to change their order. A floating icon follows the pointer while an insertion gap previews the saved position. The order is saved separately for each display, independently of Dock Modes. Escape or releasing outside the utility section cancels the move. Focus Dock and VoiceOver can open Downloads; VoiceOver move actions also reorder the three tiles.

Ordinary Shelf dragging now moves the tile. Hold Option while dragging Shelf to carry all staged files, or drag individual files from its open panel.

## Shelf

The Shelf is a staging area for files you are carrying somewhere else. Drop files on it, walk to another Space, display, or full-screen app, and drag them back out. It appears before Trash in the trailing utility area, shares that divider, and is enabled by default. Under **Features → Shelf**, turn it off for the whole app.

One Shelf is shared by every dock, so an item staged on one display is immediately on all of them. Its contents are independent of the active Dock Mode. The tile stays visible when empty, so the target never moves; a badge shows the item count once something is staged.

**The Shelf never touches the filesystem.** An item is a security-scoped reference to a file that stays exactly where it was. Dragging an item out hands other applications an ordinary file URL, exactly as Finder would, and the item deliberately stays on the Shelf: taking something out is a copy of the reference, not a hand-off. Nothing is moved, copied, or deleted.

Click the tile, press Return while it is selected in Focus Dock, or choose **Open Shelf** to open the panel. Each item shows its Quick Look thumbnail — the same artwork Finder draws, not a generic type icon — with the enclosing folder and when it was staged. Drag the tile itself to take every staged reference at once. Items animate as they arrive and leave, unless Reduce Motion is on.

Double-click an item to open it with its default application. Right-click for **Open**, **Show in Finder**, **Copy**, **Select All**, **Remove from Shelf**, and **Clear Shelf**; each command names how many items it acts on and applies to the whole selection. The header carries an **Arrange** menu with Date Added, Name, and Smart. Smart uses Apple Intelligence to group the Shelf's available file metadata in a list and keeps missing references in Unavailable. The List/Grid switch returns with its previous choice when you leave Smart. Both choices persist with the Shelf itself.

Keyboard, while the panel is open: in a list, Up and Down select the previous or next item and wrap. In a grid, Left and Right select one item and Up and Down select one row, using the columns the grid lays out, and stop at the ends. Return opens, ⌘R shows in Finder, ⌘C copies, ⌘A selects everything, Delete removes the selection, and Escape drops a multiple selection before it closes the panel.

Select items the way a Finder list does: click to replace the selection, Command-click to toggle one, Shift-click to extend from the last, and drag across empty space to sweep a rubber band. The band never starts on an item or over the scroller, so pressing an item still drags it and the list still scrolls. Dragging any selected item carries the whole selection at once; dragging an unselected one carries just that item.

Removal is always explicit. Use a row's Remove, **Clear Shelf…** from the tile menu or the panel header, or drag an item onto the dock's Trash tile — that drop reads **Remove from Shelf**, discards the reference, and leaves the file on disk. A Finder batch dropped on Trash still reads **Move to Trash** and still trashes; the two paths stay distinct because a Shelf drag also carries a private pasteboard type that only DOKK reads.

The Shelf holds at most 50 items; a larger drop is accepted up to the limit and reports the rest on the initiating dock. A file that is moved or deleted stays listed as unavailable rather than disappearing, so you can see what happened and remove it yourself. Unreadable stored bytes are reported and never overwritten.


Select a Shelf item and press Space, or choose Quick Look from its context menu, to preview it inside the panel. Space or Escape returns to the list. Arrow keys move the preview the same way they move the selection. A preview holds the file access until its native view closes.

Open **Shelf → Compost** to enable automatic archiving after 7, 14, or 30 days. It starts off.
Age counts from the last addition or restoration, including time while DOKK is closed.
Choosing a rule archives eligible entries immediately. Compost keeps the file references and
bookmarks, with a leaf-and-soil illustration and a brief leaf bounce when an item is restored.

**Restore to Shelf** returns an entry and restarts its age. **Clear Shelf** keeps Compost intact.
The archive holds 500 entries, then pauses aging without discarding anything. A full Shelf
refuses restoration until you make room. **Forget reference…** requires confirmation and
removes only that archived reference. Files remain where they are. See
[Compost acceptance](ACCEPTANCE.md#dee-55-compost-shelf) for validation limits.

Reordering individual Shelf entries and multiple named shelves remain planned.

## Trash

Trash appears as the final tile after its own divider and is enabled by default. Under **Features → Trash**, turn it off for the whole app. The tile is independent of the pinned and running sections, including their hidden and collapsed states.

Click Trash, press Return while it is selected in Focus Dock, or choose **Open Trash** from its menu to open Trash in Finder. VoiceOver exposes its name, status, hint, and actions. The first explicit Open or Empty command asks for permission to automate Finder. DOKK does not read the protected Trash directory directly. After permission exists, a serialized Finder item-count check every two seconds keeps the empty/full artwork synchronized with changes made by Finder or the system Dock.

Drop one or more files, folders, or packages from Finder directly on the tile to move the complete batch to Trash through `NSWorkspace`. The exact tile highlights and shows **Move to Trash**. Security-scoped access remains alive until macOS completes the operation; failures are reported on the initiating dock. Internal pin drags cannot target Trash, and dropping onto Trash never alters DOKK's pin configuration.

The context menu and VoiceOver offer **Empty Trash…** only when Trash contains items. **Features → Trash → Confirm before emptying Trash** controls DOKK's native destructive warning. Confirmation is on by default and applies to every display. DOKK then asks Finder to empty Trash. Finder owns the protected home and mounted-volume Trash locations. DOKK sends Apple events only to Finder. It uses no deprecated workspace operation, Finder UI scripting, or private API.

## External drives

Connected USB sticks, SD cards, and external disks appear between the Shelf and Trash. Click one to browse it in a stack, or hover over it for a card with capacity, Open in Finder, and Eject. You can also drag the tile off the dock to eject it; “Eject” appears before you release. The tile dims while ejecting and leaves once the drive is safe to remove. If an app still has a file open, the card names the app and offers Show, Quit (the eject then retries), Try Again, and Eject Anyway. Drag files onto a drive tile to copy them there, or hold Shift to move them; a label beside the cursor says which. Rest on the tile to open the drive's stack and keep resting on folders to go deeper; the stack's back button takes drops and climbs a level when you rest on it. Disk images, network shares, and Time Machine backups have their own switches in Settings › Dock Extras › Drives; backup disks stay out of the dock unless you turn theirs on, because macOS only lets DOKK browse them with Full Disk Access. DOKK can ask before ejecting a hard disk. Hide a drive you rarely use from its context menu; it stays mounted. **Manage Drives…** opens a list where you can show it again, drag drives into a new order, or forget a disconnected one. Dragging a drive tile along the other drives in the dock reorders them too. See [acceptance notes](ACCEPTANCE.md#dee-83-external-volumes) for limits and pending hands-on checks.

## Windows

### Permissions and window menus

Open **Settings → Features → Permissions** to manage Window Access and Screen Recording. Each row reports Enabled, Not Enabled, or Unavailable. The Enable buttons are the only actions that ask macOS for consent; **Open System Settings…** and **Check Again** manage and refresh the external grants. Permissions and the Window Peek controls below them apply to the app as a whole. DOKK stores no copy of permission state.

Application-level actions do not need Accessibility access. For a running app, its context menu can Hide or Show every matching instance, Bring All to Front, or request a cooperative Quit. Available app bundles also offer Open, Open Files, and Show in Finder. These commands remain available when window access is off.

When window access is enabled, a menu opens immediately with **Loading Windows…**, then replaces that row with the app's top-level standard windows and dialogs. Select a row to restore a minimized window when supported, activate its owning app, and raise that exact window. Main windows are marked, untitled windows receive a localized fallback, and duplicate titles stay separate. The same commands are exposed as VoiceOver actions.

Window discovery and selection use the public macOS Accessibility API. Moving between Spaces and full-screen transitions is best-effort because public APIs do not expose complete Space ownership or guarantee activation. Windows owned by unusual helper processes may not appear under the regular app represented by the icon.

Window Peek uses one-shot ScreenCaptureKit screenshots only while a Peek is visible. It keeps images in memory for that presentation and never records audio, shows the pointer, or writes window contents to disk unless you explicitly save, send to the Shelf, or drop a markup as a file. Accessibility and Screen Recording windows are matched conservatively by process, title, and bounds. When Accessibility discovery is unavailable, ScreenCaptureKit metadata supplies capture-only cards; selecting one activates the app because no exact AX handle exists. Minimized, protected, ambiguous, and unavailable captures keep a card with app artwork instead of risking the wrong image. Current-Space filtering is not offered because public APIs do not expose dependable Space identity.

### Window Peek

- Keep the pointer over a running app to open Window Peek, or press Space on an app while using Focus Dock. With usable Window Access, cards select individual windows. Screen Recording supplies fresh thumbnail images and can still enumerate preview cards when Window Access fails; those capture-only cards activate the app. Without either permission, Peek keeps an app-level Show App action.
- Enable **Split-peek** in **Settings → Features → Window Peek** to see two captured windows from the same app side by side. It is off by default. Previous/Next window browses the app's windows without activating them; **Show all windows** returns to your usual layout. Missing previews and file handoff use the usual Peek view.
- Drag files onto a running app and hold to choose a Window Peek destination. Drop on a card to open a file handoff, then explicitly activate the window and drag into it. In keyboard Peek, press C to choose files. App-level opening is labeled separately. See [file handoff](WINDOW-FILE-HANDOFF.md) for limits and pending native acceptance.
- Optional **Peek history** saves recognized text from peeks locally after opt-in under **Settings → Features → Window Peek**. Search recent text, delete individual entries, or clear the history. Images are not saved. See [Peek history](PEEK-HISTORY.md) for privacy, retention, and OCR limits.
- Choose **Watch this** on a Window Peek card, or press W in keyboard Peek, to monitor a selected region for stable visual change or an exact completion phrase. Save the region and condition as a named watch, bind it to a current window later, and optionally offer **Open configured folder** or **Run configured Shortcut** after detection. A persistent panel keeps Stop available. Results are local visual evidence, with optional sound and indeterminate progress. See [Watch a window](WINDOW-WATCH.md) for controls, capture limits, and pending native acceptance.
- Choose **Pin window portal** from a Window Peek card menu, or press P in keyboard Peek, to keep a live preview in a floating window. Up to four portals have independent pause, source, close, and keyboard movement controls. **Focus next portal** returns keyboard focus to them. See [window portals](WINDOW-PORTALS.md) for update policy and pending native acceptance.
- Choose **Mark up window…** on a Window Peek card, or press M in keyboard Peek, to draw on a fresh full-resolution capture: pen, highlighter, arrow, rectangle, text, numbered badges, and pixelated or solid redaction, with crop, undo, and an optional coloured frame. Copy, save, share, drag out, or send the result to the Shelf. Live Text and Visual Look Up work on the picture; **Copy Text** and **Search Web** use the selection or recognised text. With the enlarged preview on, resting the pointer on the staged picture shows Mark up, Copy, and Save. See [Window Peek markup](WINDOW-MARKUP.md) for tools, keys, privacy, and pending native acceptance.

### App Compare

Choose **Add to Compare** on a Window Peek card, then select a second window from the same or another app. In keyboard Peek, **F** adds the selected card. **App Compare** in the menu-bar item opens an accessible picker. The app-wide tray keeps the selection while you navigate other previews and displays.

Capture the selected windows, review or correct their visible text, and choose Compare, Summarize differences, or Create checklist. Apple Intelligence generates an editable draft from the reviewed text only. Save explicitly to create a native text artifact in Shelf with source attribution, capture times, and limitations. Errors retain reviewed input or the draft where practical; unavailable AI never produces a substitute result. This is a partial visible-context analysis, not a complete document comparison.

See [App Compare](APP_FUSION.md) for input lifetime, save recovery, and storage behavior. Compilation is separate from [pending native acceptance](ACCEPTANCE.md#app-compare-dee-16).

### Find a window

Choose **Find a Window** from the DOKK menu, press Command-Shift-Space globally, or press `/` in Focus Dock. Search live window titles and app names without AI. Use **Choose Windows…** and **Capture Selected** to search visible text from up to four selected windows. **Search Images with AI** separately checks those screenshots and labels matches as model suggestions. Captures stay in memory for at most ten minutes and are cleared when search closes.

**Saved Capsules** searches historical checkpoints and supports deletion. “Yesterday” requires a capsule saved yesterday; DOKK does not collect a continuous screen history. See the [window search reference](WINDOW_SEARCH.md) for limits, keyboard controls, and pending acceptance.

### App Fusion

Choose **App Fusion → Fuse windows** from the menu-bar menu to launch two apps and pair
one window from each. Shared glass controls move, resize, minimize, restore, and request
closure of both windows. A combined DOKK icon keeps the pair reachable when minimized.
Native title bars remain, and pairs last for the current DOKK session. Window Access is
required. See [App Fusion](APP-MELT.md) for setup, recovery, and validation limits.

## Dock Modes

Open **Settings → Modes** to create, rename, duplicate, reorder, activate, or delete named configurations. DOKK keeps at least one mode. New modes copy the active mode, while names must be non-empty and unique without regard to capitalization. Deleting the active mode selects the nearest remaining configuration.

**Snapshot workspace…** creates an editable recipe draft from open apps, visible window context, and DOKK pins. Review the choices, name the draft, and save it as a new mode. Saving leaves the active mode unchanged. Window titles require existing Screen Recording access and help with review only. **Prepare Workspace** reopens the chosen apps and resources. See [recipe photography](RECIPE-PHOTOGRAPHY.md) for capture and playback limits.

Each mode owns the ordered app and folder pins for every remembered display, plus the shared App Visibility choice and any display-specific App Visibility overrides. Pinning, unpinning, reordering, folder presentation changes, and App Visibility edits apply directly to the active mode. Appearance, placement, auto-hide, Trash, Window Peek, and other controls remain independent.

The menu-bar **Dock Mode** submenu switches configurations across all connected docks after the new choice has saved successfully. Ordinary switching updates pins and app visibility only. **Prepare Workspace** is a separate command: it activates the chosen mode, then runs that mode's optional recipe in order. **Previous Mode** toggles between the last two configurations. During Focus Dock, press M, use Up or Down, then Return to switch. P prepares the selected mode's workspace. Escape closes the picker without switching. Switching is unavailable while a native menu, file picker, or drag operation is active, and closes open Window Peek and folder panels before changing the docks. Prepare reports that blocked state and does not open apps, files, links, or Shortcuts. A recipe does not start a Focus Session, replay after launch, or arrange windows.

Existing installations migrate their current display pin lists and App Visibility values into an initial **Default** mode. The older preference keys remain for rollback but are no longer authoritative. If the modes document is corrupt, DOKK continues with the recoverable legacy layout, blocks persistent mode and pin edits, and offers an explicit reset in Settings rather than silently overwriting the stored evidence.

Choose a named configuration from **Dock Mode** in the menu-bar item, or press M in Focus Dock to open the keyboard mode picker. A mode changes every display's pins and App Visibility together; it does not launch, quit, hide, or reorder running-only apps. **Prepare Workspace** is a separate command that runs that mode's optional recipe.

## Focus Sessions

Choose **Dock Mode → Start Focus Session → [mode]** from the menu bar, or use the timer button beside a mode in **Settings → Modes**. DOKK activates that mode and starts a shared timer. You can also start from the already-active mode. Only one session can run or pause at a time; switching modes later does not replace its timer.

The timer tile appears on every display. Its ring shows time remaining. Click it for **Pause**, **Resume**, **Add 5 Minutes**, and **Finish**. A finished session keeps a checkmark tile until dismissed or replaced by a new session. **Save Session Capsule** opens the usual window-selection and draft-review flow; finishing never captures or saves anything automatically.

Set the next session's duration, from 1 to 180 minutes, in **Settings → Features → Focus Sessions**. The default is 25 minutes. Completion animation is optional and off by default, and Reduce Motion suppresses it. There are no streaks.

Running timers use a saved wall-clock deadline, so sleep and app downtime count. Paused timers retain their remaining duration. Reopening DOKK after the deadline marks the session finished without replaying a celebration. Changing focus defaults does not restart the current session. Renaming or deleting a Dock Mode does not erase a timer already started from it.

### Boss Fight

**Boss Fight** is an optional Easter egg in Settings → Features → Focus Sessions. Choose
up to eight work apps for your party, then start a normal session. A boss health bar shows
remaining time, and completion adds a brief, silent trophy. Disable the skin at any time
without changing the timer. See [Boss Fight behavior and acceptance](BOSS-FIGHT.md).

## Local History

Choose **Browse Local History** from the menu-bar item, or press **H** in Focus Dock. The dock under the pointer becomes a time axis of DOKK-local pin and Focus Session events. Drag along the chrome to scrub; arrows move to the previous or next event. Escape or **H** again leaves the timeline. Nothing is imported from macOS Screen Time or other apps. **Settings → Features → Local History** can pause recording and clear stored events. An empty dock shows a privacy explanation instead of a blank track. Session events share an identifier so a later session-scrub feature can replay one Focus Session from the same log.

**Show pins while browsing** is off until you turn it on in that same settings card. With it on, the dock waits until you pause on a moment, then shows that pin order using the usual insert, remove, and move animations. Saved pins do not change. Leaving the timeline restores the current layout.

## Session Capsules

Session Capsules save mental context without restoring window geometry. Open the shared Capsules tile, choose up to twelve visible windows, and create a draft. DOKK captures those windows once with ScreenCaptureKit, runs on-device Vision OCR, and gives the images plus window metadata to the system default Apple Intelligence model. Foundation Models produces typed structured output for the title, summary, and unfinished tasks; the prompt never asks for JSON. If the model is unavailable or generation fails, DOKK creates a plain editable draft from the selected window metadata instead.

Nothing is saved until you review the draft and choose **Save Capsule**. For ordinary capsules, raw screenshots and recognized text remain in memory only for draft creation and are discarded afterward. Breadcrumbs can retain reviewed text previews as described below. Each saved checkpoint then appears beside the collection tile as its own temporary, title-bearing Dock item until you delete it. The persisted capsule contains the approved text, optional personal note, application bundle identities, and window titles. **Resume** reopens missing applications and uses Accessibility to raise a unique app/title match when available, otherwise it activates a referenced app. It deliberately does not move, resize, or rearrange windows.

Choose **Leave a breadcrumb** before switching away. Select relevant windows, then write your note and next step. **Write manually** also works without Screen Recording or Apple Intelligence. **Capture & draft with Apple Intelligence** is a separate, explicit action. Review its interpretation alongside your own writing before saving. A breadcrumb uses the same capsule collection and can be edited after restart.

Saved source cards show historical text previews, dates, and current window availability. **Show window** rechecks a unique app/title match. **Open app**, **Open link**, and **Open saved document** describe separate actions. Add web links yourself or choose saved documents through the file picker. DOKK never infers reopening paths from a model or window title. Unsaved documents, Spaces, and exact window positions cannot be restored reliably.

Each source can retain at most 2,000 characters of captured text. Screenshots are never saved. Remove a source or preview in Edit and save, or delete the capsule to remove all its retained context and document bookmarks. Source documents remain untouched. Nothing captures on idle, app switches, or return from a break. See the [breadcrumb acceptance checklist](BREADCRUMBS.md) for validation status and limits.

The underlying window-context service is feature-neutral: its public values contain current window identity, application identity, bounds, one-time imagery, and OCR. The planned Window Scout can reuse that capture boundary without depending on the Capsules repository or UI.

## Action Tiles

Open **Settings → Features → Action Tiles** and pin a shortcut. Installed Shortcuts load when that page appears; **Reload Shortcuts** refreshes the list. Tiles appear in the same order on every display, independently of Dock Modes. Settings provides Run, Cancel, Unpin, and ordering controls. Up to 30 tiles can be pinned.

Click a tile or select it in Focus Dock and press Return to run it. Drop files onto a tile to pass them as shortcut input. Each tile allows one run at a time and shows progress, a completion checkmark, or an error. Saved shortcut identifiers survive renames; shortcuts that are removed or unavailable report the helper's error. DOKK never retries a run automatically.

Shortcuts may show their own permission or input dialogs. Configure the shortcut itself to save or display its output; DOKK does not retain output files. Cancel stops the CLI invocation and cannot undo actions already performed. Shortcut discovery and execution use Apple's documented `shortcuts` command, with arguments passed directly rather than through a shell.

## App Launcher

The permanent **App Launcher** tile expands the dock into a searchable app panel. It includes
grid and list app browsing plus unified search for apps, windows, Capsules/Breadcrumbs, Shelf files,
pinned Shortcuts, and Dock Modes. App browsing retains filters, a location/source filter, sorting, grouping, and launch history.
Those browse controls live in one search-field overflow menu. **Ask Robi** appears there for a
nonempty query and uses on-device Apple Intelligence to suggest apps for a task you describe.
With files selected, Launcher can open them with a compatible app, pass them to a pinned
Shortcut, or copy them into a chosen folder. See the [launcher reference](LAUNCHER.md)
for controls and discovery limits, and the [acceptance notes](ACCEPTANCE.md#dee-8-app-launcher)
for validation status.

### Launcher position

The launcher sits at the far left of a horizontal dock, or the top of a vertical one, by default.
Drag the tile to another spot to move it: before the pins, right after any pin, or past
running apps and utilities to the far end. Click it to open the launcher as usual. VoiceOver move actions step it one spot at a time.
**Settings → Dock → Position → App Launcher** offers the same choices as a menu.

A launcher placed after a pin stays beside that pin when other pins are added or removed. If you
move or unpin that pin, the launcher stays put and follows the pin that was before it. Where a display
doesn't have that pin, or it is parked on a magnetic edge, the launcher follows the nearest
earlier pin, or the far left if none. A launcher between pins shares the pinned section and adds no divider.

The position is a dock setting, saved with the other settings and kept across restarts. A drag
updates the shared default, or that display's own value when it already overrides the default.
Pins differ per display, so the shared Settings menu lists the main display's pins.

### App suggestions

Optional **App suggestions** learn from local app activity after opt-in under **Settings → Features → App suggestions**.
An empty Launcher query can show up to three likely apps above the ordinary results. Pause, reset, exclusions, and feedback controls are included.
After a week of use, a short optional survey about suggestion quality can appear below them while usage-data sharing is on.
See [app suggestions](LAUNCHER-SUGGESTIONS.md) for the 90-day retention policy and observation limits.

## App badges

Enable **Settings → Features → App badges → Show app badges**, then allow Accessibility access using the controls in that card. The setting is off by default and applies to every display. Screen Recording is not required.

DOKK mirrors badge text exposed by application items in the system Dock, matched by application URL. Apps absent from the system Dock and custom-drawn badges may not provide readable text. AX changes trigger a refresh where supported; a fallback five seconds after each completed scan covers missing notifications and permission changes. Long labels are visually truncated, with their full text available to VoiceOver.

AX reads run outside the main actor and do not depend on pointer movement or animation frames. Disabling badges, disabling all docks, and shutdown clear the badges on screen and stop the reader. Sleep, display sleep, and an inactive login session do that too. They leave badge history as it was, and the 15-second grace keeps running from the last successful scan. A failed scan within that grace shows the last badges again. Permission loss clears badges on the next refresh. If scans keep failing after the grace, badges stay clear until one succeeds. Compilation is verified; live badge coverage and performance still need native acceptance. See [the acceptance record](ACCEPTANCE.md#app-badges-dee-10).

### Badge memory

Click an app badge, choose **Badge details** from its context menu, or press **B** in Focus Dock to review observed changes. **Mark checked** explicitly sets the comparison baseline; opening an app leaves it unchanged. Optional Focus Session collection provides a digest of net badge changes. History, baseline and digest deletion controls are available in **Settings → Features → App badges → Review badge history**. See [Badge memory](BADGE_MEMORY.md) for retention limits and observation gaps.

## Atmosphere

**Settings → Atmosphere** adds optional ambient light to every drawable display, independently
of Dock Modes. It starts off. Choose 69 for candles and hearts, Minimal for a subtle color
wash, Focus for a soft glow, or Party for party décor and denser particles. Density controls
particles. Light intensity scales the edge wash from a faint rim to a stronger glow
without covering the desktop. Click corner décor to toggle its light; hold it to
change its appearance.

Choose one color source: Manual, Wallpaper, Focused app icon, or Mood. Wallpaper sampling
refreshes every eight seconds and offers prominent-to-average, average-only, and corner
colors. App colors update on activation. Mood uses the local Foundation Models model;
Apply keeps Mood selected, while Edit as Manual copies its colors. Mood and the optional
Image Playground system sheet appear only when available. Generated corner images are
saved locally.

Per display is the default layout. Panorama joins a contiguous horizontal row with matching
vertical extents, keeps décor at the outer corners, and shares one palette across the row.
Other arrangements fall back to per-display edges. Only while idle dims the effect until
30 seconds pass without input. A window covering an entire display hides its overlays;
this also treats borderless screen-filling apps conservatively as fullscreen. Reduce Motion
keeps particles still. Sleep and inactive sessions release all Atmosphere panels.
See [Atmosphere acceptance](ACCEPTANCE.md#dee-73-atmosphere) for runtime limitations.

## DOKK Discovery

**DOKK Discovery** offers occasional local feature tips. Three observed clipboard changes followed by five calm seconds can suggest Clipboard Museum. Museum collection stays opt-in. Disable tips in **Settings → Features → DOKK Discovery**. See [Discovery](DISCOVERY.md) for scheduling, privacy, and acceptance limits.

## Settings

Choose **Settings…** from the menu-bar item or app menu.

### Features and per-display defaults

**Settings → Features** collects DOKK's opt-in capabilities: Session Capsules, the Shelf, the Trash tile, and Window Peek with its Window Access and Screen Recording permissions. It sits beside General and Modes, above the Defaults section, because everything in it is app-wide.

That is the distinction the sidebar draws. Panes under **Defaults** describe how a dock looks and where it sits, so each display can override them individually. A feature is either on or off for DOKK as a whole; no display holds its own copy. Appearance, Position, and Behavior keep their per-display overrides exactly as before.

### Displays and inheritance

The Settings sidebar retains the appearance/position panes, search, cards, and live previews, and adds connected and remembered displays. App-wide General, Modes, and Features sit above them. **Defaults** changes the shared values. Selecting a display exposes **Show Dock** and the same controls. Editing a control creates an explicit override; **Use Default** restores inheritance for that control. **Use Defaults** clears all appearance, position, and behavior overrides on that display while preserving its pins and visibility.

With multiple connected desktop displays, selecting a display in the active Settings window outlines that monitor and shows its name. The marker stays across settings categories, works when that display’s dock is disabled, and disappears on Defaults, disconnected profiles, or leaving Settings. Mirrored followers do not receive separate markers.

New displays start enabled and copy the primary display’s current pins once, including an empty list. Later pin changes remain local. Disconnected displays remain editable and recover their settings on reconnect. You can disable every dock and reopen Settings from the menu-bar item to recover.

Display profiles use public ColorSync UUIDs, independent of screen order, names, and primary-display changes. Mirroring renders one dock using the mirror source’s profile; follower profiles remain saved. If macOS supplies missing or duplicate identity, affected docks use temporary state for that connection and Settings reports the limitation. Temporary profiles never replace saved profiles.

Existing settings remain shared defaults under their original preferences key. Legacy pins are retained and migrated to the initial primary profile; each display’s pins are stored separately. Malformed data is reported without silently replacing saved bytes. Unreadable display metadata blocks profile edits; unreadable pins block pin writes for that display. There is no profile deletion or repair screen yet.

### Position and appearance

Choose **Settings…** from the menu-bar item or app menu (⌘, while DOKK is active). The single native Settings window applies valid edits immediately and saves them automatically.

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
| App Launcher position | Far end left or top / after any pin / far end right or bottom | Far left or top |

Numeric controls support sliders and locale-aware typed values. Invalid drafts never enter layout calculations; leaving the field restores the last accepted value. **Restore Defaults** on the Defaults page resets shared configuration only and preserves display overrides, visibility, and pins. Unreadable saved settings are left intact and reported in Settings; Restore Defaults explicitly replaces them.

Positive along-edge offsets move right on top and bottom docks and down on side docks. Edge distance measures from the reference frame to the outer edge of the glass. Placement keeps the magnification envelope on the display, so alignment and large offsets can be constrained near an edge. Requested values remain saved across geometry changes. Crowded docks may use smaller icons than requested before scrolling; the requested size returns when space is available.

Top placement always uses **Usable desktop**. Its **Position relative to** picker is disabled and explains the menu-bar and notch restriction. The saved reference choice, including a display override or inheritance, returns when another edge is selected. Top icons stay upright, with indicators above, magnification and labels below, and outward animations moving upward. Activation remains a separate setting; a physical top-edge activation zone can also reveal the menu bar.

A 1.0× maximum disables magnification; Reduce Motion also disables it without changing the saved preference. Glass thickness stays fixed during hover. Icons magnify inward and labels remain upright in a separate inward area. Screen-edge positioning can overlap the system Dock; neither mode changes macOS preferences. Settings resolve separately for each display. Auto-hide and activation behavior can be configured separately in the Behavior pane.

Changing edges reuses the same alignment, offset, edge distance, and activation dimensions. Both side docks order pins and running apps from top to bottom. Pin order and keyboard selection survive edge changes. Switching between horizontal and vertical layout resets scrolling to the start unless keyboard focus requires revealing the selected app; switching between edges on the same axis preserves scrolling. Edge changes apply immediately and cancel obsolete drag and visibility work. Old settings load as bottom placement.

### Background and idle fading

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

Compilation is verified; hands-on acceptance for material opacity, restoration timing, and native interaction remains pending in the [acceptance record](ACCEPTANCE.md).

### App visibility and section buttons

Under **Behavior → App visibility**, choose **Show all**, **Hide running apps**, **Collapse running apps**, **Hide pinned apps**, or **Collapse pinned apps**. Each display can override the shared default independently. Only one section can be hidden or collapsed at a time. Show all is the default.

Pinned apps remain in the pinned section while running. The running section contains only unpinned running apps. Hiding a section removes its icons from the dock without changing saved pins or quitting apps.

Collapse replaces a section with a group button showing its app count, including zero. Click the button to expand or collapse the section. The button stays before its apps when expanded. Expansion survives auto-hide, pointer exit, app launches, and sleep while that dock remains alive. Restarting, recreating the dock, or changing its effective visibility choice starts it collapsed.

Group buttons participate in Focus Dock navigation. Press Return or Space to toggle the selected group. VoiceOver announces its action, count, and expanded state. Hidden apps are excluded from navigation and hit testing. Groups follow the dock's icon fading settings while keyboard outlines stay visible.

Hold a valid app drag over a collapsed pinned-group button for 0.5 seconds to expose insertion positions. The section returns to its previous expansion state when the drag ends. Dropping directly on the button appends pins. Completely hidden pins reject direct drops; **Pin** and **Pin on Display** remain available through app menus.

### App-name tooltip presets

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

Compilation is checked separately from hands-on appearance and interaction. See the [acceptance record](ACCEPTANCE.md) for the outstanding runtime scenarios.

### Multi-monitor docks

In **Settings → Features → Multi-monitor docks**, enable secondary docks to show only apps
with visible windows on their display in the running section. Only the running-only app list
is filtered; pins, folders, utility tiles, and Behavior → App Visibility keep their normal
behavior on every display. The primary dock's running list is unchanged.
Finder is the exception: on filtered secondary docks, even its pin appears only when a
visible Finder window occupies that display. The desktop does not count; the pin stays saved.
Screen Recording access is required through the permission controls in Features. If access
or window enumeration is unavailable, docks show their ordinary contents. Disabling the
primary dock also restores ordinary contents on the remaining docks.

Window metadata refreshes every three seconds while this mode has multiple enabled displays.
A spanning window belongs to the display with the largest overlap. Apps with windows on
several displays appear on each relevant dock. Minimized, hidden, and other-Space windows
have no guaranteed assignment; the primary dock keeps their apps available. Finder is an
app icon, not a separate tile per Finder window. This feature does not redirect minimize
animations or provide system Dock minimize targets.

### Auto-hide and activation zones

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

#### Animation styles

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

### Launch at login

Open **Settings → General → Launch at Login** to start DOKK automatically when you sign in. General sits above Shared Defaults and applies to the whole app. Appearance remains the initial Settings pane. Search for login, startup, or automatic launch to find General.

The toggle reflects macOS’s registration status. It stays off until approval is granted. If approval is required, use **Open System Settings…** to open Login Items, or **Cancel Request** to withdraw the registration. Returning to the Settings window refreshes the status, including changes made outside DOKK. An unavailable status provides Refresh and the System Settings link. Errors appear in General without automatic retries.

Turning off Launch at Login prevents future automatic launches and leaves DOKK running. Login startup follows normal startup: configured docks and the menu-bar item appear without opening Settings or deliberately taking foreground focus. General remains usable if display settings have a storage error, and Restore Defaults does not change login registration.

The implementation uses `SMAppService.mainApp`; it stores no duplicate preference and installs no helper or launch-agent plist. Registration is opt-in. Real registration and logout/login acceptance require a consistently signed installed copy; see [acceptance notes](ACCEPTANCE.md#launch-at-login).

## App updates

DOKK uses Sparkle’s update engine with a DOKK-owned native update window. Consent, release notes, download progress, errors, and installation choices use DOKK’s UI. Choose **Check for Updates…** from the DOKK menu, or configure automatic checks in **Settings → General**. Scheduled updates appear as **Update Available…** in the menu without taking focus. You can hide a download and reopen it from **Show App Update…**, or cancel it explicitly. The ready screen offers a restart now or installation when DOKK quits. macOS may still show an administrator authorization dialog. The release process is described in [release instructions](UPDATES.md).

## Deprecated features

These personality extras are deprecated and turn off on launch: Dock Sims and AI icon rumours, Focus breathing, Focus debt, Pin weather (icon rust), Quarantine stamp, Patch bay, and Magnetic Edges. Their settings stay under **Settings → Features → Deprecated**, with a notice that they will be removed in version 1.0.0. Atmosphere and soap bubbles stay in the ordinary Features list.

**Patch bay** is deprecated. Launch turns cable actions off. The editor stays under **Settings → Features → Deprecated**. See [supported ports and limits](PATCH-BAY.md).

**Magnetic Edges** is deprecated and will be removed in version 1.0.0. Launch turns snapping off. The toggle stays under **Settings → Features → Deprecated**.

**AI icon rumours** and Dock Sims are deprecated. Launch turns Sims moods off, which also stops rumours. Settings stay under **Settings → Features → Deprecated → Dock Sims**. See [Icon rumours](ICON-RUMOURS.md) for the old consent and data boundaries.

**Focus breathing** is deprecated and will be removed in version 1.0.0. Launch turns it off.
The controls live under **Settings → Features → Deprecated**, not on Modes.
See [Focus breathing](FOCUS-BREATHING.md) for the old setup and native acceptance limits.

**Focus debt** is deprecated and will be removed in version 1.0.0. Launch turns the meter off.
Its page is under **Settings → Features → Deprecated**. When it was enabled, each new session
was a promise to let its timer finish. Finishing or cancelling early added one to a local count.
