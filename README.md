# DeeDock

A native macOS Dock alternative. It should look like the Dock, behave like the Dock, and feel like the Dock—with the flexibility macOS should have shipped.

Familiar by default. Precise when you want control.

## Status

The first native dock slice is implemented for macOS 27: one dock on the primary display, native Liquid Glass, pointer magnification, favorites, and running applications. Fine-grained configuration and multiple docks remain planned. See [acceptance notes](docs/ACCEPTANCE.md) for what has been checked and what still needs hands-on validation.

## What we are building

The macOS Dock is the reference for visual quality, interaction, and responsiveness. DeeDock should earn its place through everyday use: recognizable app icons, predictable activation, clear running state, natural hover and motion, and reliable drag interactions.

The planned flexibility includes:

- **A dock per monitor:** independently configurable docks, with sensible behavior when displays connect, disconnect, or change arrangement.
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

## Using the first slice

DeeDock starts as a menu-bar app, without a normal document window or a second icon in the system Dock. Its dock is centered above the primary display’s usable bottom edge, leaving room for the system Dock when macOS reserves that space. If the system Dock auto-hides, its transient reveal can overlap DeeDock; dedicated coexistence controls are future work.

- Click an icon to open or activate its application.
- Hover to magnify nearby icons and see an app-name label. Running applications have a dot beneath them.
- Right-click an app for **Open**, **Pin**, or **Unpin**. Pinned apps persist across restarts; unpinned running apps remain visible until they quit.
- Initially pinned apps are Finder, Safari, Mail, Calendar, and System Settings when installed. Newly opened regular apps join the running section automatically.
- Choose **Focus Dock** from the DeeDock menu-bar item or app menu. Left/right arrows select an app, Return opens it, and Escape returns focus to the previous app.
- Choose **Quit DeeDock** from the menu-bar item or app menu to close it.

The default icons are 48 points, with 8-point spacing and 12-point padding. Crowded docks reduce icon size to 32 points before scrolling horizontally. Reduce Motion disables magnification, and Reduce Transparency uses an opaque native background.

This slice is always visible. Auto-hide, activation-zone controls, multiple docks, drag reordering, stacks/Trash, window previews, custom appearance controls, and launch-at-login are not implemented.

## Implementation and validation

The workspace service resolves applications and caches their icons. An observable store combines persisted favorites with workspace notifications. A display-specific AppKit controller manages placement, pointer passthrough, and explicit keyboard focus; SwiftUI renders the surface. Geometry and ordering are independent of AppKit.

The shared `DeeDock` scheme includes `DeeDockTests`, an unhosted Swift Testing target compiling the same model, ordering, persistence, and geometry sources used by the app. Its tests cover geometry, magnification, overflow, ordering, and favorites persistence without launching DeeDock. Tests have been compiled, but not executed. Follow `AGENTS.md` before running them.

## Source organization

- `DeeDock/App` owns the app entry point and native lifecycle composition.
- `DeeDock/Dock/Models` defines application references, render snapshots, and ordering.
- `DeeDock/Dock/Layout` contains platform-independent placement and magnification calculations.
- `DeeDock/Dock/Persistence` and `Services` isolate preferences and workspace operations.
- `DeeDock/Dock/State` holds the observable store and per-panel interaction geometry.
- `DeeDock/Dock/Windowing` owns the AppKit panel, focus, and event-monitor lifecycle.
- `DeeDock/Dock/Views` separates live-store wiring, scrolling, surface composition, app buttons, material, and errors.
- `DeeDock/Dock/PreviewSupport` provides deterministic fixtures with inert actions, compiled only in Debug.
- `DeeDockTests` contains the focused model tests. The Xcode **Test Model Sources** group references the app's source files for the unhosted test target; it does not contain copies.

Useful previews live beside their views: pinned/running/unavailable apps, launch progress, empty content, error text, and dark appearance with reduced motion/transparency. Open the canvas for `DockContentView`, `DockAppButton`, `DockBackgroundView`, or `DockErrorBanner`. Previews do not construct a live store, read saved pins, or launch applications. Production accessibility values are read from SwiftUI's environment and passed into the same presentation components used by previews.

## UI copy and translation

All app-owned UI copy lives in [Localizable.xcstrings](DeeDock/Resources/Localizable.xcstrings): menu commands, Pin/Unpin actions, accessibility text, empty-state guidance, and errors. Edit the English values there and add translations in Xcode. Stable keys generate typed Swift symbols automatically; translator comments explain each string and named placeholder.

Use generated `LocalizedStringResource` symbols in SwiftUI and defer error-message localization until display. Use `String(localized:)` for AppKit APIs that require a resolved string. Application names and underlying system error descriptions are supplied by macOS and are displayed as provided. Keep persistent storage keys separate from translated UI copy.
