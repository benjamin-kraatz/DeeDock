# DeeDock

A native macOS Dock alternative. It should look like the Dock, behave like the Dock, and feel like the Dock—with the flexibility macOS should have shipped.

Familiar by default. Precise when you want control.

## Status

The native dock and the first two customization slices are implemented for macOS 27: native Liquid Glass, pointer magnification, pinned and running applications, position/appearance settings, and one dock per connected desktop display. Each display has independent pins and optional overrides of shared defaults. Auto-hide remains planned. See [acceptance notes](docs/ACCEPTANCE.md) for what has been checked and what still needs hands-on validation.

## What we are building

The macOS Dock is the reference for visual quality, interaction, and responsiveness. DeeDock should earn its place through everyday use: recognizable app icons, predictable activation, clear running state, natural hover and motion, and reliable drag interactions.

The product roadmap includes:

- **A dock per monitor (implemented):** independent pins, shared defaults, per-setting overrides, and remembered disconnected displays.
- **Precise placement:** edge, alignment, offset, and distance from the screen edge, with fine-grained controls.
- **Activation zones:** control where pointer entry reveals a dock, the zone's dimensions, and reveal timing.
- **Size and appearance:** icon size, spacing, dock size, magnification, opacity, and fade controls.
- **Behavior:** reveal and hide delays, animation timing, auto-hide, and interaction preferences.

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
- Hover to magnify nearby icons and see an app-name label. Running applications have a dot beneath them.
- Right-click an app for **Open**, **Pin**, or **Unpin**. Pins belong to that display and persist across restarts; unpinned running apps remain visible on every dock until they quit.
- Initially pinned apps are Finder, Safari, Mail, Calendar, and System Settings when installed. Newly opened regular apps join the running section automatically.
- Choose **Focus Dock** from the DeeDock menu-bar item or app menu. It targets the enabled dock under the pointer, falling back to the primary enabled dock and then the first enabled display in Settings. Left/right arrows select an app, Return opens it, and Escape returns focus to the previous app. Only one dock has keyboard focus at a time; the command is disabled when all docks are disabled.
- Choose **Quit DeeDock** from the menu-bar item or app menu to close it.

The default icons are 48 points, with 8-point spacing and 12-point padding. Crowded docks reduce icon size to 32 points before scrolling horizontally. Reduce Motion disables magnification, and Reduce Transparency uses an opaque native background.

Enabled docks are always visible. Auto-hide, activation-zone controls, drag reordering, stacks/Trash, window previews, opacity/fade controls, and launch-at-login are not implemented.

## Position and appearance settings

Choose **Settings…** from the menu-bar item or app menu (⌘, while DeeDock is active). The single native Settings window applies valid edits immediately and saves them automatically.

| Control | Range / options | Default |
| --- | --- | --- |
| Icon size | 32–96 points | 48 |
| Maximum magnification | 1.0×–2.0×, in 0.05 steps | 1.4× |
| Horizontal alignment | Left / Center / Right | Center |
| Horizontal offset | −1,000 to +1,000 points | 0 |
| Bottom distance | 0–300 points | 8 |
| Position relative to | Usable desktop / Screen edge | Usable desktop |

Numeric controls support sliders and locale-aware typed values. Invalid drafts never enter layout calculations; leaving the field restores the last accepted value. **Restore Defaults** on the Defaults page resets shared configuration only and preserves display overrides, visibility, and pins. Unreadable saved settings are left intact and reported in Settings; Restore Defaults explicitly replaces them.

Positive horizontal offsets move right. Bottom distance measures to the glass's bottom edge. Placement is constrained to keep the magnification envelope on the display, so left/right alignment or large offsets can be adjusted near an edge. Requested values remain saved across geometry changes. Crowded docks may use smaller icons than requested before scrolling; the requested size returns when space is available.

A 1.0× maximum disables magnification; Reduce Motion also disables it without changing the saved preference. Glass height stays fixed during hover, with icons and labels using a separate envelope above it. Screen-edge positioning can overlap the system Dock; neither mode changes macOS preferences. Settings resolve separately for each display. This slice stops at multiple docks; auto-hide requires a subsequent review and authorization.

## Displays and inheritance

