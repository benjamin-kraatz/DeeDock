# Patch bay ports and limits

Patch bay v0 connects an app pin's successful open event to a folder pin's **Open in Finder** action. The editor is in **Settings → Features → Patch bay**. Cable actions are off by default. Creating or replacing a cable saves the connection without running it.

## Supported ports

| Port | Direction | Behavior |
| --- | --- | --- |
| App opened | Output | Fires after a successful app-pin click or Window Peek's Show App action through `DockStore`, including keyboard activation. Hiding the foreground app does not fire it. |
| Open folder | Input | Resolves the folder pin's security-scoped bookmark and asks Finder to open that directory in the background. The source app keeps focus. |

Select an app output and then a folder input to connect them, or drag between the ports. Native buttons support keyboard and VoiceOver routing. Escape cancels an unfinished cable. Saved cables also appear as text with **Run folder action** and **Disconnect** controls. Run folder action invokes the cable's destination directly without opening the source app.

The editor shows app and folder pins for the selected enabled display in the current Dock Mode. An empty board needs at least one app pin and one folder pin. Switching modes does not run any action.

## Scope and execution

- Up to eight saved cables across all displays and Dock Modes.
- One outgoing cable per app in each display and mode. Reconnecting replaces that cable. Several app outputs can target the same folder.
- One folder action runs at a time. Additional triggers during that action are ignored, with no queue or replay.
- Both pins must still exist in the cable's mode on its connected, enabled display. Unavailable cables remain listed so they can be removed. Returning to that scope makes the connection eligible again.
- A mode switch, pin removal, or display change that makes a running cable unavailable cancels pending work. Disabling cable actions, editing cables, sleep, screen lock, and app shutdown also cancel pending work.
- Cancellation cannot undo an open request already sent to Finder. Finder's acknowledgement is reported as such; it does not prove a window became visible.
- Missing folders and stale or invalid bookmarks report failure. Automation never falls back to a saved path. Re-pinning the folder and reconnecting restores access.

The successful-open event is local to DDock's app-pin action path. Opens from Spotlight, the system Dock, Launcher, other window-management menus, workspace recipes, spring loading, and file drops do not trigger cables. Running-only apps and historical pin previews are excluded.

## Storage and APIs

`dock.patch-bay.v1` in UserDefaults stores a versioned document containing the enable switch, cable IDs, display and mode IDs, pin IDs, and last-known names. Storage is bounded to 64 KiB. Folder bookmarks stay in the existing pin store. Run status is transient and never replays at launch.

Malformed or unsupported documents freeze editing and execution without overwriting the stored bytes. **Reset patch bay** explicitly removes those bytes, clears all cables, and turns execution off. Disconnecting a cable does not unpin anything or modify files.

Execution uses public Foundation bookmark APIs and `NSWorkspace` to open the directory with Finder. It adds no Accessibility, Screen Recording, or Automation permission request, observer for other apps, shell process, network service, or system Dock preference change.

## Non-goals

v0 has no arbitrary action nodes, chains, branching, loops, delays, schedules, scripts, Shortcut execution, app-lifecycle monitoring, data transformation, file copying, or automatic startup runs. It does not replace Shortcuts. Folder actions never emit app-pin events, so Finder cannot feed back into the graph.

## Acceptance status

See [DEE-58 acceptance](ACCEPTANCE.md#dee-58-patch-bay-automations) for compile evidence and the pending native checks.
