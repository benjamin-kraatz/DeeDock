# DeeDock

A native macOS Dock alternative. It should look like the Dock, behave like the Dock, and feel like the Dock—with the flexibility macOS should have shipped.

Familiar by default. Precise when you want control.

## Status

Project setup only. The app is still the original SwiftUI “Hello, world!” starter; none of the Dock features below are implemented. The first implementation slice awaits agreement with the project owner.

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

Open `DeeDock.xcodeproj` in Xcode, select the `DeeDock` scheme and **My Mac**, then run when you want to inspect the starter app.

Current checked-in configuration:

| Setting | Starter value |
| --- | --- |
| Platform | macOS only |
| Deployment target | macOS 27.0 |
| Swift language mode | Swift 5 (`SWIFT_VERSION = 5.0`) |
| Default actor isolation | MainActor |
| Approachable concurrency | Enabled |
| App Sandbox | Enabled |
| External package dependencies | None |

Use an Xcode version and host OS compatible with the configured target. The minimum supported macOS version, Swift language mode, distribution channel, and sandbox/permission strategy remain product and engineering decisions. The starter settings are not release commitments. No build or runtime acceptance has been established by this setup.

## Working in this repository

Read [AGENTS.md](AGENTS.md) for implementation guidance, scope boundaries, and validation expectations.

Three project-local agent skills are installed under `.agents/skills`: SwiftUI Expert, Swift Concurrency, and Swift Testing. See [docs/SKILLS.md](docs/SKILLS.md) for their purpose, pinned sources, and update instructions. They add development guidance, not app dependencies.

## Proposed first slice

**A single working dock on one display.** Agree on its visual reference and the minimum supported macOS version before implementation.

The proposed slice is a native dock surface with real application icons, running-state indicators, and click-to-launch or activate. Pointer entry should not take keyboard focus, and quitting should cleanly remove the dock. It should establish a credible native look and interaction baseline before adding the full customization UI.

Acceptance should include a hands-on check of appearance, focus, launching/activation, and teardown. Multi-monitor configuration, activation-zone tuning, and advanced hide/fade controls follow in later agreed slices. This proposal does not authorize implementation.