The Settings sidebar retains the appearance/position panes, search, cards, and live previews, and adds connected and remembered displays. **Defaults** changes the shared values. Selecting a display exposes **Show Dock** and the same controls. Editing a control creates an explicit override; **Use Default** restores inheritance for that control. **Use Defaults** clears all appearance/position overrides on that display while preserving its pins and visibility.

New displays start enabled and copy the primary display’s current pins once, including an empty list. Later pin changes remain local. Disconnected displays remain editable and recover their settings on reconnect. You can disable every dock and reopen Settings from the menu-bar item to recover.

Display profiles use public ColorSync UUIDs, independent of screen order, names, and primary-display changes. Mirroring renders one dock using the mirror source’s profile; follower profiles remain saved. If macOS supplies missing or duplicate identity, affected docks use temporary state for that connection and Settings reports the limitation. Temporary profiles never replace saved profiles.

Existing settings remain shared defaults under their original preferences key. Legacy pins are retained and migrated to the initial primary profile; each display’s pins are stored separately. Malformed data is reported without silently replacing saved bytes. Unreadable display metadata blocks profile edits; unreadable pins block pin writes for that display. This slice adds no profile deletion or repair screen.

## Implementation and validation

One application catalog owns workspace observation, running order, icon caching, and duplicate-suppressed launches. A coordinator reconciles display snapshots and owns global pointer monitoring and exclusive keyboard focus. Each panel keeps its own pins, selection, hover, scroll state, geometry, and error feedback. Removing a dock invalidates its launch callbacks without cancelling shared work; quitting cancels pending tasks and removes observers, monitors, and panels. Geometry, identity resolution, ordering, and focus routing policies are independent of native windows.

The shared `DeeDock` scheme includes `DeeDockTests`, an unhosted Swift Testing target compiling the same model, ordering, persistence, and geometry sources used by the app. Its tests cover geometry, magnification, overflow, ordering, favorites persistence, display identity and focus policy, migration, empty-pin seeding, per-setting inheritance, and stale launch/cancellation behavior without launching DeeDock. Tests have been compiled, but not executed. Follow `AGENTS.md` before running them.

## Source organization

- `DeeDock/App` owns the app entry point and native lifecycle composition.
- `DeeDock/Dock/Models` defines application references, render snapshots, and ordering.
- `DeeDock/Dock/Layout` contains platform-independent placement and magnification calculations.
- `DeeDock/Dock/Persistence` and `Services` isolate preferences and workspace operations.
- `DeeDock/Displays` supplies display snapshots, persistent identity resolution, and selection policies.
- `DeeDock/Dock/Coordination` owns panel reconciliation and application-wide event/focus routing.
- `DeeDock/Dock/State` holds the shared application catalog and per-panel stores and interaction geometry.
- `DeeDock/Dock/Windowing` owns each AppKit panel and its local focus and handler lifecycle.
- `DeeDock/Dock/Views` separates live-store wiring, scrolling, surface composition, app buttons, material, and errors.
- `DeeDock/Dock/PreviewSupport` provides deterministic fixtures with inert actions, compiled only in Debug.
- `DeeDock/Settings` groups shared settings, display profiles and persistence, sidebar navigation, and focused native controls.
- `DeeDockTests` contains the focused model tests. The Xcode **Test Model Sources** group references the app's source files for the unhosted test target; it does not contain copies.

Useful previews live beside their views: pinned/running/unavailable apps, launch progress, empty content, error text, and dark appearance with reduced motion/transparency. Open the canvas for `DockContentView`, `DockAppButton`, `DockBackgroundView`, or `DockErrorBanner`. Settings previews include multiple displays, per-setting overrides, and a disconnected display using isolated in-memory stores. Previews do not construct live workspace services, read saved pins, or launch applications. Production accessibility values are read from SwiftUI's environment and passed into the same presentation components used by previews.

## UI copy and translation

All app-owned UI copy lives in [Localizable.xcstrings](DeeDock/Resources/Localizable.xcstrings): menu commands, Pin/Unpin actions, accessibility text, empty-state guidance, and errors. Edit the English values there and add translations in Xcode. Stable keys generate typed Swift symbols automatically; translator comments explain each string and named placeholder.

Use generated `LocalizedStringResource` symbols in SwiftUI and defer error-message localization until display. Use `String(localized:)` for AppKit APIs that require a resolved string. Application names and underlying system error descriptions are supplied by macOS and are displayed as provided. Keep persistent storage keys separate from translated UI copy.
