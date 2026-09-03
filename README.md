# DeeDock

A native macOS Dock alternative. It should look like the Dock, behave like the Dock, and feel like the Dock—with the flexibility macOS should have shipped.

Familiar by default. Precise when you want control.

## Status

The native dock and the first three customization slices are implemented for macOS 27: native Liquid Glass, pointer magnification, pinned and running applications, position/appearance settings, and one dock per connected desktop display. Each dock can sit on the bottom, top, left, or right edge. Apps can be arranged by drag-and-drop, imported from Finder, and copied between display docks. Each display has independent pins and optional overrides of shared defaults, including auto-hide, activation zones, and ten reveal/hide animation styles. A first-launch tour introduces the dock and guides hiding the macOS Dock. See [acceptance notes](docs/ACCEPTANCE.md) for what has been checked and what still needs hands-on validation.

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

Use Xcode 27 and macOS 27. The app retains the original Swift language mode, App Sandbox, and signing configuration. Distribution and broader OS support are not part of this slice. DeeDock does not request Accessibility access or change the system Dock’s preferences.

## Working in this repository

Read [AGENTS.md](AGENTS.md) for implementation guidance, scope boundaries, and validation expectations.

Three project-local agent skills are installed under `.agents/skills`: SwiftUI Expert, Swift Concurrency, and Swift Testing. See [docs/SKILLS.md](docs/SKILLS.md) for their purpose, pinned sources, and update instructions. They add development guidance, not app dependencies.

## Using DeeDock

DeeDock starts as a menu-bar app, without a normal document window or a second icon in the system Dock. By default, each dock is centered above its display’s usable bottom edge, leaving room for the system Dock when macOS reserves that space. If the system Dock auto-hides, its transient reveal can overlap DeeDock; dedicated coexistence controls are future work.

- Click an icon to open or activate its application. Click the foreground application's icon to hide all of its windows; click again to show and activate it.
- Hover to magnify nearby icons and see an app-name label. Running applications have a dot toward the selected screen edge by default. In Appearance, choose Dot, Bar, Square, Target Lock, Orbit, Stardust, Power Badge, Glitch, Plasma, Hologram, Solar Flare, Prism, Lava Chrome, Singularity, or Hidden from the Running indicators gallery, in shared defaults or for an individual display.
- Plasma, Hologram, Solar Flare, Prism, Lava Chrome, Singularity, and Glitch are Metal layer effects that read the app's own artwork: the light follows the icon's real silhouette and borrows its colours, and each app draws a different figure from a seed derived from its bundle identifier, so the same app always looks the same. Lava Chrome melts the icon's own corners and edges, Singularity puts an orbiting black hole that lenses and swallows part of the artwork, and Glitch slips its rows sideways and separates its colour channels. **Animate indicators** switches motion on for those seven and for Stardust; it is on by default, honours Reduce Motion, and stops while a dock is hidden or has faded out.
- Neon and Aura were withdrawn. A saved preference naming either migrates to Plasma and Solar Flare respectively, rather than failing to load.
- Right-click an app for **Open**, **Pin**, or **Unpin**. Pins belong to that display and persist across restarts; unpinned running apps remain visible on every dock until they quit.
- Initially pinned apps are Finder, Safari, Mail, Calendar, and System Settings when installed. Newly opened regular apps join the running section automatically.
- Choose **Focus Dock** from the DeeDock menu-bar item or app menu. It targets the enabled dock under the pointer, falling back to the primary enabled dock and then the first enabled display in Settings. Left/right arrows select an app on top and bottom docks; up/down arrows select an app on side docks. Return opens it, and Escape returns focus to the previous app. An outline marks the keyboard-selected icon, independently of running indicators. Only one dock has keyboard focus at a time; the command is disabled when all docks are disabled.
- Choose **Quit DeeDock** from the menu-bar item or app menu to close it.

The default icons are 48 points, with 4-point item spacing and 6-point glass padding. Crowded docks reduce icon size to 32 points before scrolling along the dock, horizontally above or below, or vertically beside the display. Reduce Motion disables magnification, and Reduce Transparency uses an opaque native background.

Enabled docks stay visible by default; auto-hide is opt-in under Behavior. Stacks/Trash and window previews are not implemented.

## Launch at login

Open **Settings → General → Launch at Login** to start DeeDock automatically when you sign in. General sits above Shared Defaults and applies to the whole app. Appearance remains the initial Settings pane. Search for login, startup, or automatic launch to find General.

The toggle reflects macOS’s registration status. It stays off until approval is granted. If approval is required, use **Open System Settings…** to open Login Items, or **Cancel Request** to withdraw the registration. Returning to the Settings window refreshes the status, including changes made outside DeeDock. An unavailable status provides Refresh and the System Settings link. Errors appear in General without automatic retries.

Turning off Launch at Login prevents future automatic launches and leaves DeeDock running. Login startup follows normal startup: configured docks and the menu-bar item appear without opening Settings or deliberately taking foreground focus. General remains usable if display settings have a storage error, and Restore Defaults does not change login registration.

