# DeeDock

A native macOS Dock alternative. It should look like the Dock, behave like the Dock, and feel like the Dock—with the flexibility macOS should have shipped.

Familiar by default. Precise when you want control.

## Status

The native dock and the first three customization slices are implemented for macOS 27: native Liquid Glass, pointer magnification, pinned and running applications, position/appearance settings, and one dock per connected desktop display. Each dock can sit on the bottom, top, left, or right edge. Apps can be arranged by drag-and-drop, imported from Finder, and copied between display docks. Each display has independent pins and optional overrides of shared defaults, including auto-hide, activation zones, and ten reveal/hide animation styles. See [acceptance notes](docs/ACCEPTANCE.md) for what has been checked and what still needs hands-on validation.

## What we are building

The macOS Dock is the reference for visual quality, interaction, and responsiveness. DeeDock should earn its place through everyday use: recognizable app icons, predictable activation, clear running state, natural hover and motion, and reliable drag interactions.

The product roadmap includes:

- **A dock per monitor (implemented):** independent pins, shared defaults, per-setting overrides, and remembered disconnected displays.
- **Precise placement, implemented:** bottom, top, left, or right edge; alignment, along-edge offset, and distance from the chosen reference edge.
- **Activation zones (implemented):** choose dock-position or screen-edge triggering, length, depth, along-edge offset, and reveal timing.
- **Size and appearance (implemented):** icon size, spacing, magnification, running indicators, background visibility and opacity, and configurable idle fading.
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

- Click an icon to open or activate its application.
- Hover to magnify nearby icons and see an app-name label. Running applications have a dot toward the selected screen edge.
- Right-click an app for **Open**, **Pin**, or **Unpin**. Pins belong to that display and persist across restarts; unpinned running apps remain visible on every dock until they quit.
- Initially pinned apps are Finder, Safari, Mail, Calendar, and System Settings when installed. Newly opened regular apps join the running section automatically.
- Choose **Focus Dock** from the DeeDock menu-bar item or app menu. It targets the enabled dock under the pointer, falling back to the primary enabled dock and then the first enabled display in Settings. Left/right arrows select an app on top and bottom docks; up/down arrows select an app on side docks. Return opens it, and Escape returns focus to the previous app. Only one dock has keyboard focus at a time; the command is disabled when all docks are disabled.
- Choose **Quit DeeDock** from the menu-bar item or app menu to close it.

The default icons are 48 points, with 4-point item spacing and 6-point glass padding. Crowded docks reduce icon size to 32 points before scrolling along the dock, horizontally above or below, or vertically beside the display. Reduce Motion disables magnification, and Reduce Transparency uses an opaque native background.

Enabled docks stay visible by default; auto-hide is opt-in under Behavior. Stacks/Trash, window previews, and launch-at-login are not implemented.

## Arrange applications with drag-and-drop

- Drag a pinned app along the dock to reorder it. Drag a running app into the pinned section to pin it at that position. Running-only order remains automatic.
- Drop one or more application bundles from Finder into the pinned section. The whole batch must contain valid, accessible applications other than DeeDock. Existing pins move into the dropped block; duplicate app identities appear only once.
- Drag an app onto another display’s DeeDock to pin it there without removing the source pin. An existing destination pin moves to the chosen position.
- Drag a pin at least 64 points outside its dock to see **Unpin**, then release to unpin it. Returning closer or pressing Escape cancels removal. Releasing over another DeeDock that rejects the drop keeps the source pin. Running apps remain in the running section after unpinning; applications are never quit or deleted.
- During dragging, magnification settles to resting icon sizes and a live gap shows insertion. Overflowing docks scroll near their viewport edges. A hidden dock uses its existing activation zone and reveal delay; the source and revealed destination stay visible during the relevant interaction.
- Pin edits save only when a drop completes. Cancelled drags restore the saved arrangement. Invalid batches are rejected together, and save errors appear on the affected dock.

