# Vapor

Vapor is a glass orb that floats on the desktop. You drop cache and build folders onto it, then hold to delete them all at once. Deleting skips the Trash, and you can undo for 5 seconds. Linear: DEE-160. Mockup: [`mockups/vapor-orb.html`](mockups/vapor-orb.html).

The Trash is slow for folders like `node_modules` or DerivedData, because they hold tens of thousands of small files. Vapor replaces the routine of copying each path into Terminal and running `rm -rf`.

## Behavior

### Turning it on

- The DOKK menu bar extra gets a **Vapor** toggle in its Tools section, shown with a checkmark when on. That toggle is the only switch: there is no keyboard shortcut and no Dock tile item.
- The on/off state, the orb's position and the folders in the orb survive relaunch.
- Turning Vapor off hides the orb and keeps its folders. Turning it on again brings them back.
- Turned on, the orb condenses: particles gather into it while it grows with a small overshoot. Turned off, it swells slightly, then shrinks away. At launch it is simply there.

### The orb

- A 112 pt glass sphere in a borderless, non-activating panel at the floating level. It appears on every Space and over full-screen apps.
- Clicking the orb, its bubbles or its panel never activates DOKK, so Finder stays in front.
- **Drag** the orb to move it, on any display. Its position is stored per display identity, not per screen-array index. If its display goes away, the orb moves to the main display.
- **Click** opens or closes the panel.
- **Right-click** shows: Open, Delete All… (opens the panel and nudges the delete button), Clear Without Deleting, Hide Vapor.
- **Hover** shows a tooltip: "Drop folders here" when empty, otherwise "3 folders · 1.8 GB", or "3 folders · calculating…" while sizes are pending.
- A count badge sits on the orb's outer top corner, the one facing away from the screen centre, so suggestion bubbles never cover it.
- **Fill:** each folder appears inside the orb as a real folder icon that tumbles under simple 2D physics. Bigger folders get bigger icons, on a log scale. When the pile would overflow, every icon shrinks to fit. Dragging the orb makes the contents slosh. A new folder pops in at the top, and the orb squashes briefly.
- The physics loop runs only while something is moving and sleeps once the pile settles.
- An empty orb shows a faint "drop here" glyph.

### Lighting

Each display has a virtual lamp just above the middle of its top edge.

- The orb's highlight, rim light and bottom caustic turn toward the lamp, from the orb's centre in that display's coordinates.
- The contact shadow slides away from the lamp.
- Highlights get fainter with distance from the lamp.
- Lighting updates only when the orb moves.

### Dropping folders

Dropped items fall into the orb, or into the open panel, which is also a drop target.

| Dropped item | Result |
| --- | --- |
| A folder | Accepted |
| A file | Refused: "Vapor takes folders, not files." |
| Already in the orb, or inside a folder that is | Refused: "*name* is already in Vapor." |
| A parent of folders already in the orb | Accepted; the contained folders are removed from the orb |
| A protected location | Refused, with the orb shaking red and a short message |

Protected locations:

- `/` and every volume root
- the home folder: "DOKK won’t delete your home folder."
- the standard home folders (Desktop, Documents, Downloads, Library, Applications, Movies, Music, Pictures, Public): "*name* is a standard macOS folder. DOKK won’t delete it."
- `/System`, `/Library`, `/Applications`, `/usr`, `/bin`, `/sbin`, `/private`, `/etc`, `/var`, `/opt`, `/cores` and anything inside them
- `~/Library` itself (its subfolders such as `~/Library/Caches/...` are allowed)
- any bundle (`.app`, `.framework` and so on): Vapor takes folders, not packages

### Recognized folders

Classification looks only at the name and at sibling marker files.

