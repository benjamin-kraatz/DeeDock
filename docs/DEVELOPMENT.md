# Developing DOKK

This page is for people working on DOKK's code. Read [AGENTS.md](../AGENTS.md) for contributor rules, scope boundaries, and validation expectations. For how features behave, see the [user guide](GUIDE.md). For signing, notarization, and publishing, see [release instructions](UPDATES.md).

## Product goals

The macOS Dock is the reference for visual quality, interaction, and responsiveness. DOKK should earn its place through everyday use: recognizable app icons, predictable activation, clear running state, natural hover and motion, and reliable drag interactions.

The product roadmap includes:

- **A dock per monitor (implemented):** independent pins, shared defaults, per-setting overrides, and remembered disconnected displays.
- **Precise placement, implemented:** bottom, top, left, or right edge; alignment, along-edge offset, and distance from the chosen reference edge.
- **Activation zones (implemented):** choose dock-position or screen-edge triggering, length, depth, along-edge offset, and reveal timing.
- **Size and appearance (implemented):** icon size, spacing, magnification, running indicators, background visibility, and configurable idle fading.
- **Behavior:** auto-hide, reveal/hide delays, and ten animation styles are implemented; broader interaction preferences remain planned.

These are product goals, not a finished feature specification. Exact options, ranges, defaults, and delivery order will be decided slice by slice.

### What good feels like

- Useful defaults before opening Settings; advanced controls stay discoverable without making normal use complicated.
- A dock that responds immediately without stealing focus just because the pointer entered it.
- Materials, spacing, shadows, labels, menus, and animation that belong on macOS.
- Consistent behavior across display arrangements, scaling, Spaces, full-screen apps, and sleep/wake.
- Keyboard access, VoiceOver labels, and respect for Reduce Motion and Reduce Transparency.
- Low idle resource use and smooth pointer interaction. Performance claims require measurement.
- A clear way to quit and return to the system Dock. The explicit, reversible coexistence switch is [Tuck away the macOS Dock](GUIDE.md#tuck-away-the-macos-dock); a full replacement flow still needs its own design.

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
| App Sandbox | Disabled; DOKK ships only as a direct download |
| External package dependencies | Sparkle 2.9.6 |

Use Xcode 27 and macOS 27. The app retains Swift 5 language mode and the existing signing configuration. For updates and releases, see [release instructions](UPDATES.md). DOKK requests Accessibility or Screen Recording access only after an explicit Enable or Allow action; it never asks at startup. DOKK does not change the system Dock’s preferences.

## Agent skills

Project-local agent skills live under `.agents/skills`. See [docs/SKILLS.md](SKILLS.md) for their purpose, pinned sources, and update instructions. They add development guidance, not app dependencies.

## Architecture

One application catalog owns workspace observation, running order, icon caching, and duplicate-suppressed launches. A coordinator reconciles display snapshots and owns global pointer monitoring and exclusive keyboard focus. Each panel keeps its own pins, selection, hover, scroll state, geometry, and error feedback. Removing a dock invalidates its launch callbacks without cancelling shared work; quitting cancels pending tasks and removes observers, monitors, and panels. Geometry, identity resolution, ordering, focus routing, and visibility policy are independent of native windows. Each panel owns a cancellable visibility controller with monotonic deadlines and finite animation ticks; idle settled docks schedule no visibility work. Drawing and native click passthrough share the same animation sample, while context-menu tracking is scoped to the owning dock.

## Tests

The shared `DeeDock` scheme includes `DeeDockTests`, a Swift Testing target hosted in the app. Tests use `@testable import DeeDock`, so every app type is available without a separate source list. The test host starts no dock, menu-bar item, or services, and tests inject their own `UserDefaults` suites and directories, because the host shares DOKK's preferences domain. Its tests cover geometry, magnification, overflow, ordering, favorites persistence, display identity and focus policy, migration, empty-pin seeding, per-setting inheritance, stale launch/cancellation behavior, auto-hide deadlines and reversals, ten animation styles and masks, behavior migration, and temporary preview lifetimes without launching DOKK. Drag coverage adds batch insertion, cross-display pin independence, deliberate unpinning, cancellation, insertion geometry, import validation, bookmark compatibility, blocked writes, and visibility holds. Follow `AGENTS.md` before running them.

## Continuous integration

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) builds DOKK and runs `DeeDockTests` on pull requests to `main`, pushes to `main`, and manual runs. The check name is **Build & Test**.