Right-click a pin for **Move Left** and **Move Right** on a top or bottom dock, or **Move Up** and **Move Down** on a side dock. **Pin on Display…** works with every edge. With **Focus Dock** active, hold Option with the corresponding arrow key to reorder the selected pin; ordinary arrows navigate. VoiceOver exposes equivalent move and destination actions. The Pin on Display menu appends a new pin and leaves an existing destination pin in place.

Finder imports retain optional read-only security-scoped bookmarks so user-selected application bundles can remain accessible after restart. Older pins retain their existing format and identity. DeeDock adds only the app-scoped bookmark capability to its existing sandbox configuration; no Accessibility grant or system Dock preference changes are involved. Missing applications remain visible as unavailable pins.

This slice does not support documents dropped onto apps, file export, or selecting multiple apps within DeeDock. Runtime acceptance for dragging, focus, auto-hide, cross-display copying, and sandbox access remains pending; see the latest acceptance entry.

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
| Background opacity | 0–100%, in 10% steps | 100% |
| Fade when idle | On / Off | Off |
| Fade target | Entire dock / Background only / Icons and indicators only | Entire dock |
| Idle opacity | 0–100% of normal appearance, in 5% steps | 40% |
| Idle delay | 0–30 seconds, in 1-second steps | 3 seconds |
| Fade-out duration | 0–2 seconds, in 0.05-second steps | 0.3 seconds |
| Restore duration | 0–0.5 seconds, in 0.05-second steps | 0.1 seconds |

Turning off the background leaves floating icons with the same geometry and hit regions. Background opacity affects the native material, its border and shadow, and the pinned-section separator. The saved opacity returns when the background is enabled again.

Idle means no interaction with that display's dock. Working elsewhere allows it to fade. Idle opacity multiplies normal appearance: a 60% background at 50% idle opacity becomes 30%, while icons become 50%, when Entire dock is selected. Labels, keyboard outlines, launch progress, and error feedback retain full opacity.

Pointer entry, keyboard focus, VoiceOver focus, dragging, menus, mouse-button interaction, and errors restore visibility and prevent further fading during interaction. Even at 0% idle opacity, the dock retains its hit regions and restores on pointer entry. Auto-hide takes precedence; hidden docks do not schedule idle fading, and every reveal starts at normal opacity. Sleep, display refreshes, and teardown cancel stale deadlines. Each dock owns its own idle timing.

Reduce Motion restores instantly and caps fade-out at 0.1 seconds. Reduce Transparency suppresses idle fading and uses an opaque background when enabled, while preserving saved preferences. A hidden background stays hidden. The Normal and Idle samples show the effective appearance; **Play Preview** includes the configured idle delay and cancels when settings change or the view closes.

Compilation is verified; hands-on acceptance for material opacity, restoration timing, and native interaction remains pending in the [acceptance record](docs/ACCEPTANCE.md).

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
| Activation depth | 1–64 points | 8 |
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
- `DeeDock/Settings` groups shared settings, display profiles and persistence, sidebar navigation, and focused native controls.
- `DeeDockTests` contains the focused model tests. The Xcode **Test Model Sources** group references the app's source files for the unhosted test target; it does not contain copies.

Useful previews live beside their views: pinned/running/unavailable apps, launch progress, empty content, error text, and dark appearance with reduced motion/transparency. Open the canvas for `DockContentView`, `DockAppButton`, `DockBackgroundView`, or `DockErrorBanner`. Settings previews include multiple displays, per-setting overrides, and a disconnected display using isolated in-memory stores. Previews do not construct live workspace services, read saved pins, or launch applications. Production accessibility values are read from SwiftUI's environment and passed into the same presentation components used by previews.

## UI copy and translation

All app-owned UI copy lives in [Localizable.xcstrings](DeeDock/Resources/Localizable.xcstrings): menu commands, Pin/Unpin actions, accessibility text, empty-state guidance, and errors. Edit the English values there and add translations in Xcode. Stable keys generate typed Swift symbols automatically; translator comments explain each string and named placeholder.

Use generated `LocalizedStringResource` symbols in SwiftUI and defer error-message localization until display. Use `String(localized:)` for AppKit APIs that require a resolved string. Application names and underlying system error descriptions are supplied by macOS and are displayed as provided. Keep persistent storage keys separate from translated UI copy.