| Rule | Tag | Suggested |
| --- | --- | --- |
| `node_modules` | npm packages | yes |
| `.next` | Next.js build | yes |
| `.nuxt` | Nuxt build | yes |
| `.svelte-kit` | SvelteKit build | yes |
| `.turbo` | Turborepo cache | yes |
| `.parcel-cache` | Parcel cache | yes |
| `coverage` | Test coverage | yes |
| `.build` next to `Package.swift` | SwiftPM build | yes |
| `DerivedData` (under `~/Library/Developer/Xcode`, or a project's own) | Xcode build cache | yes |
| a direct child of an Xcode DerivedData folder | Xcode build data | yes |
| `ModuleCache.noindex` | Xcode module cache | yes |
| `~/Library/Caches/org.swift.swiftpm` and its children | SwiftPM cache | yes |
| `target` next to `Cargo.toml` | Cargo build | yes |
| `Pods` next to `Podfile` | CocoaPods | yes |
| `.gradle` | Gradle cache | yes |
| `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache` | Python cache | yes |
| `dist`, `build`, `out` | Build output | **no** |

- `dist`, `build` and `out` get a tag when dropped but are never suggested, because some projects commit them.
- Anything else gets an orange **Not a known cache** tag. The panel then shows the note "1 folder isn’t a known cache. Check before you delete."

### Sizes

Each folder's allocated size and file count are measured in the background as soon as it lands.

- Measurement can be cancelled when the folder is removed.
- Rows show a "Calculating…" shimmer, then count up to the result.
- Totals stay pending until every measurement finishes.
- An unreadable folder shows "—" instead of a size.

### The panel

A non-activating glass panel grows out of the orb toward the screen centre, with a spring. It has, in order:

1. **Header:** a mini orb, "Vapor", and a subtitle ("3 folders · 1.8 GB"). On the right, a **Clear** button takes everything out without deleting.
2. **Found in *folder*:** this section appears only while Finder suggestions exist. One row per suggestion with an **Add** button, and **Add All** in the header.
3. **Folder rows:** icon, name, tag chip, parent path in monospace, size and file count. A remove (×) button appears on hover. An empty orb shows "Drop build folders and caches here." with "Nothing is deleted until you hold Delete."
4. **Drop zone:** "Drop more folders here". It highlights while a drag hovers the panel.
5. **Footer:** "Total 1.8 GB · 104,226 files", then the **Hold to Delete 3 Folders** button.
   - Holding for 0.9 s fills the button left to right. Releasing early drains it back.
   - The VoiceOver action deletes right away, since holding isn't practical there.
   - A note below the button reads "Skips the Trash. You can undo for 5 seconds." It is replaced by the unknown-folder warning when one applies.

Escape, or a click outside, closes the panel. The panel can't take focus, so Escape works only while the pointer is over it.

### Deleting

1. On completion of the hold, the rows are pulled into the orb, the panel shrinks back into it, and the orb plays **evaporate**:
   - icons rise and fade, giving off steam particles
   - a soft flash plays inside the glass
2. At the same moment every folder is **staged**: renamed into the staging location on its own volume. Finder shows it gone right away.
3. A capsule appears above the orb: "Deleted 3 folders", a 5-second countdown ring, and **Undo**.
   - **Undo** renames the folders back, and they drop into the orb again. The capsule changes to "Put back 3 folders" for a moment.
   - If the original path is taken by then, that folder stays staged and the capsule says it couldn't be restored.
4. After 5 seconds the capsule turns into "✓ Freed 1.8 GB", and a background task removes the staged files.
5. If a folder can't be staged (permission denied, a volume that doesn't support renames, the folder is gone), it stays in the orb. Its row shows the reason, and the capsule mentions the failures.

### Finder suggestions

While Vapor is on, the orb is visible and Finder is the frontmost app, Vapor reads the folder shown in Finder's front window.

- It lists that folder's direct children and keeps those that match a **suggested** rule above, minus anything already in the orb or staged.
- Up to five bubbles float beside the orb, on the side facing the screen centre.
- A capsule just beyond them reads "4 caches in dokk-web", with **Add All** and ×. It keeps 10 pt clear of the bubbles, whatever its text.
  - Hovering a bubble changes the capsule to "node_modules · npm packages".
  - Clicking a bubble flies it into the orb: it dives behind the glass, and its folder drops into the pile as it lands.
  - When a bubble comes or goes, the others and the capsule glide to their new places.
  - × hides suggestions for that folder until Finder shows a different folder.
- While the panel is open, the bubbles hide and the suggestions appear as the panel's **Found in *folder*** section instead.
- Nothing is ever added automatically.

## Implementation notes

All code lives in `DeeDock/Vapor/`, with tests in `DeeDockTests/Vapor/`. The project uses synchronized folders, so no `project.pbxproj` edits are needed. The default actor isolation is `MainActor`; mark background types `nonisolated`.

### Staging and removal

- **Staging location:** a hidden `.dokk-vapor` directory.
  - On the home volume it is `~/Library/Caches/DOKK/Vapor/staging`.
  - On any other volume it is `<volume root>/.dokk-vapor`.
  - If that directory can't be created, the folder is renamed in place to `.<name>.dokk-vapor-<uuid>` in its own parent.
  - A rename never crosses volumes. Compare `volumeIdentifierKey` before renaming; on a mismatch, use the in-place fallback.
- **Ledger:** `~/Library/Application Support/DOKK/Vapor/ledger.json` records each staged path, its original path, its size and when it was staged. It is written before the rename, and the entry is updated after it.
- **Removal:** after the undo window, a background task (utility QoS) lists the staged folder's top-level children and calls `removefile(_:_:REMOVEFILE_RECURSIVE)` on them, at most 4 at a time. It then removes the staged folder and clears the ledger entry.
- **Recovery:** on launch, DOKK finishes removing every ledger entry still staged, even if Vapor is off. A staged folder is never restored without an explicit Undo.
- **Undo** is a rename back to the original path. It never overwrites an existing item.

### Finder

