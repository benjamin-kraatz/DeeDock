# DeeDock acceptance record

Recorded on 2026-09-02 with macOS 27.0 (26A5425a) and Xcode 27.0 (27A5252f). Earlier sections retain historical observations; the final section records the current multi-display slice.

## Compilation

The focused Debug app build succeeded. The shared scheme's test build also succeeded, including the unhosted `DeeDockTests` target. No test cases were executed and no automated visual suite was run.

Commands used:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-build build

xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-build build-for-testing
```

The initial command-sandbox build failed because Xcode's Swift macro helper produced malformed responses. Building outside that command sandbox succeeded; this did not disable the app's App Sandbox. App sandbox and signing settings remain enabled and unchanged.

Local artifacts are at `/tmp/DeeDock-build/Build/Products/Debug/DeeDock.app`; build logs are `/tmp/DeeDock-build.log` and `/tmp/DeeDock-test-build.log`. These temporary artifacts are not release packages.

## Interactive observations

- DeeDock opened as a native panel with real app icons, running dots, a material background, a favorites separator, and hover labels. Captured states included magnified and resting icons.
- The accessibility tree exposed app names, running/not-running values, and Keep in Dock/Remove from Dock actions.
- A running app's context menu exposed Open and Keep in Dock.
- Ghostty was pinned, observed in favorites after quitting and reopening DeeDock, and then unpinned to restore its original running-only status.
- Clicking the Calendar favorite launched it and changed the running state. Calendar was closed again, and DeeDock subsequently returned its indicator to Not running.
- Focus Dock appeared in the native app menu. Choosing it displayed a focus ring and Finder label; Right moved the ring and label to Safari. Return and Escape paths were exercised, but return-to-previous-app focus was not independently established.
- Quit DeeDock and reopening were exercised during the build/inspection cycle.

These observations establish the specific behaviors above, not complete visual or interaction parity with the system Dock. The UI inspection tool may raise/activate its target, so it cannot by itself prove that normal pointer interaction preserves the foreground app.

## Remaining hands-on acceptance

- With a text field active in another app, move across DeeDock and its transparent margins. Confirm hover never steals keyboard focus and clicks in unused margins reach the underlying app. Repeat while apps join or leave the dock.
- Use Focus Dock, arrows, Return, and Escape; confirm the intended application becomes active and Escape restores the previous application. Check activation with minimized, hidden, and windowless applications.
- Check horizontal overflow and keyboard scrolling with enough running apps to exceed the display width.
- Compare glass, shadows, icon movement, label placement, and click targets against the macOS Dock on light and dark desktop content.
- Exercise VoiceOver, Reduce Motion, and Reduce Transparency. The implementation includes these behaviors; system settings were not changed during inspection.
- Reconfigure/unplug/reconnect displays, including displays with negative origins and different scaling. Confirm the single dock follows the primary display and stays within its usable frame.
- Exercise normal Spaces, full-screen apps, Mission Control, and sleep/wake. The panel joins normal desktop Spaces; it does not request full-screen auxiliary overlay behavior. Exact OS behavior still needs hands-on acceptance.
- Exercise unavailable favorite apps and failed launches. Check the visible error message, dismissal, and removal of missing favorites.
- Confirm idle resource use and smoothness with Instruments before making performance claims; verify complete observer/panel teardown under repeated lifecycle changes.

## Boundaries

The app uses public AppKit/SwiftUI APIs and local preferences. It does not modify system Dock preferences, grant permissions, install a login item, reserve desktop work area, or manage other apps' windows through Accessibility APIs. Reopening/minimized-window behavior is delegated to Launch Services and the target app; exact system Dock parity is not promised.

Placement uses the primary display's `visibleFrame`. When the system Dock auto-hides, macOS may not reserve space for it, so its temporary reveal can overlap DeeDock. Avoiding that overlap, persistent per-monitor choices, auto-hide, activation zones, drag reordering, and the wider configuration roadmap remain later slices.

## Copy and localization update

The app actions now read **Pin** and **Unpin**. All app-owned UI copy is managed in `DeeDock/Resources/Localizable.xcstrings`, including conditional accessibility labels and interpolated errors. The catalog contains English values and translator comments; other languages have not been added. Application names and underlying system error descriptions still come from macOS.

The focused Debug app build succeeded with derived data at `/tmp/DeeDock-localized-build`. The compiled English strings resource was inspected and contains all 16 catalog entries, including correctly emitted positional placeholders. No tests or automated visual checks were run for this update; animation behavior was not changed.

## Organization and preview refactor

App composition, models, persistence, workspace operations, observable state, native windowing, and SwiftUI components now live in focused files and folders. Shared interfaces have Swift documentation comments, with critical invariants documented at coordinate conversion, stable magnification, focus reentrancy, cancellation, and persistence boundaries. Existing placement, animation constants, ordering, storage keys, and launch behavior are retained.

Xcode MCP `BuildProject(buildForTesting: true)` succeeded on 2026-09-02 for the DeeDock scheme, compiling the app, Debug preview declarations, and the unhosted test target against the four extracted shared sources. The build log confirms compilation and linking of `DeeDockTests`; no tests were executed. The final successful build log is `/var/folders/q5/16skxm0d1rlgnyf53r13c1rm0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260902-191904.txt` (temporary local artifact).

Preview fixtures are deterministic and use inert actions. Preview rendering, automated visual checks, and runtime interaction were not exercised for this refactor. Prior interactive observations above describe the earlier build; the remaining hands-on acceptance still applies.

## Fixed-height magnification surface

The glass now keeps its resting height during pointer magnification. Icons remain anchored at the bottom and can extend above the glass within the existing panel envelope. Label placement clears the enlarged icon. Native pointer handling includes each exposed app-button frame, clipped to the viewport, while leaving unused transparent margins available to the underlying app.

A focused `xcodebuild` Debug `build-for-testing` for the DeeDock scheme succeeded with derived data at `/tmp/DeeDock-magnification-build`; Xcode MCP was unavailable because its transport was closed. The log is `/tmp/DeeDock-magnification-build.log`. The only build warnings reported skipped App Intents metadata extraction because these targets do not depend on AppIntents. The new geometry regression test compiled but was not executed, and the magnified-state preview was not rendered.

Hands-on acceptance still needs to confirm constant glass height while moving between icons, labels above enlarged icons, clicking the exposed icon area, and click passthrough in empty space above the glass, including during horizontal scrolling. No runtime or automated visual acceptance was performed for this change.

## Position and appearance settings slice

Native Settings now exposes icon size, maximum magnification, alignment, horizontal offset, bottom distance, and usable-desktop/screen-edge positioning. Usable desktop remains the default. Valid edits save immediately, display fitting preserves requested preferences, and Restore Defaults leaves pins untouched. Invalid saved settings use defaults without overwriting the saved bytes until an explicit reset.

The focused Debug app and test-target compilation succeeded using `xcodebuild ... build-for-testing`, with derived data at `/tmp/DeeDock-settings-build` and log `/tmp/DeeDock-settings-build.log`. Xcode MCP remained unavailable (transport closed), so the command-line build was used. Only skipped App Intents metadata extraction warnings were reported. No tests were executed, no previews were rendered, and no automated visual checks were run.

New tests cover settings defaults, numeric validation/normalization, persistence and reset without changing pins, unreadable settings preservation, both placement references with negative origins, alignment/offset clamping, overflow, and the maximum magnification envelope with fixed glass height. Settings and maximum-size dock previews use isolated state and do not read or write real preferences.

Runtime acceptance remains unexercised for this slice: opening/reopening the same Settings window through both menus and the ⌘, shortcut, live sliders and numeric entry (including locale decimal separators), reset while editing, persistence after restart, focus preservation, screen-edge placement, labels and click targets at maximum size, Reduce Motion/Transparency, keyboard/VoiceOver use, and display changes/wake. Build success does not establish native feel or runtime acceptance. Implementation stops here for review; multiple docks have not been started.


## Slice 2: one dock per monitor

Implemented after the committed Settings redesign (`3a3114f`), preserving its sidebar artwork, search, pane transitions, cards, sliders, numeric fields, and inline previews. Added display scope, visibility controls, individual inheritance actions, and remembered disconnected displays. All new production copy is in `Localizable.xcstrings`; previews use deterministic in-memory display fixtures.

### Implementation contracts

- One shared catalog owns workspace observation, running order, icon caching, and duplicate-suppressed launches. Each panel owns its own render store, hover, scrolling, selection, hit regions, effective geometry, and launch-error feedback. Cache pruning uses all active docks.
- A coordinator owns global pointer monitors and reconciles enabled logical desktop surfaces. Existing panels are reused on arrangement, geometry, and settings changes. Disabled/disconnected panels are stopped and released. Only one panel can own keyboard focus; removal restores the previous application when available.
- ColorSync UUIDs identify persistent profiles. Primary-first discovery preserves legacy pins and seeds new displays once from current primary pins, including an intentionally empty list. Changing the primary display does not transfer profiles.
- Mirroring uses the source profile for one panel and preserves follower profiles. Duplicate/missing UUIDs become session-local identities, with a Settings warning and no saved-profile replacement.
- Shared defaults retain the original settings key. Metadata and each display's pins have separate keys; original pins remain intact. An initial-primary marker makes interrupted migration retryable. Malformed data produces localized errors and blocks affected writes rather than replacing saved bytes.
- Per-setting overrides inherit independently. Resetting shared defaults does not clear overrides, visibility, or pins; Use Defaults on a display clears only its overrides. All docks may be disabled while Settings and Quit remain available.
- Panel removal invalidates its completion token without cancelling a shared launch. Application shutdown removes observers and monitors, closes panels, and cancels launch tasks. Cancellation cannot undo a request already submitted to Launch Services.

### Compilation and authored coverage

The focused Debug app and unhosted test target compiled successfully with Xcode 27 on 2026-09-02:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-displays-build build-for-testing
```