The implementation uses `SMAppService.mainApp`; it stores no duplicate preference and installs no helper or launch-agent plist. Registration is opt-in. Real registration and logout/login acceptance require a consistently signed installed copy; see [acceptance notes](docs/ACCEPTANCE.md#launch-at-login).

## First launch

The first time DeeDock runs, a tour opens over the desktop. The docks are already live behind it, so every page describes something you can see. Seven pages: what DeeDock is, a guide to hiding the macOS Dock, placement, running indicators, auto-hide, one dock per display, and a closing page with the launch-at-login toggle.

Closing the window counts as finishing. The tour does not reappear on the next launch, whether you completed it or dismissed it on the first page. Choose **Welcome to DeeDock** from the menu-bar item or the app menu to see it again; reopening never changes what is stored.

One page changes a setting; the rest only demonstrate. **Put it where you want it** lets you click a screen edge, which sets **Edge** in shared defaults and moves the docks immediately. It writes shared defaults only and leaves per-display overrides alone, so a display already overriding that control keeps its own value, and the change is reversible in Settings.

That page carries a prompt line under its illustration and its handles respond to the pointer. The prompt is the only signal that a page is interactive; pages without one do nothing when clicked.

The macOS Dock page opens **System Settings → Desktop & Dock** and reports whether the Dock is still holding desktop space, updating as you change it. DeeDock never writes the system Dock's preferences; the page asks and then observes. The reading compares each screen's full and visible frames, because an App Sandbox cannot read another application's preferences: turning on *Automatically hide and show the Dock* releases the space and clears the status, while moving the Dock to another edge does not. The page can be skipped.

The illustrations use production code, not artwork. Placement runs the same `DockPlacement` calculation as a real dock, the running indicators are drawn by `DockIconIndicator` and `DockRunningIndicator`, and the auto-hide page is driven by the real `DockVisibilityController`. Reduce Motion holds a single frame on every page and cross-fades between them instead of sliding; Reduce Transparency uses opaque backgrounds. Only the visible page animates.

## Arrange applications with drag-and-drop

- Drag a pinned app along the dock to reorder it. Drag a running app into the pinned section to pin it at that position. Running-only order remains automatic.
- Drop one or more application bundles from Finder into the pinned section. The whole batch must contain valid, accessible applications other than DeeDock. Existing pins move into the dropped block; duplicate app identities appear only once.
- Drag an app onto another display’s DeeDock to pin it there without removing the source pin. An existing destination pin moves to the chosen position.
- Drag a pin at least 64 points outside its dock to see **Unpin**, then release to unpin it. Returning closer or pressing Escape cancels removal. Releasing over another DeeDock that rejects the drop keeps the source pin. Running apps remain in the running section after unpinning; applications are never quit or deleted.
- During dragging, magnification settles to resting icon sizes and a live gap shows insertion. Overflowing docks scroll near their viewport edges. A hidden dock uses its existing activation zone and reveal delay; the source and revealed destination stay visible during the relevant interaction.
- Pin edits save only when a drop completes. Cancelled drags restore the saved arrangement. Invalid batches are rejected together, and save errors appear on the affected dock.

Right-click a pin for **Move Left** and **Move Right** on a top or bottom dock, or **Move Up** and **Move Down** on a side dock. **Pin on Display…** works with every edge. With **Focus Dock** active, hold Option with the corresponding arrow key to reorder the selected pin; ordinary arrows navigate. VoiceOver exposes equivalent move and destination actions. The Pin on Display menu appends a new pin and leaves an existing destination pin in place.

Finder imports retain optional read-only security-scoped bookmarks so user-selected application bundles can remain accessible after restart. Older pins retain their existing format and identity. DeeDock adds only the app-scoped bookmark capability to its existing sandbox configuration; no Accessibility grant or system Dock preference changes are involved. Missing applications remain visible as unavailable pins.

File export and selecting multiple apps within DeeDock remain outside this slice. File and folder opening is described below. Runtime acceptance for dragging, focus, auto-hide, cross-display copying, and sandbox access remains pending; see the latest acceptance entry.

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

The Settings sidebar retains the appearance/position panes, search, cards, and live previews, and adds connected and remembered displays. **Defaults** changes the shared values. Selecting a display exposes **Show Dock** and the same controls. Editing a control creates an explicit override; **Use Default** restores inheritance for that control. **Use Defaults** clears all appearance, position, and behavior overrides on that display while preserving its pins and visibility.

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
- `DeeDock/Dock/Views` separates live-store wiring, scrolling, surface composition, app buttons, material, and errors.
- `DeeDock/Dock/PreviewSupport` provides deterministic fixtures with inert actions, compiled only in Debug.
- `DeeDock/Settings` groups shared settings, display profiles and persistence, sidebar navigation, and focused native controls. `General` contains the app-owned login-item controller, service boundary, and presentation.
- `DeeDock/Onboarding` holds the first-launch tour: step and reservation models, the completion record, navigation and screen-observation state, its AppKit window, and views. The models stay free of SwiftUI so the test target does not pull in the settings view layer.
- `DeeDockTests` contains the focused model tests. The Xcode **Test Model Sources** group references the app's source files for the unhosted test target; it does not contain copies.

Useful previews live beside their views: pinned/running/unavailable apps, launch progress, empty content, error text, and dark appearance with reduced motion/transparency. Open the canvas for `DockContentView`, `DockAppButton`, `DockBackgroundView`, or `DockErrorBanner`. Settings previews include multiple displays, per-setting overrides, and a disconnected display using isolated in-memory stores. Previews do not construct live workspace services, read saved pins, or launch applications. Production accessibility values are read from SwiftUI's environment and passed into the same presentation components used by previews.

## UI copy and translation

All app-owned UI copy lives in [Localizable.xcstrings](DeeDock/Resources/Localizable.xcstrings): menu commands, Pin/Unpin actions, accessibility text, empty-state guidance, and errors. Edit the English values there and add translations in Xcode. Stable keys generate typed Swift symbols automatically; translator comments explain each string and named placeholder.

Use generated `LocalizedStringResource` symbols in SwiftUI and defer error-message localization until display. Use `String(localized:)` for AppKit APIs that require a resolved string. Application names and underlying system error descriptions are supplied by macOS and are displayed as provided. Keep persistent storage keys separate from translated UI copy.
