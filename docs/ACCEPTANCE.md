# First-slice acceptance

Recorded on 2026-09-02 with macOS 27.0 (26A5425a) and Xcode 27.0 (27A5252f).

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