Result: **TEST BUILD SUCCEEDED**. Log: `/tmp/DeeDock-displays-build.log`. Xcode MCP was attempted but its transport was closed, so the focused command-line fallback was used. Only skipped App Intents metadata extraction warnings were reported. The existing Swift language mode, signing, sandbox, deployment target, and dependencies are unchanged.

Added tests cover legacy migration, preserved empty lists, primary-first/one-time seeding, independent pins, primary reassignment, inheritance and explicit-equal overrides, resets preserving visibility and pins, offline profile edits, interrupted migration, corrupt-byte preservation, session-only identity, mirrored/disabled display selection, pointer/fallback focus routing, stale panel completions, shared launch suppression, and shutdown cancellation. Existing geometry coverage remains for negative origins, display fitting, overflow, and fixed-height magnification. The tests use isolated preferences and a controlled application service; they do not launch real applications.

**No test cases were executed. No previews were rendered, no automated visual checks were run, and no hands-on app acceptance was performed for slice 2.** Compilation establishes neither passing assertions nor native interaction quality. Native panel reconciliation, monitor teardown, and actual focus restoration still require runtime checks beyond the policy/session tests.

### Remaining hands-on acceptance for the current build

- Show simultaneous docks on displays with different scaling and negative origins; confirm placement uses each display's current frame and usable frame.
- Hover, magnify, scroll, and select independently. Confirm fixed glass height, exposed-icon clicks, labels, transparent click passthrough, keyboard overflow access, and no foreground-app activation from hover.
- Pin/unpin locally, including an empty primary list before attaching a new monitor. Restart and reconnect to confirm independent persistence and one-time seeding.
- Change shared defaults and individual overrides; confirm untouched controls follow defaults and individual/all override resets preserve visibility and pins. Edit a remembered disconnected display and reconnect it.
- Disable every dock and recover through Settings. Exercise Focus Dock under the pointer and its fallback order. Disable or unplug the keyboard-focused dock and verify restoration to the previous app.
- Change primary display, rearrange, disconnect/reconnect, and enable/disable mirroring. Verify source-only rendering and follower profile restoration. Where hardware permits, exercise missing/duplicate display identity and its session-only warning.
- Launch from one dock while interacting with another; verify duplicate suppression and failure placement. Disconnect the initiating display before completion and confirm no stale UI or disruption elsewhere.
- Check light/dark appearance, Reduce Motion/Transparency, VoiceOver, keyboard-only Settings, normal Spaces, full-screen apps, Mission Control, and sleep/wake.
- Quit with multiple panels and with a pending launch; verify all panel/monitor/observer resources are released. Measure performance separately before claiming idle-use or frame-rate results.

Public display UUIDs can be unavailable or ambiguous for some hardware/virtual-display configurations; this is reported rather than guessed from a name or screen position. DeeDock does not reserve desktop work area or modify the system Dock. Screen-edge positioning or a transient system-Dock reveal may overlap it. Actual mirroring/Spaces behavior remains subject to macOS and hardware acceptance.

Changes are left uncommitted for review. Slice 2 stops here; auto-hide, activation zones, pin-management screens, profile deletion, and release work remain outside scope.