- **When to read:** when Finder becomes active (`NSWorkspace.didActivateApplicationNotification`). While it stays active, an `AXObserver` on Finder's PID listens for `kAXFocusedWindowChangedNotification`, `kAXMainWindowChangedNotification` and `kAXTitleChangedNotification`; title changes follow folder navigation. The observer is removed when Finder deactivates or Vapor turns off. Without Accessibility trust, Vapor reads only on activation.
- **Debounce:** 250 ms. Then an actor runs a read-only Apple Event script: the URL of the target of `Finder window 1`, the frontmost Finder window. A window with no folder target (Recents, search results) yields nothing.
- **Automation permission:** checked first with `AEDeterminePermissionToAutomateTarget(..., askUserIfNeeded: false)`. While the user hasn't decided, the panel shows a one-line "Show caches from the open Finder folder" with a **Turn On** button. That button asks with `askUserIfNeeded: true`. Vapor never prompts on its own. If permission was denied, it shows nothing.
- **Scanning:** listing children and classifying them happens off the main thread, and is cancelled when the folder changes.

### Windows

- **Orb:** an `NSPanel` with `[.borderless, .nonactivatingPanel]`, at level `.floating`, with collection behaviour `[.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`. It is never key or main.
- **Panel and suggestions:** separate panels with the same flags. Each is placed from the orb's frame and the visible frame of the orb's display, in AppKit global coordinates. Negative origins and non-primary displays must work.
- **Suggestions window:** covers the orb, the whole bubble arc and every place the capsule can take, so its frame depends only on where the orb is. Bubbles glide inside it and fly into the orb without being clipped. The orb's window stays in front of it.
- **Drops:** an AppKit `NSDraggingDestination` registered for `.fileURL` on the orb and the panel. It reports hover proximity to the orb view for the lean and glow.
- **Orb canvas:** the orb's window is the 112 pt orb plus a 48 pt transparent margin on every side, for the badge, the squash, the drop lean and swell, and steam rising out of the glass. Only the sphere takes clicks. Liquid Glass is composited outside the window's backing, so the window's own alpha hit-testing reads the sphere as transparent and passes clicks on it through. `VaporOrbPointerGate` follows the pointer with global and local mouse monitors and sets the window's `ignoresMouseEvents` explicitly: `false` over the sphere and `true` everywhere else, as the dock's panels do. File drags from Finder move the gate too, so the orb takes a drop when a drag reaches it.
- **Panel window:** larger than the panel. It also covers the orb, so the panel can grow out of the orb and rows can fly into it without being clipped. The orb's window stays in front of it. Drops count only over the panel itself.
- **Lifecycle:** panels are re-placed on display changes (`DisplayService`) and after wake. Everything is torn down when Vapor turns off or DOKK quits.

### Fill and motion

- **Physics:** `VaporPhysicsWorld` is a value type stepped in fixed 1/180 s substeps: gravity, circle collisions, the glass as a circular wall, spin from sliding contact, slosh from the orb's drag acceleration, and fit-to-orb shrinking. It is seeded, so tests and snapshots repeat.
- **Idle cost:** the world sleeps once the pile rests (or after 3 s without input). The orb's `TimelineView` is paused while it sleeps, so a settled orb draws nothing.
- **Delete sequence:** the rows fly into the orb one after another, the panel shrinks back into it, then the orb evaporates and the capsule appears. `VaporMotion` holds the shared timings.
- **Folder drawing:** the pile and the bubbles use Vapor's own small folder (`VaporFolderGlyph`), because the system icon reads as a plain tile at those sizes. Panel rows use the system folder icon.
- **Turning off:** the coordinator keeps the windows for the orb's exit (about a third of a second), then tears everything down.

### Snapshots

`VaporSnapshotTests` renders the orb, panel, capsules and bubbles to PNGs for review against the mockup. It runs only when `VAPOR_SNAPSHOT_DIR` is set:

```sh
TEST_RUNNER_VAPOR_SNAPSHOT_DIR=/path/to/out xcodebuild test -project DeeDock.xcodeproj -scheme DeeDock \
  -destination 'platform=macOS' -testLanguage en -only-testing:DeeDockTests/VaporSnapshotTests
```

Offscreen rendering can't draw Liquid Glass, so panels and capsules use a flat tint in the images, and the orb shows its tint and lighting without the blur behind it.

### Accessibility and motion

- **The orb** is an accessibility element: "Vapor, 3 folders, 1.8 GB". Its actions are Open and Delete All.
- **Rows** have labels and a Remove action.
- **Reduce Motion:**
  - no tumbling: the pile is placed already settled
  - no slosh, lean or squash
  - the panel fades instead of springing
  - evaporate becomes a fade
  - the orb fades in and out instead of condensing and shrinking
  - bubbles fade in place and don't glide
- **Reduce Transparency:** opaque fills instead of glass.

### Analytics

Count-only events. No paths or folder names are sent.

| Event | Properties |
| --- | --- |
| `vapor_toggled` | `enabled` |
| `vapor_folders_added` | `source` (`drop`, `suggestion`, `add_all`), `count` |
| `vapor_deleted` | `count`, size bucket |
| `vapor_undo` | `count` |
