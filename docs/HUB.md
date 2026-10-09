# DOKK Hub

The DOKK Hub is one large glass panel for apps, windows, and files. It opens from the DOKK tile,
which replaced the App Launcher tile. The header holds the DOKK wordmark, the **Apps**, **Windows**,
and **Files** switcher, a search field for the visible tab, a pin button, and a close button.

Only one Hub exists. It opens on the display whose tile, Focus Dock, or drop opened it. The Hub
replaced both launcher styles: the Compact popover and the Full presentation that expanded the
dock. The Apps tab carries the whole launcher. Validation status is in the
[acceptance notes](ACCEPTANCE.md#dee-121-dokk-hub).

## Opening and closing

Click the DOKK tile, press Return on it in **Focus Dock**, or use its VoiceOver action. The Hub
opens on the tab it showed when it last closed. Files opens with keyboard focus in the listing.
Apps and Windows open with focus in the search field. Opening the Hub closes folder stacks, the
Shelf and other dock popovers, Window Peek, the Dock Mode picker, drive cards, and Focus Dock.

Drop files on the DOKK tile or on the open Apps tab, or choose **Use in Launcher** from a Shelf
selection, to open the Apps tab in file-action mode. The Windows tab does not accept drops. **Open in Hub** on a folder stack, the Downloads stack, or a drive opens the
Files tab on that folder. See [Open in Hub](#open-in-hub).

### Anchored and detached

The Hub opens anchored by default. An anchored Hub is a borderless panel next to the dock with a
pointer aimed at the tile's resting position, so magnification under the click does not move the
pointer. It is 1,180 by 640 points, shrunk to fit the display's visible frame with a 16-point
margin. It opens on the side away from the dock on any edge. The dock stays revealed while an
anchored Hub points at it, and the Hub follows the tile when the dock moves, resizes, or scrolls.
The anchored panel floats above other windows and appears on every Space, including over
full-screen apps.

The pin button (**Keep open as a window**) turns the Hub into a normal window with traffic lights.
A detached Hub can be moved and resized down to 900 by 500 points. It stays open after you open an
app, a window, or a file, like a Finder window. It is a normal-level window that stays on its
Space. The pin button changes to **Attach to the dock**, which turns it back into an anchored
panel. The Hub remembers which mode it was in and the detached window's frame. A remembered frame
is moved onto a display that still exists.

### Clicking the tile while the Hub is open

- Anchored on the same display: the Hub closes and the previously active app becomes active again.
  The click does not reopen it.
- Anchored on another display: the Hub moves to this display and keeps its tab.
- Detached: the window comes to the front and the tile pulses once.

### What closes an anchored Hub

- Escape, the close button, and ⌘W close the Hub and reactivate the app that was active before it
  opened. Escape first clears the visible tab's search, and the tab itself may use it before that.
  See [Escape order](#escape-order).
- A click outside the Hub, or another app taking focus, closes it without reactivating anything.
- Opening an app, a window, a file, a capsule, or a DOKK tool closes it.
- Opening a folder stack, the Shelf, Radar, Find a Window, Focus Dock, or Local History closes it.
- Sleep, switching to another user, and a display change close it at once, whatever holds it open.

A detached Hub ignores outside clicks and focus loss. Escape only clears its search. The close
button, its title-bar close button, and ⌘W close it.

### Holds

These keep an anchored Hub open through outside clicks, focus loss, and Escape:

- A drag that started in the Hub, while it is over another app.
- An open file chooser, an alert or confirmation dialog, or Quick Look.
- A context menu or options menu from Hub content.
- A copy or move in the Files tab.

Focus moving to a menu, Quick Look, or a sheet or child window of the Hub does not count as focus
loss.

### The DOKK tile

On a dock with app icons, the tile is the DOKK mark on a dark face over a slowly turning rainbow
halo. The halo brightens and grows while the Hub is open. On a Line dock, the tile glyph stays lit
while the Hub is open. While the Files tab copies or moves files and the Hub is closed, an accent
progress ring circles the tile. VoiceOver reads the tile as **DOKK Hub** and reads the transfer
percentage as its value.

The tile's place in the dock is set under **Settings → Dock → Position → DOKK Hub → Tile position**,
or by dragging it. See [DOKK tile position](GUIDE.md#dokk-tile-position).

## Tabs

The switcher has a sliding selection pill. ⌘1, ⌘2, and ⌘3 select Apps, Windows, and Files. The
Hub saves the selected tab as soon as you switch.

⌘F focuses the header search field. Each tab keeps its own search text, and the field shows that
tab's prompt. The text stays when you switch tabs, and while a detached Hub stays open. Closing the
Hub, anchored or detached, clears every tab's search text; Files returns from its results to its
panes. Moving an anchored Hub to another display's tile keeps the text. Typing a character
while a tab's content has focus moves it into the search field.

### Escape order

Each press of Escape does the first of these that applies:

1. The visible tab handles it. Apps cancels Robi, then drops the arrow-key selection. Files closes
   Quick Look or cancels a rename. Windows has no Escape step of its own.
2. The Hub clears the visible tab's search.
3. An anchored Hub without a hold closes.

## Apps tab

The Apps tab is the app launcher: Suggested cards, app browsing, mixed search, Robi, DOKK's tools,
and file actions. See [Apps tab](LAUNCHER.md) for its full behavior.

## Windows tab

The Windows tab shows open windows grouped by app, on every display. A summary bar reads, for
example, **5 windows in 3 apps**, and it has an **Open Radar** button. Groups are ordered by their
frontmost window. Apps with only minimized or hidden windows come after them. Within a group,
visible windows come first in front-to-back order, then minimized windows, then windows of hidden
apps. Each window card has a thumbnail and the window title, or the app name when the window has
no title. Minimized and hidden windows show the app icon with a **Minimized** or **Hidden** badge.

The tab lists regular apps only. It skips DOKK, background and menu-bar apps, and windows smaller
than 40 points. Windows on other Spaces are left out. Minimized windows and windows of hidden apps
appear whatever their Space.

Search matches app names and window titles. Every word must appear, ignoring case, accents, and
character width. A word that matches an app name keeps all of that app's windows. The summary
counts follow the search.

The list refreshes when an app launches, quits, hides, or unhides, and when the Space changes.
While the Hub is detached, it also refreshes when another app becomes active. There is no timer.
A window opened, closed, or moved inside a running app appears after the next refresh or when the
tab opens again.

### Permissions

The tab never asks for a permission. Each missing permission shows a hint row with **Open System
Settings**, which opens the matching privacy pane.

| Permission | With it | Without it |
| --- | --- | --- |
| Screen Recording | Window thumbnails | App icons instead of thumbnails. Titles come from Accessibility, or are missing when it is off too. |
| Accessibility | Minimized windows, hidden apps, and raising one exact window | Only on-screen windows of the current Space. A click activates the app instead of one window. |

### Keyboard and activation

- Down and Up move to the nearest card below or above. From the search field, Down moves into the
  cards.
- Left and Right move in reading order. In the search field they move the text cursor.
- Return activates the selected card. With a search and no selection, Return activates the first
  result.

Clicking a card, or pressing Return, unhides a hidden app and raises the window. A minimized window
is restored. Without Accessibility, DOKK activates the app instead. An anchored Hub then closes and
leaves focus on that window. **Open Radar** opens [Radar](GUIDE.md#radar) and closes an anchored
Hub.

## Files tab

The Files tab is a file browser: a sidebar, browser tabs, one or two panes, a preview column, and a
status bar.

### Sidebar and drives

**Favorites** lists Recents, Desktop, Documents, Downloads, your home folder, and Applications.
Recents comes from Spotlight. **Drives** lists the startup disk and every mounted volume under
`/Volumes`, each with its free space. The list updates when volumes mount, unmount, or are renamed.

External disks, disk images, and network volumes have an eject button. The startup disk does not. While it ejects, the row dims and shows a
spinner. If an app is using the volume, an alert names that app. Panes showing a folder on an
ejected volume move to your home folder.

### Browser tabs and split view

⌘T or the **+** button opens a new browser tab with the current folder, sort, and view. ⌘W closes
the current browser tab when there is more than one. With one browser tab, ⌘W closes the Hub.
Click a tab to select it. A tab's close button appears on hover.

**Split View** in the status bar, or ⌥⌘S, shows two panes side by side. The second pane starts in
Downloads and keeps its folder when you turn split off. Each pane has its own folder, sort,
history, and selection. Both use the browser tab's view. Click a pane, or press Tab or Shift-Tab,
to make it active. The sidebar, back and forward, the keyboard, and the current-folder search
scope apply to the active pane. Split view hides the Kind column.

### Views, sorting, and navigation

The status bar switches between **List**, **Icons**, and **Columns** for the current browser tab.
These views have no keyboard shortcuts, because ⌘1 to ⌘3 switch Hub tabs.

- **List** shows Name, Date Modified, Kind, and Size. Size is the space a file takes on disk.
  Folders show no size.
- **Icons** shows Quick Look thumbnails in a grid, with each file's size or each folder's item
  count.
- **Columns** shows one column per folder, from the nearest sidebar location to the current
  folder.

Click a column header in List to sort by it. Click it again to reverse the order. Name and Kind
sort ascending first, and Date Modified and Size newest or largest first. Names sort the way Finder
sorts them, so "File 2" comes before "File 10". Folders stay on top only when sorting by name. The
sort also applies in Icons and Columns, which have no sort control. Hidden files are never shown.

The breadcrumb bar starts at the nearest sidebar location or volume. Click a segment to go there.
Back and forward, or ⌘[ and ⌘], move through the pane's last 50 folders. ⌘↑ opens the enclosing
folder and selects the folder you left.

### Preview column and Quick Look

**Show Preview** in the status bar toggles a preview column on the right. One file shows a live
Quick Look preview after the selection settles. A folder shows its icon, and several items show a
fan of up to three icons. Below the preview are the name, kind, size, and modification date, and
for one item the **Open**, **Quick Look**, and **Reveal in Finder** buttons.

Space or ⌘Y opens the system Quick Look panel for the selection. Arrow keys move the selection
while it is open, and the panel follows. Escape or Space closes it.

### Search

Type in the header search field, or start typing over the listing. The scope bar offers
**This Mac** and the active pane's current folder. Search uses Spotlight and matches file and
folder names, ignoring case and accents. It does not search file contents.

Results replace the panes and show the name, location, date modified, and size. Prefix matches
come first, then recently used or modified items. Search collects at most 200 Spotlight results
and does not update while you look at them. Down moves from the search field into the results.
Return opens the selected result, or the first one when nothing is selected. A folder result opens
in the active pane and ends the search. A file opens in its default app. You can drag results out,
and folder results accept drops.

### Context menu and keyboard

Right-click an item for **Open**, **Quick Look**, **Reveal in Finder**, **Copy Path**, **Rename**,
**New Folder**, and **Move to Trash**. Right-click empty space for **New Folder**,
**Reveal in Finder**, and **Copy Path** for the current folder. **Copy Path** copies plain text, one
path per line. **Reveal in Finder** opens Finder with the item selected and closes an anchored Hub.

| Key | Action |
| --- | --- |
| Return, ⌘↓, double-click | Open. A folder opens in the pane. |
| ⌘↑ | Enclosing folder |
| ⌘[, ⌘] | Back, forward |
| Space, ⌘Y | Quick Look |
| ⌥⌘R | Reveal in Finder |
| ⌥⌘C | Copy Path |
| ⇧⌘N | New Folder |
| ⌘⌫ | Move to Trash |
| ⌘A | Select all in the active pane |
| ⌘T, ⌘W | New browser tab, close browser tab |
| ⌥⌘S | Split View |
| Tab, Shift-Tab | Switch the active pane |
| Arrow keys | Move the selection. Shift extends it. |

In Columns, Left opens the parent folder and Right opens the selected folder. Command-click
toggles an item and Shift-click extends the selection.

New Folder creates **untitled folder**, or a numbered name when that exists, and starts renaming
it. Rename edits the name in place, with the file extension left unselected. Return or clicking
away saves, and Escape cancels. Empty names, names with `/` or `:`, and names already in use show
an alert. Move to Trash uses the system Trash, so Finder's **Put Back** works. It asks for no
confirmation and the Files tab has no Undo.

The Files tab has no Copy, Paste, or Duplicate commands. To copy, drag with Option.

### Drag and drop

Drag items within the Hub, out to Finder or another app, or in from another app. Folders, empty
pane space, sidebar places, drives, and browser tabs accept drops. Recents and breadcrumbs do not.
Dropping items into the folder they are already in does nothing.

DOKK follows Finder's rule. A drop on the same volume moves the items, and a drop on another volume
copies them. Hold Option to copy on the same volume. When another app offers only a copy, DOKK
copies.

Hold a drag over a folder, a sidebar place, or a browser tab to spring-load it. The folder opens,
or the tab is selected, after the system spring-loading delay.

Dragging out hands other apps ordinary file URLs. If Finder or another app moves the files, that
app does the move. A drag from an anchored Hub keeps it open while you are over another app.

### Copy queue

Each drop becomes one job. Jobs run one at a time and keep running after the Hub closes. The status
bar shows the job, its progress and percentage, the source and destination folders, and a count
of waiting jobs. Finished items flash briefly in the destination pane, and a **Copied** or
**Moved** message shows for about two seconds.

- **Pause** stops the copy at the next point it can and **Resume** continues it.
- **Cancel** stops the running job and deletes the partly copied item. Items already finished stay
  at the destination. Cancelling a waiting job removes it.
- A failure stops the job and shows the error in the status bar for about two seconds.

The Files tab never replaces a file. A name already in use gets **copy**: `Report.pdf` becomes
`Report copy.pdf`, then `Report copy 2.pdf`. This applies to moves too. A move between volumes
copies each item, then deletes the original for good. The original does not go to the Trash.

A move on the same volume finishes at once and shows no byte progress. While the Hub is closed,
the progress ring on the DOKK tile shows the progress of all queued jobs.

### What the Files tab remembers

DOKK saves the browser tabs, each pane's folder and sort, split view, the active pane, the view,
the selected browser tab, and the preview column. It does not save history, selection, or search.
The first time, the Files tab opens with a split tab showing Documents and Downloads and a second
tab showing Downloads in Icons. A saved folder that no longer exists falls back to your home
folder.

## Open in Hub

**Open in Hub** shows a folder in the Files tab's active pane. A closed Hub opens on the display
under the pointer. The command replaces Open in Finder and Show in Finder in these places:

- The context menu and VoiceOver actions of a pinned folder and of Downloads.
- Folders inside an open folder stack. Files in a stack keep **Show in Finder**.
- A drive's hover card, context menu, and VoiceOver actions.

DOKK does not replace Finder system-wide. Double-clicking a folder elsewhere still opens Finder.
In the Hub, **Reveal in Finder** opens the item in Finder. A folder stack that cannot read its
folder still offers **Open in Finder**, because Finder can often open folders DOKK cannot.

## Accessibility and motion

- The switcher, header buttons, cards, rows, and drives have VoiceOver labels and actions. Window
  cards report Minimized or Hidden as their value. File rows offer Open and Quick Look actions.
  Drive rows offer Eject. Browser tabs offer Close Tab.
- Reduce Motion: the Hub fades in and out without scaling or moving. The tab switch fades without
  sliding, and the selection pill moves without animation. Hover lifts, entrance staggers, and the
  tile's halo rotation stop.
- Reduce Transparency: the Hub draws an opaque background instead of Liquid Glass.

## Known limitations

- File search finds only items in the Spotlight index. Folders excluded from Spotlight, unindexed
  volumes, and some network shares return nothing, and the tab does not say why.
- The Windows tab sees only the current Space, apart from minimized windows and hidden apps.
- macOS asks for permission the first time the Files tab reads Desktop, Documents, or Downloads.
- The Hub has no global keyboard shortcut. Open it from the tile or Focus Dock.
- A folder stack's access-denied view still offers Open in Finder.
- The Files tab has no Copy, Paste, Duplicate, or Undo commands yet. Drag with Option held to copy.
- Cancelling a move between volumes leaves the items that already moved at the destination, as in
  Finder. Only the item in progress is removed.
- Quitting DOKK during a copy or move cancels it and removes the partly copied item. If the volume
  stops responding, DOKK waits up to three seconds and then quits, leaving that partial item behind.