The job runs on the `xcode-27` runner and selects Xcode the same way the Release archive job does: the highest Xcode on that machine, which has to be Xcode 27 with the macOS 27 SDK. The build is Debug and unsigned (`CODE_SIGNING_ALLOWED=NO`). It does not notarize, and it does not read Sparkle or PostHog secrets. With no token, analytics stay off. A failure uploads `DeeDock.xcresult` and `xcodebuild.log` as the `build-and-test-results` artifact.

CI caches Swift package checkouts. The key is `Package.resolved`, the runner OS and architecture, and the selected Xcode version. There is no restore-key prefix. Compiled package products are not cached. Restoring PostHog intermediates and `XCBuildData` skipped those package compiles, and `DOKK` was still built from source, but the package compile is about 20–30 seconds and DeeDock's own compile is 2–4 minutes on this runner. Each job uses a fresh DerivedData directory under `RUNNER_TEMP`. CI sets `ENABLE_CODE_COVERAGE=NO`, which the script passes as `-enableCodeCoverage NO`. Leave that variable unset for a local run, including the pre-push hook, and the script keeps the shared scheme's coverage setting. Compile jobs follow `hw.ncpu`. The job log prints that count as `runner cores:`. Test runners stay at the scheme default.

The workflow and the optional pre-push hook both call [`scripts/build-and-test.sh`](../scripts/build-and-test.sh). To turn the hook on in one clone:

```sh
git config core.hooksPath .githooks
```

Git does not enable that path on its own. The hook needs `xcodebuild`. Skip it for one push with `git push --no-verify`.

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
- `DeeDock/Dock/History` owns the shared DOKK-local pin and Focus Session event model, persistence, and dock-axis scrub mapping. DEE-45 can reuse the same events for session playback.
- `DeeDock/Dock/Views` separates live-store wiring, scrolling, surface composition, app buttons, material, and errors.
- `DeeDock/Dock/PreviewSupport` provides deterministic fixtures with inert actions, compiled only in Debug.
- `DeeDock/Modes` owns named configurations, the keyboard picker, and optional workspace recipes. Recipe execution lives in `WorkspaceRecipeCoordinator` with per-run state that is never persisted.
- `DeeDock/Settings` groups shared settings, display profiles and persistence, sidebar navigation, and focused native controls. `General` contains the app-owned login-item controller, service boundary, and presentation. `Features` holds the app-wide pane for the Shelf, Trash, and Window Peek. `Modes` hosts recipe editing beside mode management.
- `DeeDock/Onboarding` holds the first-launch tour: step and reservation models, the completion record, navigation and screen-observation state, its AppKit window, and views. The models stay free of SwiftUI so the test target does not pull in the settings view layer.
- `DeeDockTests` contains the focused model tests. They run hosted in the app and reach app types through `@testable import DeeDock`.

## Previews

Useful previews live beside their views: pinned/running/unavailable apps, launch progress, empty content, error text, and dark appearance with reduced motion/transparency. Open the canvas for `DockContentView`, `DockAppButton`, `DockBackgroundView`, or `DockErrorBanner`. Settings previews include multiple displays, per-setting overrides, and a disconnected display using isolated in-memory stores. Previews do not construct live workspace services, read saved pins, or launch applications. Production accessibility values are read from SwiftUI's environment and passed into the same presentation components used by previews.

## UI copy and translation

All app-owned UI copy lives in [Localizable.xcstrings](../DeeDock/Resources/Localizable.xcstrings): menu commands, Pin/Unpin actions, accessibility text, empty-state guidance, and errors. Edit the English values there and add translations in Xcode. Stable keys generate typed Swift symbols automatically; translator comments explain each string and named placeholder.

Use generated `LocalizedStringResource` symbols in SwiftUI and defer error-message localization until display. Use `String(localized:)` for AppKit APIs that require a resolved string. Application names and underlying system error descriptions are supplied by macOS and are displayed as provided. Keep persistent storage keys separate from translated UI copy.
