# DeeDock acceptance record

Recorded on 2026-09-02 with macOS 27.0 (26A5425a) and Xcode 27.0 (27A5252f). Earlier sections retain historical observations; the final section records the current folder-stack slice.

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

The app uses public AppKit/SwiftUI APIs and local preferences. It does not modify system Dock preferences, grant permissions, install a login item, reserve desktop work area, or manage other apps' windows through Accessibility APIs. Application-icon clicks use AppKit's app-wide hide request when the selected app is foreground; reopening and minimized-window behavior remain delegated to Launch Services and the target app. Exact system Dock parity is not promised.

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


## Slice 3: auto-hide, activation zones, and ten animation styles

Implemented on 2026-09-03, preserving the existing Settings design and display-profile behavior. Automatically hide defaults to off. Shared defaults and individual display overrides now include activation location/width/height/offset, reveal and hide delays, animation style, and duration. Numeric controls preserve whole-point and 0.05-second precision. Missing behavior data in older settings receives defaults; malformed present data still reports an error without replacing saved bytes.

### Implemented behavior and ownership

- Each panel owns a visibility state machine, monotonic scheduling, and cancellable animation/deadline tokens. Pointer movement does not restart dwell deadlines. Native deadlines resample the actual pointer before applying a delayed action, and fresh input can cancel an expired but undelivered deadline. Settled idle docks schedule no visibility work.
- Activation can follow the resting glass bottom or the physical screen bottom. Dock-width or custom zones are centered on the resting dock with an independent horizontal offset and clamped to the display. A click-through connecting area retains the revealed dock while the pointer travels upward to it.
- Mouse interaction, the owning context menu, explicit keyboard focus, accessibility focus, and a visible error hold the dock open. Context menus use a scoped AppKit bridge with native open/close callbacks. Pending application launches do not hold visibility; errors appear and hold only on the initiating dock.
- Focus Dock reveals immediately. Fully hidden content is excluded from hit testing and accessibility. Scroll/application state persists across hiding, while pointer magnification resets. Disabling, disconnecting, wake/Spaces/display changes, and quitting invalidate stale work as appropriate; shared launch ownership remains unchanged.
- Ten styles use semantic storage identifiers: Glide & Seek, Slip Away, Ghost Mode, Up, Up & Away, Exit Stage Left, Right on Cue, Mini Me, Curtain Call, Squeeze Play, and Boing Voyage. They are grouped into Smooth Operators, Taking the Scenic Route, and A Little Drama. Style selection is static; explicit Play Preview animates an inert sample.
- Animation samples provide scale, translation, opacity, and masks to both SwiftUI presentation and native hit handling. A fixed native window envelope accommodates movement, clips at display boundaries, and preserves fixed glass height during magnification. Reversal begins at current progress. Reduce Motion uses a fade capped at 0.10 seconds; duration zero is instant.
- The deterministic diagram and ten-second Show Zone outline share production activation geometry. The outline is nonactivating and click-through, follows valid edits, and closes on selection/category change, actual Settings-window close, disappearance of its display, expiration, or shutdown. Preview leases reject stale expirations after replacement.
- All new production labels, group names, style names/subtitles, units, and help text are in Localizable.xcstrings. SwiftUI previews use in-memory settings and an explicit Reduce Motion fixture without changing system settings.

### Compilation and authored tests

Xcode MCP `BuildProject(buildForTesting: true, tabIdentifier: "windowtab-a2fQL021MS")` succeeded. The app and unhosted test target compiled; the test bundle was linked and signed. The final successful build log is:

`/var/folders/q5/16skxm0d1rlgnyf53r13c1rm0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260903-093540.txt`

The preceding full test compilation log is `BuildProject-Log-20260903-093155.txt` in the same temporary directory. New Swift actor-isolation diagnostics found during implementation were resolved. The remaining warnings only report skipped App Intents metadata extraction because the targets do not depend on AppIntents. Swift language mode, deployment target, signing, sandbox, and dependencies are unchanged.

New tests cover legacy decoding and corrupt-byte preservation; individual behavior inheritance and resets; all ten semantic style round trips; dimension/timing validation; screen/dock zone anchors; negative origins, clamping, overflow and magnification-independent zones; all animation endpoints, inverse transforms and masks; two-stage bounce; independent docks; dwell/hide cancellation; reversal continuity; interaction holds; immediate focus reveal; hidden content eligibility; zero-duration and Reduce Motion behavior; stale deadlines after geometry changes/teardown; and bounded preview leases. Scheduling tests use a manually advanced clock, not sleeping or live windows.

**No tests were executed. No app was launched for acceptance, no previews were rendered, and no automated visual checks were run.** Successful compilation does not establish passing assertions, native menu/focus behavior, animation smoothness, or Dock-like feel.

### Remaining hands-on acceptance

- Compare every style against its described motion at zero, default, and maximum duration. Exercise rapid pointer exits/returns during dwell, reveal, hide delay, and hiding, including interrupted bounce/wipe transitions. Check for jumps, clipping, input lag, and unintended clicks.
- Use both activation anchors with elevated docks, large offsets, custom widths/heights, overflow, different scaling, and negative screen origins. Confirm the invisible trigger and connecting area remain click-through, magnification stays stable, and transformed/masked click targets match visible content.
- Exercise right-click and Control-click menus from another active app. Keep a menu open beyond the hide delay, move outside the dock, select/cancel actions, and confirm the originating dock remains visible and does not activate DeeDock merely from hover.
- Exercise Focus Dock, arrows, Return, Escape, mouse-down holds, VoiceOver focus/actions, failed launches, and error dismissal. Confirm hiding removes accessibility elements and focus restoration still works when a dock is disabled or unplugged.
- Configure different displays independently; change Defaults and individual overrides, including controls matching the current default. Confirm resets preserve pins and visibility and hidden docks do not appear just because running apps or geometry refresh.
- Play Settings previews repeatedly, change styles during playback, close/reopen Settings, and use Show Zone while editing/switching displays or categories. Confirm the outline expires after ten seconds without capturing clicks or stealing focus.
- Exercise light/dark appearance, Reduce Motion/Transparency, multiple monitors, mirroring/unmirroring, primary-display changes, normal Spaces, full-screen apps, Mission Control, sleep/wake, and clean quitting during a transition/menu/preview/launch.

These native scenarios remain unexercised for this build. Display-edge activation can also reveal the system Dock; DeeDock neither changes its preferences nor reserves desktop work area. Window-overlap detection, pressure gestures, broader drag behavior, and performance guarantees are outside this slice. No new permissions or machine settings were requested or changed.

## Application icon show/hide toggle

Ordinary app-icon clicks now check the live foreground application. A matching foreground app receives AppKit's app-wide hide request. A closed, background, or hidden app keeps the existing `NSWorkspace.openApplication` path, which launches or activates without creating a second instance. Bundle identity takes priority so moving a pinned application does not break the match; bundle-less references fall back to their standardized application URL.

The primary icon action is separate from explicit Open. Context-menu Open, Focus Dock Return, file opening, and drag spring-loading never hide an app. All display docks still share duplicate suppression, cancellation, and error ownership through `ApplicationCatalog`. A rejected hide request produces localized feedback on the initiating dock. The sandbox and entitlements are unchanged, and the feature does not use Accessibility APIs or inspect individual windows.

The focused Debug app build and a subsequent `build-for-testing` compilation succeeded with derived data at `/tmp/DeeDock-show-hide-build`. The initial `build-for-testing` attempt exposed the scheme's missing test-target dependency and stopped before app compilation; building the app first allowed the same test-source compilation to succeed. Xcode still reports that `DeeDockTests` is missing its discovered dependency on `DeeDock`.

No tests were executed. The app was not launched, no previews were rendered, and no automated visual checks ran. Hands-on acceptance still needs to confirm foreground hide, hidden-app restoration, background activation, closed-app launch, multi-window app-wide hiding, multiple Spaces, full-screen apps, and rapid repeated clicks.

Implementation changes are left uncommitted for review. Pause after slice 3; further roadmap work requires a new request.

## App organization slice 1: drag-and-drop

Implemented on 2026-09-03 after the user selected and approved the app-organization plan. Includes per-display pin reordering, running-to-pinned insertion, multiple Finder application imports, copying pins between displays, and deliberate drag-out-to-unpin. Cross-display copying was explicitly included during planning. No later placement or appearance features were started.

### Behavior and implementation

- Native AppKit source tracking distinguishes a click from movement beyond 5 logical points. Internal pasteboards expose an opaque session token rather than file URLs; the active coordinator resolves its source display and application identity. AppKit destination callbacks accept same-dock moves and cross-dock copies.
- Temporary render slots show insertion gaps without editing the store or preferences. Resting geometry drives insertion while magnification is settled; overflow autoscrolling runs only during active dragging, including over the running section when necessary to reach off-screen pins.
- Successful pin edits use one save. Existing identities are relocated, incoming duplicates are removed, and cross-display copies preserve source pins. Failed writes retain saved state and show the existing error UI on the affected dock.
- Drag-out unpinning requires an explicit release, a pinned source, at least 64 points beyond its resting visible bounds, and no destination dock under the pointer. Cancellation and accepted destination drops take priority. AppKit failure alone never authorizes removal; late source callbacks must match the active native session.
- Finder batches are validated off the main actor before any pin commit. Non-apps, inaccessible bundles, mixed batches, and DeeDock itself are rejected. Worker cancellation and session tokens prevent late imports from changing replacement sessions. The existing pointer policy reveals hidden docks; native destination entry validates the payload after reveal, avoiding stale pasteboard reads during unrelated mouse drags.
- Source/destination holds integrate with auto-hide; normal visibility resumes after completion. Conflicting profile edits, display/placement changes, sleep, Space transitions, removal, and shutdown invalidate drag state. Temporary event monitors, import/cleanup tasks, and scrolling timers have explicit teardown.
- `ApplicationReference` adds optional bookmark data while preserving older pin decoding and stable identities. Scoped resource leases cover metadata, icons, and asynchronous launches. The app retains its sandbox and read-only user-selected-files setting and adds `com.apple.security.files.bookmarks.app-scope`; signing mode, language mode, deployment target, and dependencies are unchanged.
- Move Left/Right are available in native menus, VoiceOver actions, and Option–Left/Right during Focus Dock. Pin on Display lists other connected enabled docks, appends absent pins, and preserves existing destination positions. All app-owned copy uses the string catalog. Insertion, empty-dock, rejection, and removal feedback have inert previews.

### Compilation and authored coverage

The focused app and unhosted test target are compiled with:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-drag-build build-for-testing
```

Result: **TEST BUILD SUCCEEDED**. Build log: `/tmp/DeeDock-drag-build.log`. The only reported build warning was skipped App Intents metadata extraction because these targets do not depend on AppIntents.

A subsequent normal Debug app build using the same command with `build` instead of `build-for-testing` also returned **BUILD SUCCEEDED**; log: `/tmp/DeeDock-drag-app-build.log`. Its signed entitlements were inspected: App Sandbox, read-only user-selected files, app-scoped bookmarks, and the normal Debug `get-task-allow` entitlement. Xcode's build-for-testing artifact adds temporary testing permissions; that artifact must not be used as evidence of normal sandbox restrictions.

The string catalog parses with `jq empty`, the entitlement file passes `plutil -lint`, and `git diff --check` is clean. These are static checks, not runtime sandbox or native-interaction acceptance.

Added Swift Testing cases cover both reorder directions and boundaries, ordered batch insertion and duplicates, preserved bookmark metadata, transient gap identities, cross-display pin independence, running state after unpinning, explicit-release/cancel/committed-drop precedence, the removal threshold, scrolling coordinates, invalid Finder batches, bookmark failures and backward-compatible decoding, corrupt-byte preservation, stale session completion, and visibility-hold release/teardown. Tests use isolated stores and inert application services; importer fixtures use temporary bundles and injected bookmark data rather than launching apps or granting access.

**No test cases were executed. No app was launched, no previews were rendered, and no automated visual checks or hands-on acceptance were performed.**

### Required hands-on acceptance

- Verify native click-versus-drag behavior and context clicks without foreground-focus changes. Exercise Escape both before and after the drag threshold, outside release, and rejection over another dock; confirm cancelled drags never unpin.
- Reorder first/last pins, pin a running app, populate an empty dock, import multiple apps, and repeat imports containing existing pins. Verify insertion feedback and saved order after restart.
- Import an application from a user-selected restricted folder and restart DeeDock. Verify metadata, icon, and launch access from the stored bookmark, then exercise a moved or unavailable app.
- Exercise magnification settling, gap motion, Reduce Motion/Transparency, maximum sizes, horizontal overflow and edge scrolling in both directions, and transparent-margin click passthrough.
- Copy between displays with negative origins and different scaling. Test existing destination pins, rejected/disabled destinations, disconnects during dragging, conflicting settings/pin edits, sleep/wake, Spaces, and quitting mid-drag.
- Drag from Finder toward hidden activation zones at configured delays, including a stationary pointer during reveal, and verify destination holds and cleanup after successful, rejected, and cancelled sessions. Native AppKit tracking-loop delivery and foreground-app focus require runtime verification.
- Exercise native menu moves, Option-arrow reordering, VoiceOver move/copy actions, boundary-disabled actions, selection retention, and destination-specific save errors.

These checks are still pending. Compilation establishes neither drag-event delivery nor native interaction quality. The changes stop here for review and remain uncommitted.

## Settings display identification

Added an automatic, static accent outline and localized “Editing this display” badge naming the selected physical monitor. The marker appears only while the Settings window is active and more than one connected desktop surface exists. It follows display-profile selection and remains across Appearance, Position, and Behavior. Disabled docks are still identifiable; Defaults, disconnected profiles, and mirrored followers do not receive a marker.

The overlay uses a nonactivating AppKit panel with click-through content and no keyboard/main-window eligibility or accessibility focus target. Its frame uses the selected display’s full frame in logical points, including negative origins, and the badge sits below the visible-frame top inset. SwiftUI follows Reduce Transparency; no animation is used. Settings window/app notifications handle closing, reopening a retained window, focus changes, minimization, and app hiding. Display snapshots refresh placement and connectivity, and quitting explicitly closes the panel. Preview fixtures create no native overlays or preference changes.

The focused Debug app build (`xcodebuild -project DeeDock.xcodeproj -scheme DeeDock -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/DeeDock-drag-build build`) succeeded. Log: `/tmp/DeeDock-display-indicator-build.log`. The only build warning was skipped App Intents metadata extraction. The string catalog parses and the diff passes whitespace checks.

No tests, automated visual checks, app launches, or hands-on acceptance were performed for this change. Remaining acceptance: identify both monitors while switching profiles/categories; select Defaults and disconnected profiles; disable a dock; close/reopen/minimize Settings and switch apps; rearrange/unplug displays; check negative origins, scaling, notch/menu-bar placement, mirroring, full-screen Spaces, contrast, Reduce Transparency, and click/focus passthrough. Full-screen auxiliary participation is requested through a public AppKit API; actual Spaces behavior remains unverified.

## Feature 2: Left and right edge placement

Implemented on 2026-09-03 against `13adfdc`, including the user's committed item spacing, glass padding, and source-display Settings changes.

### Behavior and compatibility

- Defaults and display profiles support Bottom, Left, and Right. Each edge uses one shared alignment, offset, and edge distance. Positive offsets move right below and down beside the display. Pins keep their order; both side docks read top to bottom.
- `DockEdge` maps canonical dock geometry into physical top-left content coordinates. Placement converts those rectangles into AppKit screen coordinates. Icons, selection markers, running dots, separators, labels, scrolling, drag insertion, and native hit testing use the selected edge. Icons remain upright and magnify inward while glass thickness stays fixed.
- Activation length follows the dock axis; depth extends inward from the glass or selected screen edge. The Settings diagrams and Show Zone overlay use production geometry. Directional animation offsets, anchors, and masks use the same transformation as native input. Side-specific names and descriptions match their direction.
- Up/Down and Option-Up/Down navigate and reorder side docks. Menus and VoiceOver expose Move Up and Move Down. Cross-display copies support every source/destination edge pair. Finder imports, duplicate handling, bookmark access, and the 5-point drag and 64-point unpin thresholds remain in place. Transparent source-label space holds visibility without extending the unpin threshold; another dock still protects a rejected destination. Animated portions outside the visible mask cannot accept insertion.
- Edge changes clear obsolete hit regions, cancel active drag/import work through the existing owner, and invalidate visibility deadlines. Keyboard selection stays in the store. Horizontal/vertical changes recreate scrolling presentation and reveal the selected app when keyboard-focused; left/right changes keep scroll position. A geometry change alone does not reveal a hidden dock.
- Internal position and activation names now describe axes rather than bottom-only dimensions. Explicit Codable mappings preserve existing field names, alignment raw values, animation identifiers, and preferences keys. Missing edge defaults to bottom in shared settings and inheritance in display overrides. Unknown or null edge values refuse loading without replacing saved data.
- UI copy remains in the string catalog. Added inert previews cover both sides, magnification, long labels, overflow, empty content, insertion feedback, errors, and reduced-motion/transparency appearances. No preview launches apps or changes real preferences.

### Compilation and authored coverage

The focused Debug app build and the unhosted test-target build use the existing DeeDock scheme:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-edge-build build

xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-edge-build build-for-testing
```

Final results: **BUILD SUCCEEDED** for the app and **TEST BUILD SUCCEEDED** for the app plus test target. Logs are `/tmp/DeeDock-edge-app-build.log` and `/tmp/DeeDock-edge-test-build.log`. The normal final app build reported no warnings. The test build reported only skipped App Intents metadata extraction because the targets do not depend on AppIntents.

The initial sandboxed build could not run Swift macro plugins; subsequent builds ran outside that sandbox. This does not change the app's App Sandbox setting. The string catalog passes `jq empty`, the Xcode project passes `plutil -lint`, and `git diff --check` is clean.

New Swift Testing coverage checks legacy field compatibility, edge round trips, malformed-byte preservation, individual inheritance and resets, pin preservation, all edge alignments and reference frames, signed offsets, negative origins, clamping, overflow, fixed glass thickness, inward magnification, coordinate inverses, activation boundaries, all ten oriented animation masks, reduced-motion samples, vertical insertion/autoscroll, all nine cross-edge copy pairs, selected-app retention, keyboard direction mapping, and stale visibility callbacks. Existing model tests use the renamed interfaces. The test target explicitly includes the shared edge model.

**No tests were executed. No app was launched, previews rendered, or automated visual checks performed.** Compilation does not establish passing assertions, native event delivery, animation quality, or Dock-like feel.

### Remaining hands-on acceptance

- Place docks on different edges across multiple monitors. Check top/center/bottom alignment, positive/negative offsets, zero and maximum distance, usable-desktop versus screen-edge references, negative display origins, scaling, and display unplug/reconnect.
- Compare bottom placement with the committed baseline. On both sides, check upright icons and labels, outer running/selection markers, inward magnification, fixed glass thickness, readable errors, empty docks, and transparent-margin click passthrough.
- Exercise vertical scrolling and autoscrolling, Finder batches, running-to-pinned insertion, all mixed-edge copy directions, deliberate outside unpinning, Escape, rejected destinations, and settings changes during a drag. Verify saved order after restart.
- Exercise Focus Dock, parallel and perpendicular arrows, Option-arrow moves, native context menus, VoiceOver actions, and error dismissal. Confirm pointer interaction does not steal foreground focus and selected apps stay visible after an axis change.
- Check both activation anchors, offsets, custom dimensions, elevated docks, and pointer travel through the connecting region. Play every animation on both sides, including reversal, zero duration, Reduce Motion, and Reduce Transparency. Verify Show Zone and Settings previews follow edge edits and close correctly.
- Check ordinary Spaces, full-screen apps, Mission Control, mirroring, sleep/wake, and quitting during a transition or drag. Existing native collection behavior is unchanged; actual OS behavior remains unverified for this feature.

Top placement, idle fading, background controls, and system Dock coexistence settings are outside this feature. No permissions, system Dock preferences, signing settings, language mode, deployment target, or dependencies were changed. Stop here for user review.

## Top placement and fixed usable-desktop reference

Added on 2026-09-03 after the Bottom/Left/Right checkpoint `b564d85` at the user's request.

Top is available in shared defaults and per-display edge overrides. It keeps horizontal ordering and keyboard controls, with upright icons, indicators above, and magnification, labels, and callouts below. The shared coordinate transformation also maps activation, insertion, scrolling, animation masks, native hit testing, and previews. Top and Bottom share a scrolling axis, so switching between them retains scroll position.

For Top, **Position relative to** displays **Usable desktop** and is disabled. A caption explains that this avoids overlapping the menu bar and notch. A shared model rule selects the effective reference for both placement and Settings diagrams without rewriting the stored reference or its inheritance. The reference override status and reset action are hidden while Top is selected; they return with the saved choice on another edge. Activation location remains independent, and its top-specific help explains that physical screen-edge activation can also reveal the menu bar.

Authored coverage now includes Top in edge persistence, geometry, animation, input, and cross-display copy cases. Added assertions cover the forced usable-desktop frame, unchanged encoded reference values, inherited and explicit display requests, and restoring those requests after switching edges. Inert previews cover Top with magnification, long labels, overflow, reduced appearance settings, insertion feedback, errors, empty content, and a disabled reference picker whose saved choice is Screen edge.

Compilation succeeded with the existing scheme and build configuration:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-edge-build build-for-testing

xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-edge-build build
```

Results: **TEST BUILD SUCCEEDED** and **BUILD SUCCEEDED**. Logs are `/tmp/DeeDock-top-test-build.log` and `/tmp/DeeDock-top-app-build.log`. Both reported only skipped App Intents metadata extraction. The string catalog parses and the diff passes whitespace checks. No signing, sandbox, language-mode, deployment-target, or dependency settings changed.

No tests were executed, app launched, or automated visual checks performed. Runtime acceptance remains pending for the disabled picker and subtitle, defaults and override restoration, menu-bar auto-hide, notched and unnotched displays, mixed-edge monitors, negative origins, display rearrangement, scrolling and drag destinations, native menus and focus, VoiceOver, all animations and activation zones, Spaces/full-screen behavior, and sleep/wake. The placement restriction uses the existing display visible frame supplied by macOS; compilation does not establish behavior when reserved system UI changes. Stop for review before committing this addition.

## Running indicator styles

Added on 2026-09-03 before the planned background and idle-fading work.

Appearance offers fifteen styles for running applications: Dot, Bar, Square, Neon, Aura, Target Lock, Orbit, Stardust, Power Badge, Glitch, Plasma, Hologram, Solar Flare, Prism, and Hidden. A responsive thumbnail gallery replaces the original four-option segmented picker. The choice persists in shared defaults and can be overridden or reset independently per display. Existing saved defaults without the field use Dot; absent display overrides inherit. Unknown style values fail decoding through the existing settings error handling. The Hidden value is an explicit choice, separate from an absent override.

Dot, Bar, and Square follow all four physical dock edges. Bars run along the edge. Neon frames the icon, Aura backlights it, Target Lock adds corner brackets, Orbit adds an arc and satellites, Stardust adds colored stars, Power Badge adds a lightning badge, and Glitch adds offset silhouettes and pixel strips. Icon decorations stay upright and inside the icon square. All effects are static, with no timers or continuous animation. Reduce Transparency replaces blurred backlighting with solid artwork. Keyboard selection and launch progress render above these decorations. Hidden preserves the reserved indicator strip, icon positions, and hit regions. Settings samples use the same marker view, with alternating running and inactive sample apps. New copy and search terms are in the string catalog.

The former `isSelected` button flag is now `isKeyboardSelected`. It marks navigation after choosing **Focus Dock**, not the foreground application or hover. Keyboard selection keeps its accent outline with every running-indicator style. The old selection bar no longer replaces the running marker, so selection and running state remain separate. Running-state accessibility text is unaffected by hiding the visual marker.

Validation used the focused Debug app build:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-indicators-build build
```

Result: **BUILD SUCCEEDED**, recorded in `/tmp/DeeDock-indicators-expanded-build.log`. The initial sandboxed attempt could not load Swift macro plugins; the successful build ran outside that sandbox. The only warning reported skipped App Intents metadata extraction because there is no AppIntents dependency. The string catalog parses and the diff passes whitespace checks.

No tests were executed, app launched, or automated visual checks performed. Inert gallery previews cover all fifteen styles, including side placement, dark appearance, and an explicit reduced-transparency variant. Existing button previews cover keyboard selection and launch progress. Hands-on acceptance remains pending for light and dark appearance, magnification, reduced transparency, Focus Dock navigation, display overrides and reset, persistence after restart, and mixed-edge monitors. Background visibility and idle fading remain outside this change.


### Four Metal indicator styles

Plasma, Hologram, Solar Flare, and Prism fill the four remaining cells at a five-column gallery width. The gallery remains adaptive at other widths. Each style uses a stitchable Metal color function on an icon-sized rectangle, with transparent space in the center and premultiplied alpha. Plasma draws electric filaments, Hologram draws a diffraction rim and scan lines, Solar Flare draws a rayed corona, and Prism draws a spectral octagonal bevel.

The shader functions use arithmetic without texture reads, layer sampling, particle simulation, timers, or a continuous animation loop. They redraw through the existing SwiftUI rendering lifecycle. Reduce Transparency changes translucent light to solid bands. All four remain static under Reduce Motion. These are implementation constraints, not measured GPU or battery results. Artwork stays inside the icon bounds and beneath keyboard focus and launch progress.

The bridge uses Apple's [SwiftUI colorEffect shader API](https://developer.apple.com/documentation/swiftui/view/coloreffect(_:isenabled:)), checked against the installed macOS SDK. The synchronized Xcode source group includes the Metal file without manual project edits. No frameworks, dependencies, deployment changes, or signing changes were added.

The focused Debug app build succeeded. `/tmp/DeeDock-indicators-metal-build.log` records both `CompileMetalFile` and `MetalLink`; the output app contains `Contents/Resources/default.metallib`. The only warning was the existing skipped App Intents metadata extraction. The string catalog parses and the diff passes whitespace checks. New inert previews show all four shaders on application icons at 32, 64, and 96 points; the gallery also has dark and reduced-transparency previews.

No tests, live visual checks, or GPU profiling were run. Remaining acceptance includes runtime shader resolution, visual contrast on real icons, all dock edges, magnification, hidden/revealed docks, focus and launch overlays, reduced transparency, display scaling, and GPU cost with multiple running apps across displays.


## Background controls and idle fading

Added on 2026-09-03 after the running-indicator work. Appearance now provides Show background, Background opacity, Fade when idle, Fade target, Idle opacity, Idle delay, Fade-out duration, and Restore duration. Every control supports independent display inheritance and reset. Background opacity snaps to 10% steps and idle opacity to 5% steps; idle delay snaps to 1-second steps and defaults to 3 seconds. Duration controls use 0.05-second steps. Existing saved settings receive the new defaults only when their keys are absent; malformed shared values and unknown targets retain the existing load-error handling. Explicit false and zero overrides remain distinct from inheritance.

Background visibility affects material, border, shadow, and separator without changing geometry. Idle fading can target all artwork, only the background, or only icons and running indicators. Opacity multiplies normal appearance. Labels, keyboard outlines, launch progress, and error feedback remain at full opacity. Native hit regions and accessibility availability do not depend on idle opacity, including at zero.

Each panel owns a cancellable idle deadline through the existing monotonic scheduler. Repeated pointer updates preserve the deadline. A fresh pointer sample and generation check precede fading. Pointer interaction, menus, dragging, keyboard focus, accessibility focus, and errors restore the dock. Only fully revealed docks schedule idle work; auto-hide transitions restore the idle multiplier immediately. Sleep suspends idle timing, display and Space refreshes reset it, and panel teardown cancels callbacks. Opacity animations have their own scope so magnification springs cannot override fade timing. There is no idle polling or continuous animation loop.

Reduce Motion makes restoration immediate and caps fade-out at 0.1 seconds. Reduce Transparency suppresses idle fading and makes an enabled background opaque. Both preserve stored preferences. Settings contains Normal and Idle samples plus cancellable playback using the configured delay and durations. Inert previews cover floating icons at zero opacity, side placement with background-only fading, dark appearance, reduced accessibility settings, and display overrides. Preview accessibility values are injected because the SDK environment properties are read-only.

### Validation

The focused Debug app build succeeded with the existing project and scheme:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-idle-build build
```

Result: **BUILD SUCCEEDED**, recorded in `/tmp/DeeDock-idle-build.log`. The initial sandboxed attempt could not access the installed Metal toolchain; the successful build ran outside the sandbox. The final build reported only skipped App Intents metadata extraction because there is no AppIntents dependency. The string catalog parses and the diff passes whitespace checks. No dependencies, entitlements, signing settings, language mode, deployment target, or system Dock preferences changed.

After the final default and step adjustments, the feature-only snapshot also passed the focused Debug app build. It used `/tmp/DeeDock-fade-delivery` as its source and `/tmp/DeeDock-fade-delivery-build` for derived data; `/tmp/DeeDock-fade-delivery-build.log` records **BUILD SUCCEEDED**. This confirms compilation without the separate uncommitted indicator and layout work.

No tests were authored or executed for this feature. No app was launched, previews rendered, or automated visual checks performed. Compilation does not establish native appearance or interaction acceptance.

Remaining hands-on acceptance:

- Check background off, zero opacity, and partial opacity on light and dark desktops, on all four edges and at different display scales. Confirm the glass shadow and separator disappear together and geometry stays stable.
- Check each fade target, percentage composition, every slider's steps and typed input, shared defaults, individual overrides, resets, and saved values after restart.
- Exercise zero and maximum delays and durations, pointer restoration at zero opacity, entering during a fade, rapid leave/re-enter, native context menus, mouse holds, dragging, keyboard focus, VoiceOver, and error dismissal. Confirm the first click still activates its app and hover does not steal focus.
- Combine fading with auto-hide and each reveal animation. Verify fresh full-opacity reveals, no stale deadlines after settings changes, independent displays, unplug/reconnect, sleep/wake, Spaces, full-screen apps, and quitting during a delay.
- Toggle Reduce Motion and Reduce Transparency while fading and during preview playback. Verify immediate restoration, opaque enabled backgrounds, hidden backgrounds staying hidden, preserved preferences, and preview cancellation on Settings navigation or closure.

The pre-existing running-indicator and layout edits remain in the working tree. The background and idle-fading feature is ready for delivery.


## Preserve native glass outside idle fading

On 2026-09-03, the user reported that lowering Background opacity made the dock lose its glass appearance. Source inspection confirmed that the setting applied alpha to the entire rendered glass effect. Apple's [public Glass configuration](https://developer.apple.com/documentation/swiftui/glass) and the installed SDK expose variants, tint, and interaction, but no independent material-opacity control. The reported visual degradation is consistent with whole-effect alpha; it was not reproduced in a live UI session here.

Removed the steady Background opacity slider. Enabled backgrounds now use native glass at full strength, regardless of the legacy stored opacity. The old value and display override remain encoded for compatibility; no preferences are rewritten. Show background still enables floating icons, and Reduce Transparency still selects an opaque native background. The live dock and Settings samples use the same calculation.

DockBackgroundView now bypasses the opacity modifier at full visibility and draws no material at zero. Its animatable opacity interpolates between those branches during intentional idle fading. Partial idle fading still reduces the rendered glass effect; selecting Icons and indicators only keeps the glass intact while dimming icons. This change does not claim independently adjustable glass transparency.

Validation: the focused Debug app build uses the existing DeeDock scheme and `/tmp/DeeDock-idle-build` derived data. Result: **BUILD SUCCEEDED**, recorded in `/tmp/DeeDock-glass-opacity-build.log`. The only warning was skipped App Intents metadata extraction. No tests, app launch, or automated visual checks were performed. Runtime acceptance remains required for native backdrop sampling after restoration, partial idle fading and reversal, saved legacy opacity values, background on/off, both accessibility settings, and Settings samples. Existing unrelated work remains intact.

## Per-dock app visibility and tooltip presets

Added on 2026-09-03. Behavior now provides five mutually exclusive visibility choices. One enum represents Show all, Hide running apps, Collapse running apps, Hide pinned apps, or Collapse pinned apps. Pinned apps retain their group while running. The catalog and saved pin lists remain complete.

Collapsed groups have a count-bearing section button, including when empty. Expansion is local to the panel session and resets on an effective visibility-policy change or panel recreation. App events, auto-hide, and geometry refreshes preserve it. Typed entry identities distinguish applications from section actions. Rendering, keyboard selection, hit regions, accessibility, and insertion geometry consume the same projected entries. Removed entries cannot re-register stale hit rectangles during an exit animation.

A valid drag dwelling on the pinned-group button for 0.5 seconds temporarily expands its pins. Completion or cancellation restores the prior state. Button drops append; expanded insertion positions map back to saved pin indices without counting the control. Completely hidden pins reject direct drops, while existing menu commands remain available. Native panel resizing and entry changes use a 0.18-second transition, with immediate changes under Reduce Motion.

Appearance includes eighteen bundled app-name presets plus Off. Each choice includes design, placement, hover delay, and entrance. The gallery and inert preview use the production renderer. Placements adapt to all four edges; labels are upright, width-limited, and clamped to the viewport. Before/after placements try the opposite direction before centering. Dock captions use the resting visible dock and a stable inward anchor independent of the hovered icon's magnification.

Each panel owns cancellable tooltip timing through the existing monotonic scheduler. Target changes, menus, dragging, hiding, error feedback, sleep, and teardown invalidate pending work. Keyboard labels bypass delays. Tooltips do not capture input, extend activation retention, or resize the panel when shown. Reduce Motion limits entrances to short fades; Reduce Transparency replaces material with opaque backgrounds. Settings playback also observes actual window closure because the Settings scene can retain its SwiftUI tree.

Both settings support shared defaults, explicit per-display overrides, remembered displays, individual resets, and existing reset-all behavior. Missing legacy keys use Show all and Classic. Explicit Show all and Off remain distinct from absent overrides. Unknown enum values retain existing load-error handling. All new app-owned copy uses generated string-catalog symbols and translator comments.

### Validation

The focused Debug app build and test-target compilation succeeded. Test sources were compiled with `build-for-testing`; **no test cases were executed**. Commands:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-sections-build build

xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-sections-build build-for-testing
```

Logs are `/tmp/DeeDock-sections-build.log` and `/tmp/DeeDock-sections-test-build.log`. The sandboxed attempt could not access the installed Metal toolchain. Builds outside that sandbox succeeded. The only remaining warning was skipped App Intents metadata extraction because the target has no AppIntents dependency.

Authored regression cases cover visibility membership, running and unavailable pins, empty groups, independent expansion, selection repair, stale hit-region rejection, drag dwell and cancellation, insertion mapping on all four edges, legacy settings, explicit overrides, remembered-display persistence, resets preserving pins, tooltip timing, keyboard labels, Off, placement fallback, and activation retention. New source dependencies are registered with the existing test target. The string catalog parses and the diff passes whitespace checks.

Inert previews cover the gallery, collapsed sections on every edge, expanded running apps, zero pins, long names, overflow, dark appearance, and reduced motion/transparency. No app was launched, no preview was rendered, and no automated visual checks were performed. Compilation does not establish passing assertions or native interaction quality.

### Remaining hands-on acceptance

- Exercise all visibility modes, empty groups, live launches/quits, pinning/unpinning, count updates, expansion, resizing, and overflow. Confirm focus and app order survive changes.
- Use pointer, Focus Dock, Return/Space, and VoiceOver with section buttons. Confirm hidden apps cannot receive clicks, keyboard selection, or accessibility focus.
- Drag from Finder and another dock onto collapsed pins, wait for expansion, insert at each boundary, cancel, and drop onto the button. Verify temporary expansion restores and hidden pins reject drops without unpinning the source.
- Inspect every tooltip preset against light and dark desktops, with long names, all four edges, magnification, scrolling, mixed scale factors, and negative display origins. Confirm dock-centered labels stay fixed and tooltip regions never capture clicks or extend hiding delays.
- Check rapid hover changes, pointer exit, menu tracking, errors, Reduce Motion/Transparency, and Settings preview cancellation on window close or navigation.
- Combine sections and tooltips with all auto-hide styles and idle fading. Check separate display overrides, disabled docks, restart/reconnect, Spaces, full-screen apps, and sleep/wake.

Existing uncommitted work is preserved. No signing, dependency, entitlement, language-mode, deployment-target, or system Dock preference changes were made. No files were staged or committed.

## Open files from DeeDock

Added on 2026-09-03. Available application icons accept existing files, document packages, and folders in either section. Validation checks the complete batch, preserves order and granted URLs, and removes duplicates. Application bundles still use pin import; mixed application and document batches are rejected. Web URLs, pasted content, and file promises are outside this slice. The receiving application decides which document types it supports.

The native drag coordinator owns payload validation and routes document targets through clipped icon geometry and the existing animation coordinate conversion. Metadata work runs outside pointer callbacks. Checking and rejected batches cannot be dropped. Document feedback uses an accent outline and localized target text without pin-insertion gaps. Either collapsed section temporarily expands after a 0.5-second document hover and restores its previous state when dragging ends. Completely hidden sections remain hidden.

Spring-loading uses the AppKit destination protocol and system hover and Force Click preferences. Activation requests contain no documents. Actual drops and confirmed picker selections create independent catalog requests, including repeated batches while an app is launching. Temporary security-scope access remains owned through validation and handoff. Display removal invalidates its UI callbacks without discarding an accepted request; shutdown cancels owned tasks. Submitted OS operations cannot be rolled back, and a successful handoff does not establish that every document appeared in the receiving app.

Open Files… is available through app context menus, VoiceOver actions, and Command-O in Focus Dock. One app-owned native picker captures its original target, accepts multiple files and folders, and treats packages as items. Repeated commands bring that picker forward. The initiating dock remains visible until dismissal; removing it cancels the picker. Cancellation restores the originating dock selection or external application only while DeeDock still owns foreground focus. No document bookmarks, history, or preferences are stored.

### Validation status

The narrow Debug app build succeeded using the DeeDock scheme and `/tmp/DeeDock-documents-build` derived data. The log is `/tmp/DeeDock-documents-build.log`. The successful build required access to the installed Metal toolchain outside the sandbox and reported the existing skipped App Intents metadata extraction warning. Test sources also compiled with `build-for-testing` before the user authorized test execution.

Authored Swift Testing cases cover classification with temporary fixtures, mixed and invalid batches, order and duplicates, metadata refresh, balanced resource ownership, clipped targets on all four edges, non-destructive operation selection, temporary section expansion, spring target changes, activation without document delivery, repeated requests, stale callbacks, shutdown, display removal, and picker target capture and cancellation. Existing pinning and unpinning cases remain in the test target. These cases passed in the full test run recorded below. Inert previews cover checking, valid targets, rejection, long app names, and reduced transparency.

During hands-on use, the user reported that dwelling with a Finder file over ChatGPT failed to foreground the app. The console warned that AppKit attempted to make a non-key dock panel key, once per dock entry. Moving to another icon during the same drag also failed to activate it. Debugger breakpoint counts confirmed calls to the panel's key-window method and zero calls to the hosting subclass's spring entry or activation methods. Runtime inspection found that NSHostingView's own spring-loading eligibility was false despite the subclass's protocol implementation.

The native destination now uses a plain NSView containing the SwiftUI hosting view. Both drag and spring-loading callbacks belong to that outer view; ordinary input and accessibility remain with the child. No private APIs were added to the application. Subsequent breakpoint counts confirmed native spring entry and activation. Direct NSRunningApplication activation still failed to foreground the target in the user's check, so spring activation now uses NSWorkspace.openApplication for running and closed apps. The user confirmed that foreground activation works through this path while holding the file drag.

Xcode's RunProject tool rebuilt and launched that version successfully with no build errors. Its log is `/var/folders/q5/16skxm0d1rlgnyf53r13c1rm0000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20260903-162733.txt`. App and test-source compilation then succeeded through BuildProject with buildForTesting enabled; its log is `/var/folders/q5/16skxm0d1rlgnyf53r13c1rm0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260903-162848.txt`. That check compiled tests without executing them. No automated visual tests ran.

Escape cancellation has an observed platform limitation on the development Mac. In the user's hands-on check after spring activation, both the file attached to the pointer and the dock outline remained after Escape. A follow-up confirmed that Escape cancels before activation, but does not cancel after activation even when the pointer leaves DeeDock. The local Escape handler received no hits; native exit and end callbacks did arrive. The user then reproduced the cancellation failure by dragging from Finder and switching apps with Command-Tab without using DeeDock. This establishes that the failure also occurs independently of DeeDock; it does not establish behavior on other macOS versions or machines. Foreground activation and cancellation before activation are confirmed for these checks. Escape after an app switch remains a documented limitation, and the remaining acceptance scenarios are still outstanding. Temporary agent-added debugger breakpoints have been removed.

On the user's subsequent request to run tests, Xcode RunAllTests initially reported 199 passing and two failing tests. Both failures were stale assertions in existing tests: the importer fixture compared equivalent directory URLs with different formatting, and the activation-envelope test expected transparent viewport padding to belong to the glass activation zone. After correcting those assertions, the complete DeeDock suite passed: **201 passed, 0 failed, 0 skipped**. No production behavior changed for those corrections. The result bundle is `/var/folders/q5/16skxm0d1rlgnyf53r13c1rm0000gn/T/ActionArtifacts/default/RunAllTests/Test-DeeDock-2026.09.03_16-37-07-+0200.xcresult`. Passing model and lifecycle tests do not establish the remaining native interactions below.

### Remaining hands-on acceptance

- Drop a Finder document, multiple documents, a document package, and a project folder onto running and closed apps. Verify the documents actually appear separately from successful OS handoff. Try duplicate URLs, missing files, mixed app/document selections, and unsupported receiver types.
- Keep holding the drag over an icon, activate through native dwell or Force Click, and continue into the app's window. Move rapidly between icons, leave and re-enter, press Escape, and confirm hovering alone sends no documents.
- Exercise overflow scrolling, all four edges, gaps, clipped icons, unavailable apps, auto-hide activation, both collapsed sections, and completely hidden sections. Confirm document feedback has no pin-insertion gap and temporary expansion restores.
- Use context menus, Command-O, and VoiceOver. Confirm picker cancellation, captured targets, repeated commands, app-list changes, focus restoration, and inaccessible targets. Check Reduce Motion and Reduce Transparency.
- Repeat on multiple displays and Spaces, remove the initiating display during a picker and accepted request, and exercise sleep/wake. Confirm ordinary application activation preserves the ongoing external drag. Recheck application-bundle pinning, internal reorder, and dragging out to unpin.

The pre-existing panel-controller retention change and Xcode recovered-reference group edits remain outside this feature commit.

## Launch at login

General is an app-wide Settings pane above Shared Defaults. Appearance remains the initial selection; localized search terms include login, startup, and automatic launch. General has no display overrides or Restore Defaults action and remains independent of configuration storage errors.

The toggle reads `SMAppService.mainApp.status`. Only enabled registration turns it on. Pending approval keeps it off and disabled, with Open System Settings… and Cancel Request. Missing or unknown status provides Refresh and the System Settings link. Registration controls are disabled during a request, and both successful and failed operations reread macOS status. Errors appear inline without automatic retries or opening System Settings.

The application delegate owns the injectable controller. Settings appearance and the existing window-activity bridge refresh status without polling. Closing Settings does not cancel accepted requests; shutdown cancels owned work and suppresses late callbacks. Already-submitted system operations cannot be rolled back. Normal startup still restores docks and the menu-bar item without explicitly opening Settings or taking foreground focus. No helper, launch-agent plist, or mirrored preference was added.

### Validation status

The narrow DeeDock Debug build was attempted through Xcode MCP. It identified missing generated-string argument labels and unsupported preview environment overrides; both were corrected. The next build was cancelled by an interaction in Xcode. No successful build of the final source state is recorded. The user then requested committing and pushing the current work without further validation.

Swift Testing cases were authored for status mapping, approval gating, registration, unregistration and approval cancellation, external changes, failure followed by status refresh, explicit retry, overlapping and repeated commands, and shutdown before submission or after submission with late success/failure. The service fixtures do not access real login-item registration. These new tests have not been compiled or executed. Inert previews cover all statuses, each pending operation, and long error text in a narrow dark presentation. Previews and automated visual checks were not run.

Static review checked the separate General navigation path, initial Appearance selection, localized search matching, storage-error independence, and window-activation refresh wiring. The string catalog parses and retains all prior entries. Native controls provide keyboard and accessibility semantics, while feedback uses opaque cards and static text; their hands-on behavior remains unverified.

### Remaining hands-on acceptance

- Use one consistently signed installed copy. Enable Launch at Login, inspect Login Items in System Settings, and verify the toggle is on only after approval. Disable it externally, return to DeeDock Settings, and verify the status refreshes.
- Where pending approval is available, cancel the request and verify it is withdrawn. Disable an enabled registration and verify DeeDock keeps running. Close Settings during unregistration and reopen it to inspect the final status.
- Search for login, startup, and automatic launch. Navigate between General, Shared Defaults, and displays. Verify General has no overrides or reset action and works with an unreadable dock configuration fixture.
- Check keyboard navigation, VoiceOver labels and feedback, long translated text, light/dark appearance, Reduce Motion, Reduce Transparency, and increased contrast.
- With user control of logout, verify automatic startup after signing out and back in. Confirm configured docks and the menu-bar item return without Settings opening or deliberate focus transfer. Disable registration and repeat. Quit DeeDock before each logout or otherwise exclude macOS session restoration so it cannot be mistaken for login-item startup.

No real registration changes, logout/login cycles, or machine-setting changes were performed during implementation. The existing panel retention change, recovered-reference group, and concurrent Xcode build-number change are retained in the requested clean-tree delivery.

## First-launch onboarding

Adds a seven-page tour shown once on first launch, reopenable from the menu-bar item and the app menu. Sources live in `DeeDock/Onboarding`, split into `Models`, `Persistence`, `State`, `Windowing`, and `Views`. `OnboardingStep` and `SystemDockReservation` stay free of SwiftUI so the unhosted test target does not need the settings view layer; step artwork lives in `Views/OnboardingStepPresentation.swift`.

The tour is presented after `coordinator.start()`, so the real docks exist behind it. `OnboardingRepository` stores `{ completedVersion }` under `onboarding.v1`. Reaching the end, opening Settings from the last page, and closing the window all record completion; reopening from a menu never rewrites the record. Unlike the settings repositories, an unreadable record is treated as already completed rather than surfaced as an error, so a stray byte cannot make the tour reappear on every launch. Reading never rewrites the stored bytes.

One page writes a setting, through the existing `DockSettingsStore.update`: placement sets `edge`. It does not touch per-display overrides and goes through the same validation and save path as Settings. Every other page changes nothing. The writing page carries a prompt line and pointer affordances and the others carry neither, which is the tour's only signal of which is which.

An interactive running-indicator gallery was built and then removed at the user's direction. Showing six apps each wearing a different marker asked a person to choose a global style by clicking an individual app, a mapping with no meaning, and it depicted a dock no screen can produce. The page is a demonstration again: one coherent dock cross-fading between styles.

Illustrations reuse production code rather than re-creating it: `DockGeometry`/`DockPlacement` for placement, `DockSampleView` for the magnification sweep and the indicator demonstration, `DockDisplayDiagram` for the display page, and `DockVisibilityController` with `DockAnimationGeometry` and `DockPresentationModifier` for the auto-hide page. `DockSampleView` gained an optional `pointerAlong`, which defaults to its previous behavior. The macOS Dock page is drawn separately because it depicts the system Dock, where reusing the DeeDock diagram would be misleading.

Each page runs at most one ambient task, started by `.task` and cancelled by SwiftUI when the page leaves, so a page a person has moved past animates nothing. `SystemDockMonitor` observes `NSApplication.didChangeScreenParametersNotification` and removes its observer when the view disappears and when the window controller stops; nothing polls.

### System Dock detection

`SystemDockReservation` compares each screen's `frame` and `visibleFrame` and reports the non-top edge whose inset exceeds one point. The top inset is excluded because the menu bar and notch always reserve it. This is a deliberate limitation, not a shortcut: an App Sandbox cannot read `com.apple.dock`, so the switch itself is unreadable, and `AGENTS.md` forbids writing it. The status is therefore worded as reserved space rather than as the state of a preference. Turning on automatic hiding releases the band and clears the status; moving the Dock to another edge does not, which is correct.

### API limitation

`SettingsWindowOpener` reaches the SwiftUI `Settings` scene through `NSApp.sendAction(Selector(("showSettingsWindow:")))`. `@Environment(\.openSettings)` is delivered only to views inside the `App` scene graph, and the tour is an AppKit-hosted window, so that action is unavailable to it. No public symbol exposes the selector. The call reports whether it was accepted and nothing depends on it: the menu-bar item and ⌘, remain the documented routes to Settings, and the tour's final page says so.

### Validation status

`xcodebuild build` and `build-for-testing` both succeeded for the Debug app and the unhosted `DeeDockTests` target, using the same commands recorded in the Compilation section. The suite was executed once at the user's implicit request during implementation and passed: 132 tests across 25 suites, including the two new suites. The user then asked that tests not be run again, and none were run after that point; later source changes to the placement and indicator pickers are compiled but not re-tested.

New tests cover reserved-edge detection for each edge, menu-bar-only insets, released space, sub-point rounding, negative screen origins, empty frames, and multi-display aggregation; and tour navigation ordering, clamping at both ends, skip applying only to the macOS Dock page, direction tracking, first-launch presentation, completion, an older completed version, unreadable data, and a value of the wrong type. Four onboarding sources were added to the Xcode **Test Model Sources** group and the test target's Sources phase.

Previews cover every page, both system-Dock states, the placement picker on all four edges, an indicator style outside the curated gallery, dark appearance, Reduce Motion, Reduce Transparency, and accessibility text sizes. Previews use scratch `UserDefaults` suites and a stub login service, so none of them registers a login item or writes the real completion record. Previews were not run.

Layout was inspected by the user at several points during implementation and corrected in response: the window height was reduced and its content made scrollable, the placement handles were moved outside the screen diagram after they were found to cover the dock, and the indicator gallery was first corrected — four of six options rendered as nothing because only `DockRunningIndicator` was applied and not `DockIconIndicator` — and then withdrawn in favor of a demonstration.

### Remaining hands-on acceptance

- Delete `onboarding.v1` and launch. Confirm the window is centered and focused, the docks are already visible behind it, and every page animates.
- Walk forward and back through all seven pages. Confirm the slide direction reverses, only the visible page animates, and closing part-way through does not re-present the tour on the next launch.
- On the macOS Dock page, confirm the status reads as reserving space, open Desktop & Dock from the button, turn on automatic hiding, and confirm the status clears without returning to DeeDock. Turn it off and confirm it returns. Confirm Skip works and that nothing in `com.apple.dock` changed.
- Click each placement handle and confirm the real docks move to that edge. Confirm a display with an existing edge override keeps its own value. Confirm no other page changes anything when clicked.
- Open Settings from the last page and confirm the tour closes and Settings opens. Reopen the tour from the menu-bar item and the app menu, and confirm a second window is never created.
- Enable Launch at Login from the last page and confirm the state matches Settings → General afterwards, including a pending approval.
- Exercise Reduce Motion, Reduce Transparency, increased contrast, and larger text sizes on every page. Confirm the login card's approval and error states scroll rather than clip.
- Use VoiceOver on the placement page: confirm the handles are reported as selectable buttons with the chosen one marked, that the illustrations elsewhere are silent, and that the page indicator reads its position.
- Run with several displays, including a display whose Dock reserves a side edge, and with all docks disabled.

## Icon-aware running indicators

Added on 2026-09-03, after the first-launch tour.

### What changed

The four Metal styles were procedural drawings on a white square that never read the icon underneath, so every application showed the same figure in the same colours. They are now layer effects: each shader samples the artwork it decorates.

A shared `iconEdge` helper walks four rings of twelve spokes around each output pixel and returns a signed distance to the artwork's alpha silhouette — negative on the artwork, positive in its transparent margin — together with the alpha-weighted colour of the artwork within reach. Every style shapes its light around that boundary, so the indicator follows the real outline of the icon rather than a rounded rectangle. The artwork is returned unmodified by the light-only styles, so icons stay crisp; a narrow rim just inside the edge keeps icons that fill their whole square from showing nothing.

Two additional inputs vary the result per application:

- `DockIndicatorVariant` derives a seed from FNV-1a over the application's stable identity. `Hashable` is deliberately not used because its per-process seed would reshuffle every launch. The seed selects lobe counts, spin direction and rate, facet counts, scan frequency, and phase.
- `DockIconAccent` rasterizes each icon once to a 16×16 bitmap and averages hue on the colour circle, weighted by alpha, squared saturation, and brightness. Icons whose hues disagree, or that are close to achromatic, return no accent and each style keeps its own palette instead of glowing white. Results are cached by identity, which is what makes the lookup safe to read from a view body.

Two existing styles were rebuilt and two new ones added. Glitch moved from offset silhouettes and static bars to a shader that cuts the icon into rows, slides a random subset of them sideways, separates the colour channels, and gates the whole thing behind a burst clock so the icon reads normally between faults. Stardust moved from three fixed sparkles to slots that each run a birth-to-death cycle, redrawing position, size and colour per generation. Lava Chrome melts the icon's own corners and edges: domain-warped noise displaces the artwork along its outward normal, weighted by distance from centre so corners go first and the middle is never touched, with a downward bias that turns overhangs into drips. Singularity puts an inclined orbiting black hole around the icon, lensing the artwork toward it with a radial and a tangential term, tearing a void where the event horizon passes, and lighting a photon ring and a Doppler-beamed accretion disk in the colours of the artwork falling in.

Neon and Aura were withdrawn.

### Persistence

`animateIndicators` was added to `DockSettings` and to the inheritable display-override fields, defaulting to on. Saved documents without the key decode to on.

Withdrawn style values no longer fail the whole settings document. `RunningIndicatorStyle` decodes `neon` as Plasma and `aura` as Solar Flare; genuinely unknown values still throw through the existing settings error handling, as before. This is a deliberate narrowing of the rule recorded in the *Running indicator styles* section above.

### Motion

Animated styles run on a `TimelineView` at 30 Hz. Motion stops when the preference is off, when Reduce Motion is on, while a panel is hidden (`DockInteraction.exposesContent`, kept in step with the visibility controller), and once a dock has faded out on idle. A hidden dock therefore schedules no frames.

Elapsed time is wrapped to a 60-second period before it reaches a shader, because a 32-bit float cannot hold an absolute timestamp at animation precision. Every time-dependent term is an integer harmonic of that period, and the noise fields are sampled along wide circular orbits rather than translated, so the wrap is seamless rather than a jump once a minute. Angular multipliers are whole numbers for the same reason, so nothing seams at ±π.

`maxSampleOffset` is 0.24× the icon dimension while the shaders sample at 0.16×. Glitch stacks a row slip and a channel split on top of the silhouette reach, and Singularity's deflection reaches further than its sampling; one shared value would have widened every other style's glow band.

### Compilation

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock -configuration Debug build
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock -configuration Debug build-for-testing
```

Both reported **BUILD SUCCEEDED** and **TEST BUILD SUCCEEDED**. The Metal file compiles and links into `default.metallib` with no diagnostics. The only warning reported skipped App Intents metadata extraction, as before. The string catalog parses.

### Validation status

No tests were run, no app was launched, and no automated visual checks were performed, per the project's test policy. One test was added covering the withdrawn-style migration, a full settings document carrying a withdrawn value, and the rejection of an unknown value; it is compiled but not executed.

Previews cover every shader style across six differently coloured sample icons, three icon dimensions, the still variant, and an explicit reduced-transparency variant, plus six sparkle repertoires. Previews were not run. Sample tiles in the Settings demonstration gained a proportional transparent margin, because real application artwork carries one and without it the shader styles have nowhere to put their light.

The shader cost is an implementation constraint, not a measured result: the silhouette pass is 48 texture samples per output pixel, Lava Chrome adds three fbm evaluations, and Singularity adds none. No GPU or battery measurement was taken.

### Remaining hands-on acceptance

- Confirm each shader style visibly differs between adjacent running applications, and that the same application keeps its figure across a relaunch of DeeDock.
- Confirm icons stay recognizable under Lava Chrome, Singularity, and Glitch at 32, 48, and 96 points, and while magnified.
- Confirm greyscale icons (System Settings, Xcode) fall back to each style's own palette rather than glowing white, and that strongly coloured icons take their own hue.
- Confirm motion stops when a dock auto-hides and when it fades out on idle, and that it never restarts while hidden.
- Confirm Reduce Motion holds a single frame for every animated style, and that Glitch still reads as broken rather than merely offset when still.
- Confirm Reduce Transparency replaces graduated light with solid bands on all seven shader styles.
- Confirm a saved `neon` or `aura` preference, in shared defaults and in a display override, loads as Plasma and Solar Flare and does not surface a settings error.
- Confirm the Animate indicators toggle is disabled for the styles that have no motion, and that it overrides independently per display.
- Watch one animated dock for longer than a minute and confirm no jump at the cycle wrap.
- Confirm indicator artwork stays inside its own icon square with item spacing at zero.

## Folder stacks

Implemented on 2026-09-03 after the running-indicator work was committed on the existing `codex/onboarding-tour` branch. No branch switch, merge, staging, commit, or push was performed for this feature.

### Behavior and implementation

- Per-display pin storage is now an ordered `DockPin` list containing applications and folders. A missing `dock.pins.v3.<displayID>` key migrates the corresponding application-only list once, while v1 and v2 bytes remain unchanged. Unknown or corrupt v3 bytes block edits and remain available for recovery.
- Folder identity is a persistent UUID plus resolved standardized URL. Reimporting the same location moves the established pin and retains its bookmark, UUID, and presentation. New displays copy the primary display's complete typed list once; later edits and Grid/List changes are independent.
- Finder classification runs outside pointer callbacks. Insertion boundaries accept ordered all-pinnable batches of applications and ordinary non-package folders. Direct application targets continue to accept document-only batches, including folders. A folder drag chooses one presentation owner per pointer update: document feedback directly over an application, otherwise pin-insertion feedback. Insertion hit-testing stays in the pre-preview resting frame so a gap cannot resize the panel and invalidate itself; duplicate geometry callbacks are ignored. Packages, aliases, plain files, unreadable items, and mixed pinnable/non-pinnable selections reject pin insertion as a complete operation.
- One app-wide coordinator owns a transient nonactivating panel. Clicking its source folder toggles it closed without the outside-click monitor reopening it. The panel anchors inward on all four edges, clamps to the display's visible frame with a 16-point margin, and points back to the source icon with a two-point visual join. It uses a 560×420-point ideal size and 280×220-point minimum, and reanchors after display geometry changes.
- The open panel holds every dock revealed and suppresses idle fading, tooltips, hover, and magnification. A click on any dock closes the stack and consumes that click, so the application or folder underneath does not receive an action. The panel fades and slides from its source edge when opening and closing, while Reduce Motion makes both transitions immediate. Outside click, Escape, a second source click, successful open or drag, replacement, source hiding/removal, display removal, sleep, and shutdown close it. Folder resolution and scoped access are renewed for each opening; stale bookmarks are refreshed in the source display's pin.
- Immediate non-hidden children load away from the main actor and return immutable snapshots. Files, packages, and aliases are leaves; ordinary subfolders reveal in Finder. One scoped directory event source runs only while the panel is open, debounces bursts, and stale loads cannot update a replacement session.
- Grid uses adaptive columns, 48-point icons, and two-line labels. List uses 24-point icons and one-line labels. Loading, empty, unavailable, and retryable error states are present. Reduce Transparency selects an opaque native background; the stack introduces no required motion.
- Folder icons and their stack cues use the same idle artwork opacity and animation as application icons.
- One child can be opened or dragged at a time. Native drag sources export a file URL with copy and move operations while the panel retains its security-scoped folder lease through the AppKit session. DeeDock does not mutate the filesystem.
- Focus Dock transfers explicit keyboard focus into a stack. Arrow keys navigate, Return opens, Escape returns to the source pin, and Tab reaches Grid/List. Folder menus and VoiceOver actions cover opening, Finder reveal, presentation, movement, copying to another display, and unpinning. New app-owned copy is in the string catalog with translator comments.

### Compilation and authored coverage

The focused Debug app build and the test-target compilation used:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -derivedDataPath /tmp/DeeDock-folder-stacks-derived \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -derivedDataPath /tmp/DeeDock-folder-stacks-derived \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

Both succeeded. Xcode reported the existing skipped App Intents metadata warning and its existing test-target dependency-scan warning. The latter does not prevent test compilation.

Authored Swift Testing coverage includes v2-to-v3 migration without legacy-byte mutation, unknown v3 tags and byte preservation, folder identity/deduplication with established metadata, presentation round trips and failed-save rollback, mixed Finder pin ordering, folder document-versus-pin routing, package and symbolic-link rejection, scoped-access release, hidden-child filtering, localized numeric sorting, packages as leaves, and four-edge panel clamping with a negative display origin. Existing profile, pin-editing, insertion, cross-display, document-payload, and selection tests were adapted to typed pins.

Deterministic previews cover Grid and List, populated, loading, empty, unavailable, recoverable error, long-name, dark, and opaque-background states. They were compiled but not rendered.

**No tests were executed. The app was not launched. No previews were rendered, and no automated visual checks or hands-on acceptance were performed.**

### Required hands-on acceptance

- Import mixed folders and apps, restart, reorder, copy between displays, drag out to unpin, and verify Grid/List independence. Exercise a moved, renamed, deleted, unreadable, and stale-bookmark folder.
- Open regular files, packages, aliases, and subfolders. Verify successful opens close the panel; failed opens remain visible and Retry works.
- Drag children to Finder and applications with copy, move, modifier changes, rejection, and cancellation. Confirm DeeDock itself never changes the filesystem and that access ends after AppKit completes the session.
- Change directory contents while the stack is open and closed. Verify live updates, event-burst settling, no stale result after replacement, and no idle watcher when closed.
- Check all four dock edges, negative origins, visible-frame clamping, small displays, overflow, collapsed and hidden pins, auto-hide, multiple displays, display removal, Spaces, full-screen apps, and sleep/wake.
- Exercise pointer focus passthrough, Focus Dock keyboard transfer and return, Tab routing, VoiceOver labels/actions/counts, long names, dark appearance, Reduce Motion, and Reduce Transparency.

Fan and Automatic modes, recursive navigation, search, Quick Look, multi-selection, file promises, two-way folder drops, and persistent utility windows remain planned.

## Trash

Implemented on 2026-09-04 on `main`. The existing uncommitted project-file change for `FoundationModels.framework` and a concurrent `DockAppButton.swift` edit were preserved. No branch switch, staging, commit, or push was performed.

### Behavior and boundaries

- One app-wide controller supplies the same Finder-owned Trash snapshot to every display. AppKit's named empty/full Trash artwork remains the fallback if inspection is unavailable.
- Trash is a trailing utility entry after its own divider. The pinned/running divider remains independent, including with hidden and collapsed sections. Geometry counts utility entries explicitly, so horizontal and vertical docks share the same spacing model.
- **Show Trash** and **Confirm before emptying Trash** default on under Behavior. Both participate in the shared-default and nullable per-display override system, including inherited-state UI and backward-compatible decoding of settings saved before either field existed.
- Click, Focus Dock Return, the context menu, and VoiceOver open Trash in Finder. The context menu also opens DeeDock Settings. Keyboard selection repair treats Trash as its own stable identity instead of assigning it to an application section.
- An external Finder batch can target only the exact Trash tile. Feedback uses the delete cursor, a tile outline, and **Move to Trash**. DeeDock retains the batch's temporary security-scoped access through `NSWorkspace.recycle`; success refreshes shared state and a partial or failed operation reports an error on the initiating dock. Internal pin drags cannot target Trash.
- User-selected file access is read/write because recycling changes the location of explicitly dropped items. Persistent app and folder pins continue to create read-only security-scoped bookmarks. DeeDock receives no general home-folder or Accessibility permission.
- Open and Empty use Finder's Trash scripting commands through a user-approved Automation grant. The sandbox restricts scripting to Finder's `com.apple.finder.trash` access group and includes a Finder-only temporary Apple-event exception needed by the open/count compatibility path. DeeDock does not automate Finder UI or use private APIs.
- **Empty Trash…** appears in the context menu and as a VoiceOver action only when Finder reports that Trash is full. When the initiating display's confirmation setting is on, a native warning requires explicit destructive confirmation. When it is off, the command goes directly to Finder. Finder then empties the home and mounted-volume Trash locations it owns.
- Finder exposes no public Trash-change notification. After Automation access has been granted, a two-second serialized item-count read keeps the shared state synchronized with Finder and system-Dock operations. Activation and action-result reads provide faster updates around direct interaction. No background query asks for permission.

### Compilation evidence

The string catalog parsed with `jq empty`, the Xcode project parsed with `plutil -lint`, and a feature-scoped `git diff --check` reported no whitespace errors. The focused unsigned Debug app build used:

```sh
xcodebuild -quiet -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -derivedDataPath /tmp/deedock-trash-derived-data \
  CODE_SIGNING_ALLOWED=NO EXCLUDED_SOURCE_FILE_NAMES=RunningIndicatorShaders.metal \
  ENABLE_DEBUG_DYLIB=NO build
```

It completed successfully after the Finder-routing correction. The Metal source was excluded because this command environment lacks the optional Metal toolchain; this proves Swift and project compilation, not shader compilation or native interaction quality.

A subsequent signed Debug build in `/tmp/deedock-trash-automation-derived` completed successfully after the Finder Automation and synchronization changes. `codesign -d --entitlements` confirmed that the built app contains App Sandbox, read/write user-selected files, app-scoped bookmarks, the normal Debug `get-task-allow`, Finder Automation, the Finder Trash scripting access group, and the Finder-only temporary Apple-event exception. The generated Info.plist contains the Automation usage description.

A user checkpoint of the first draft found that opening `~/.Trash` as an ordinary URL produced a sandbox permission alert and its unknown-state icon fell back to generic folder artwork. AppKit's named Trash artwork fixed the icon. A second checkpoint showed that direct Finder routing still failed. Runtime diagnostics then proved that macOS privacy protection denied direct `~/.Trash` access even when the signed app carried a Trash-only home-relative sandbox exception. The implementation therefore removed direct filesystem access and delegates open, count, and empty operations to Finder.

The signed sandboxed build was launched and exercised with native UI automation after granting its one-time Finder Automation request. Clicking DeeDock opened Finder's **Papierkorb** window. DeeDock's context action showed its destructive confirmation, emptied two existing items after explicit approval, and immediately changed its accessibility value to **Empty**. A separate disposable Desktop file was moved to Trash through Finder; DeeDock changed to **Contains items** within the monitoring interval. Emptying that one disposable item outside DeeDock changed DeeDock back to **Empty** on the next interval. Apple's Dock process did not expose an automation surface, so the final external mutation was initiated in Finder; both entry points use Finder's Trash operation, but the system-Dock menu itself was not clicked by the tool.

The confirmation preference was then added and checked in a signed Debug build. Defaults showed the new toggle on. A connected display showed it as **Following default**, switching it off created only that display's **Customized** override, and **Use Default** restored inheritance. With the override off, DeeDock emptied one disposable test item without presenting its alert and returned the Trash state to **Empty**. Verification restored the display to the enabled shared default.

**No test suite or preview was run. The focused signed Debug target built successfully, and the Trash open, DeeDock empty, Finder fill, external empty, and artwork/accessibility-state transitions above were exercised in the running app.**

### Required hands-on acceptance

- Verify the trailing divider and hit region on all four edges with pinned-only, running-only, collapsed, hidden, empty-app, crowded, magnified, scrolled, and auto-hidden docks.
- Exercise shared-default and per-display Trash visibility, inheritance restoration, disconnected-display persistence, and settings saved before the new field existed.
- Open Trash by click, context menu, Focus Dock, and VoiceOver. Confirm focus passthrough, selection repair, menu visibility holds, accessible empty/full/unknown values, and unavailable behavior.
- From Finder, drop one item and ordered mixed batches of files, folders, and packages. Exercise success, cancellation, partial failure, inaccessible input, consecutive drops, display removal during completion, and a drop while Trash is already changing.
- Use a consistently signed sandboxed build to verify dropped-item access and Automation revocation/regrant behavior. Confirm rejected and cancelled recycle operations do not move items and DeeDock cannot read protected home-relative paths directly.
- Empty from the system Dock itself. Verify cancellation, Finder failures, hidden Trash items, repeated fill/empty cycles, mounted-volume Trash, sleep/wake, and the monitoring cost over an extended run.
- Confirm Reduce Motion, Reduce Transparency, idle fading, tooltip behavior, dark appearance, different backing scales, negative display origins, Spaces, and full-screen apps do not regress the tile.

## Window-aware application menus

Implemented on 2026-09-03. App Sandbox, signing settings, and entitlements were left unchanged.

### Behavior and boundaries

- Application context menus open synchronously and retain the existing nonactivating-panel tracking hold. When Accessibility access is enabled, the window section starts with a disabled loading row and updates only while that exact menu remains tracked.
- A main-actor menu controller owns session generations, discovery and action tasks, cancellation, and per-dock error delivery. Window discovery does not enter the application catalog's launch-progress state.
- One dock icon resolves every matching regular process from its bundle identifier or standardized bundle URL. Hide, Show, Bring All to Front, and cooperative Quit attempt every match and report rejection as an action error.
- A dedicated actor serializes public Accessibility calls with a 250 ms cross-process messaging timeout. Native `AXUIElement` handles stay private to that actor; views receive immutable snapshots and opaque menu-scoped tokens.
- Discovery retains Accessibility order, includes top-level windows and dialogs, excludes floating utility windows, marks main and minimized states, preserves runtime titles, and gives blank titles a localized fallback. Selecting a row invalidates menu tracking before it restores, activates, marks main when supported, and raises the exact retained window.
- Settings is the only place that can request Accessibility consent. Startup and application menus only read current trust. No duplicate permission preference is stored.
- VoiceOver actions cover available app commands and discovered windows. Existing context-click handling, focus navigation, tooltip suppression, auto-hide holds, and pin/display commands remain in place.

Spaces and full-screen transitions are best-effort: public APIs neither expose complete Space ownership nor guarantee cross-Space activation. Windows owned by helper processes with unusual Accessibility trees may not appear beneath the regular app's icon. This application-menu slice did not itself capture thumbnails; the later Window Peek slice below adds a separate, explicit Screen Recording permission flow. DeeDock uses no private window-server API or AppleScript for either feature.

### Compilation and authored coverage

The focused unsigned Debug app build used:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/DeeDock-window-menu-build \
  CODE_SIGNING_ALLOWED=NO build
```

It reported **BUILD SUCCEEDED**. A separate command with the same arguments and `build-for-testing` reported **TEST BUILD SUCCEEDED**. Xcode emitted the existing skipped App Intents metadata warning and the existing test-target dependency-scan warning.

Authored Swift Testing coverage exercises closed, running, hidden, and multi-instance projections; granted, denied, unavailable, loading, empty, and failed discovery; duplicate, untitled, minimized, and main window metadata; exact token routing; stale discovery cancellation; every application command; and partial-process rejection. The services are injected, touch no real applications or Accessibility state, and use no shared mutable fixture.

The string catalog parses, the entitlement plist is valid, and the diff passes whitespace validation. No entitlement was added or removed.

**No tests were executed. The app was not launched. No permission prompt, preview, automated visual check, signed sandbox checkpoint, or hands-on runtime acceptance was performed.**

### Required hands-on acceptance

- Use one consistently signed sandboxed build. Grant and revoke Accessibility access from Settings, use Check Again after external changes, and confirm startup and app menus never prompt.
- Verify right-click and Control-click do not steal focus. Exercise ordinary, dialog, minimized, main, duplicate-title, and untitled windows, plus a window that disappears while its menu is open.
- Exercise multiple instances, a partial cooperative-quit rejection, Finder reveal, app termination during tracking, menu replacement, dock removal, sleep/wake, and shutdown. Confirm failures reach only the initiating live dock.
- Check every dock edge and multiple displays, Spaces, full-screen windows, Electron-style apps, and apps with helper-owned or unusual Accessibility trees. Record which windows public AX can discover and raise from the signed sandbox.
- Verify VoiceOver window and app actions, Focus Dock behavior, tooltip suppression, and auto-hide menu holds.

If the signed sandbox checkpoint cannot read, unminimize, and raise representative windows after a manual grant, stop with application-level actions intact. Do not remove App Sandbox, add exceptions, or change distribution without a separate decision.

## Window Peek

Implemented as an app-wide transient panel with shared defaults and independent display overrides under the new Previews settings category. Window Peek is enabled by default. Hover uses a configurable 0.2 to 1.0 second dwell, while Focus Dock opens it with Space. Ordinary icon clicks and application context menus keep their existing actions.

The panel supports Small, Medium, and Large cards; List, Grid, and Filmstrip layouts; Glass, Minimal, and Captioned styles; minimized and untitled filters; and Compact, Balanced, and Showcase presets. Presets apply the underlying fields rather than adding another persisted value. Existing settings documents receive Balanced defaults, and each field follows the existing nullable display-override model.

Accessibility remains the source for exact individual-window discovery and raising. ScreenCaptureKit supplies one-shot, memory-only thumbnail images after an explicit Screen Recording grant. Public APIs expose no direct identity bridge, so AX-backed capture matches PID, normalized title, and near-identical bounds and refuses ambiguous matches. If AX discovery fails, ScreenCaptureKit's public PID, title, and bounds metadata supplies capture-only cards; selecting those activates the app instead of claiming exact-window control. Capture errors, protected content, minimized windows, missing permission, and individual matching failures preserve metadata or app-level fallback actions.

Permission trust and usable AX window access are reported separately. The current target keeps App Sandbox enabled. Apple documents accessibility APIs used by assistive apps as incompatible with App Sandbox, so a build can retain its TCC grant while every cross-process query fails. DeeDock falls through to ScreenCaptureKit preview cards when that service is granted, otherwise reports the sandbox restriction and keeps Show App available. Removing App Sandbox or introducing a separate helper remains a product and distribution decision, not an implicit Window Peek change.

Permissions are app-wide and live at the top of both Defaults and display Previews pages. Permission actions remain enabled if persisted settings require reset. Startup and hover only read status; only the Settings Enable buttons request macOS consent. No entitlement, dependency, persistent image store, private window-server API, or automatic System Settings change was added.

Authored tests cover absent-key defaults, preset projection, display inheritance, permission request gating, the fallback matrix, dwell retention, stale-result suppression, delay normalization, conservative matching, and four-edge clamped placement. Deterministic SwiftUI samples cover the permission combinations, preset-driven sizes/layouts/styles, fallback states, long text, and Reduce Transparency without requesting permissions or inspecting real windows.

The final focused Xcode app build succeeded with no reported diagnostics. The signed Debug app launched, and its console showed one XProtect rule-read diagnostic at startup but no two-second recurrence after the Trash monitor stopped recompiling its read-only script. The currently launched Debug identity reported both privacy grants as disabled, so thumbnail rendering and window-card interaction could not be accepted in that process. No test suite, SwiftUI preview, or automated visual check was run. Compilation and the bounded console observation do not establish permission behavior, capture correctness, window selection, native input, or visual quality.

### Required hands-on acceptance

- Grant, deny, revoke, and regrant each permission independently in one consistently signed build. Confirm no prompt appears from startup, hover, context menus, or Focus Dock.
- Exercise exact selection, disappearing windows, duplicate and untitled windows, minimized and protected content, helper-owned windows, multiple Spaces, and full-screen apps. Confirm uncertain matches never display another window's image.
- Check hover dwell and rapid target changes, pointer travel into the panel, outside clicks, app clicks, menu opening, dragging, folder stacks, file picking, display removal, settings changes, lock, sleep, wake, and shutdown.
- Check every size, layout, style, preset, and filter under Defaults and per-display overrides. Include four edges, negative origins, scaling, crowded panels, remembered displays, and long localization.
- Exercise Focus Dock with Space, arrow navigation, Return, and Escape, plus VoiceOver, Reduce Motion, Reduce Transparency, and foreground-focus preservation.
- Measure idle and visible-Peek CPU, GPU, and memory use. Confirm capture stops and images are released when Peek closes.

## Dock Modes

Implemented on 2026-09-04 as an app-wide named configuration layer over display pins and App Visibility. The first launch after this change creates **Default** from the existing shared visibility, display visibility overrides, and every remembered display's typed pins. Legacy keys remain untouched for rollback, while subsequent pin and visibility edits write to the active mode.

The versioned modes document stores ordered stable IDs, names, active and previous IDs, shared App Visibility, and each remembered display's pins and optional visibility override. Saves complete before live state changes. Load corruption preserves the recoverable legacy projection, blocks persistent pin and mode edits, and exposes an explicit Settings reset. A newly discovered display copies the primary display's pins independently in every mode.

**Settings → Modes** supports creation by duplicating the active mode, renaming, arbitrary duplication, reordering, activation, and deletion while retaining at least one mode. Names are trimmed and unique under case- and diacritic-insensitive comparison. App Visibility remains in Behavior, where Defaults edits the active mode's shared value and displays can create or clear independent overrides. Other settings remain outside modes.

The menu-bar **Dock Mode** submenu lists modes in their saved order, marks the active one, exposes Previous Mode, and opens management. Focus Dock opens an anchored keyboard picker with M; Up and Down navigate, Return selects, and Escape returns to the dock. Switching closes Window Peek and folder stacks, cancels window discovery, and is blocked during native menu tracking, file picking, and drag sessions. Connected docks refresh together after persistence succeeds, while running-only applications keep discovery order.

Authored Swift Testing coverage includes legacy migration and key retention, corrupt recovery, failed-save atomicity, naming, ordering, duplication, active deletion, previous-mode toggling, live-edit isolation, display visibility overrides, new-display seeding across modes, four-edge geometry with a negative display origin, and keyboard picker navigation. Deterministic SwiftUI samples cover normal management, long names, corrupt-storage recovery, the picker, and its reduced-transparency rendering. Preview dependencies neither inspect applications nor touch real preferences.

Xcode's focused build-for-testing completed successfully in 4.747 seconds, compiling the app and test targets without executing tests. The subsequent focused DeeDock app build completed successfully, and Xcode reported no warning-level diagnostics. No test suite, SwiftUI preview, automated visual check, app launch, or permission-sensitive runtime action was performed.

### Required hands-on acceptance

- Switch among at least three modes from the menu bar and Focus Dock. Confirm Previous Mode toggles the last two modes and selecting the active mode does nothing.
- Edit pins, folder presentation, shared App Visibility, and a display visibility override in each mode. Restart and confirm isolation, order, inheritance, and remembered disconnected displays.
- Attach a new display and confirm each mode seeds it from that mode's primary-display pins while inheriting shared visibility. Repeat with a negative-origin arrangement and each dock edge.
- Switch with Window Peek and a folder stack open. Confirm both close, focus selection repairs to a stable surviving item or its nearest neighbor, and running-only app order remains unchanged.
- Confirm switching is disabled during native menus, file selection, and cross-display or Finder drags. Cancel each operation and verify switching becomes available again.
- Exercise long localized names, VoiceOver actions, Reduce Motion, Reduce Transparency, sleep/wake, display removal, and corrupt modes reset in a disposable preferences domain.

## Shelf

Implemented on 2026-09-04 as the first dock tile that owns content rather than pointing at an application. A shared `ShelfController` holds security-scoped references to user-dropped files; nothing is copied, moved, or deleted. The document is stored under `dock.shelf.v1`, independent of display profiles and of Dock Modes, and is injected into every `DockStore` beside the existing `TrashController` so one edit re-renders every dock.

`FolderStackPanelController`'s window, dismissal monitors, and show/close animation were extracted into `DockPopoverPanelController`, with the placement math and pointer shape moved alongside it as `DockPopoverGeometry` and `DockPopoverShape`. `DockPopoverPresenter` keeps at most one popover open across features and displays. Folder stacks keep their own state, view, and key handling and were rebuilt on the shared shell; `DockPanelController.folderStackAnchor(for:)`, `holdFolderStack(_:)`, and its `folderStackHeld` flag became `popoverAnchor(for:)`, `holdPopover(_:)`, and `popoverHeld`.

The tile renders after every application and before Trash. `DockRenderSlot.isUtility` now covers both, so `DockGeometry` continues to derive a single divider before the pair with no new layout code. `DockExternalPayload.trashItems` was renamed `stageableItems` and now feeds both drop targets.

Dragging out writes plain `.fileURL` pasteboard items plus a private `…DeeDock.shelf-drag` type naming the staged ids. Other applications see ordinary file references; DeeDock uses the private type to distinguish a staged reference from a Finder batch, so a Shelf item dropped on Trash reports **Remove from Shelf** and discards only the reference, while a Finder batch still reports **Move to Trash** and still calls `NSWorkspace.recycle`. Items already staged cannot be dropped back onto the Shelf. Security scope is held for the whole session and released when AppKit reports it ended. A completed drag deliberately does not remove the item.

Authored Swift Testing coverage: persistence round trip, corrupt storage reported without overwriting the stored bytes and blocking further writes until an explicit reset, an unknown document version failing rather than reading as empty, duplicate suppression and capacity reporting, explicit removal and clearing, drag-out leaving the item staged, a missing file staying listed as unavailable, security-scope release exactly once and only when acquired, and four-edge projection asserting Shelf-then-Trash order with a single divider before the pair. Deterministic SwiftUI previews cover the empty and badged tile plus the panel's populated, empty, error, and reduced-transparency states; none touch real preferences or resolve real bookmarks.

`xcodebuild build` and `xcodebuild build-for-testing` both succeeded for the shared scheme, compiling the app and the unhosted `DeeDockTests` target. **No test cases were executed**, no preview was rendered, and the app was not launched.

The panel list animates insertions and removals with a snappy spring, falls back to a plain fade under Reduce Motion, and transitions the header symbol and count. Selection follows Finder list conventions — replace, Command-toggle, Shift-extend, ⌘A — plus a rubber band swept over empty space. `ShelfSelection` holds that arithmetic as pure functions so it is testable without a window. The sweep overlay declines every point inside a row and the trailing `NSScroller.scrollerWidth` strip, so row presses and scroller drags are unaffected. A drag starting inside the selection carries all of it; one starting outside carries a single row.

### Required hands-on acceptance

- Drop a Finder selection on the tile. Confirm the badge updates on every display's dock and the files stay where they were on disk.
- Open the panel from a second display and confirm identical contents.
- Drag one row into a Finder window and into a full-screen app. Confirm the item remains staged both times.
- Drag the tile itself into Finder and confirm every staged item arrives in one drop.
- Drag a staged item onto Trash. Confirm the label reads **Remove from Shelf**, the item leaves, and the file is still on disk.
- Drop the same batch from Finder onto Trash. Confirm it still reads **Move to Trash** and still trashes.
- Quit and relaunch. Confirm items persist and still drag out, which exercises bookmark resolution across launches.
- Move a staged file in Finder, reopen the panel, and confirm the item reads as unavailable, Remove still works, and nothing is purged automatically.
- Turn Shelf off in shared defaults and on as a per-display override. Confirm the tile appears on that display only, the divider stays correct, and no layout jump occurs.
- Exercise all four edges: the panel places inward and stays on screen, and the divider sits before the Shelf/Trash pair.
- Focus Dock: arrow to the Shelf, Return to open, Up/Down to select, Delete to remove, Escape to return focus to the dock.
- VoiceOver: tile label, count value, and actions; panel rows exposing Remove from Shelf and Show in Finder.
- Reduce Motion (panel cross-fades without sliding) and Reduce Transparency (opaque panel).
- Confirm folder stacks still open, place inward on four edges, dismiss on outside click, Escape, sleep, and display disconnect, and return focus. Opening a stack must close an open Shelf and the reverse.
- With auto-hide on, confirm a Finder drag reveals the dock and holds it while the Shelf is targeted, then hides after the drag ends.
- Fill the Shelf past 50 items and confirm the overflow is reported rather than silently dropped.
- Sweep a rubber band across empty space and confirm it selects the rows it touches in both sweep directions, that it never starts on a row, and that the vertical scroller still drags normally.
- Command-click, Shift-click, and ⌘A. Confirm a drag from inside a multiple selection carries every selected item in one drop, and a drag from an unselected row carries only that row.
- Press inside a multiple selection and release without moving: the selection must collapse to that one row.
- Delete with several rows selected removes all of them. Escape drops a multiple selection before it closes the panel.
- Add and remove items with the panel open and confirm rows animate in and out, then repeat with Reduce Motion enabled and confirm the animation degrades to a fade.

## Settings: Features

Added on 2026-09-04. `SettingsSelection` gains a `features` case beside `general` and `modes`, so Features sits above the Defaults section with a `puzzlepiece.extension.fill` tile in pink-to-magenta, a hue no other pane uses. `FeaturesSettingsPane` carries Session Capsules and Shelf cards, the Trash card moved out of Behavior, and the whole former Previews pane including its Window Access and Screen Recording permissions. `SettingsCategory.previews` is gone, and its two string-catalog entries with it.

Everything in Features is app-wide by design, which is the reason it sits where it does: panes under Defaults describe how a dock looks and where it sits, so a display can override them; a feature is on or off for DeeDock as a whole. `showSessionCapsules`, `showShelf`, `showTrash`, `confirmBeforeEmptyingTrash`, and the seven `windowPeek*` fields are absent from `DockSettingField` and `DockSettingsOverrides`. They remain on `DockSettings`, so `resolving(_:)` still carries them into every dock's effective settings — it simply copies the shared value instead of consulting an override. Stored bytes naming a retired override decode and are ignored rather than rejected. `DockSettingField.windowPeekFields` is gone, and a Window Peek preset now always writes shared settings.

`settingsPreviewDisplayRequest` became `settingsFeaturesRequest`, a Bool: Window Peek's "open settings" action has no display to select any more, so it selects Features.

## Shelf: list behavior

Added on 2026-09-04, after the first Shelf slice.

Quick Look replaces the generic type icon. `ShelfThumbnailLoader` asks `QLThumbnailGenerator` for each item's own artwork at the panel's backing scale while the item's security scope is held, caches it by item identity, and cancels every pending request when the panel closes. Items keep the workspace type icon until their thumbnail arrives, then cross-fade.

`ShelfDocument` gained `sort` and `presentation`, both defaulted when absent, so the panel reopens the way it was left. Arrangement is Date Added (newest first), Name (natural order, A to Z), or Smart. Layout is a List or a Grid of thumbnails for the two flat arrangements. Smart temporarily uses a grouped list and preserves the stored List/Grid choice for later.

Double-clicking an item opens it through `NSWorkspace.open(_:configuration:completionHandler:)`, holding its scope until the open completes and reporting a failure in the panel. The context menu adds Open, Show in Finder, Copy (file references, so pasting in Finder copies the files), Select All, Remove from Shelf, and Clear Shelf, each with an icon and each naming how many items it acts on. Keyboard gains Return to open, ⌘R to reveal, and ⌘C to copy.

Subtitles now read as the enclosing folder and a relative staging time. In grid layout the remove button is layered after the drag source so it keeps its own clicks, the same fix the list row needed.

## Semantic Stacks

Implemented on 2026-09-04 for pinned folder stacks and the shared Shelf. `FoundationModelsSemanticStackOrganizer` uses `SystemLanguageModel.default`, typed `@Generable` output, `@Guide` constraints, greedy generation, and streamed partial snapshots. The prompt supplies numbered metadata records only. It never supplies file contents, URLs, bookmark data, or a request to produce JSON.

Folder Smart is a third per-pin presentation. It groups up to 60 children ranked by modification date and adds the rest to More Items. Shelf Smart is a third persisted arrangement. It groups every available staged item and adds unresolved references to Unavailable. Groups preserve model order, items inside them use natural name order, and incomplete output is repaired so each item appears once. A live generation keeps unassigned items in Organizing; unavailable models and generation failures retain Smart, show an alphabetical fallback, and offer Retry.

The organizer caches completed results for the process lifetime using source identity plus a metadata fingerprint. Folder changes and Shelf edits create a new request, cancel current work, and reject stale snapshots. Panel close and presentation changes also cancel generation. Reduce Motion removes section movement, and VoiceOver receives one completion or failure announcement rather than every streamed update.

When the Shelf is visible and Smart remains selected, startup and persisted Shelf edits schedule a silent refresh after a 500 ms debounce. A newer edit cancels the older request. Warm-up skips unavailable models, fewer than four available items, and Low Power Mode; it never presents an error. Identical active requests share one Foundation Models generation, so opening the Shelf while warm-up is running joins the same stream and the panel retains responsibility for progress, fallback, Retry, and accessibility announcements.

## Session Capsules

Implemented on 2026-09-04 as an app-wide, user-initiated checkpoint feature. Its trailing collection tile appears before Shelf and Trash, carries the saved-capsule count, opens from a pointer click or Focus Dock Return, and can be disabled under Features. Every approved checkpoint is also projected before that tile as its own temporary Dock item using the user-approved continuation title; selecting it opens that capsule directly, and deleting it removes the item. Saved Dock items and collection rows expose matching Resume and Delete context menus, with the existing confirmation before deletion. One shared `SessionCapsuleController` persists at most 30 approved capsules under `dock.session-capsules.v1`, independent of displays and Dock Modes. Invalid versions, duplicate identities, empty required text, and oversized collections are rejected rather than read as an empty collection.

Creating a capsule discovers eligible visible windows through public ScreenCaptureKit metadata and excludes DeeDock, nonstandard layers, and tiny surfaces. The user explicitly chooses up to twelve windows. The feature then performs serial one-shot window capture, accurate on-device Vision OCR with automatic language detection, and Foundation Models 2 multimodal generation using `Attachment(CGImage)`. `FoundationModelsSessionCapsuleComposer` uses `SystemLanguageModel.default`, an `@Generable` response, `@Guide` constraints, greedy `GenerationOptions`, and a 500-token response limit. Window titles, OCR, and images are explicitly treated as untrusted data; no prompt asks the model to return JSON. If Apple Intelligence is unavailable or generation fails, metadata creates a useful editable fallback draft.

The approval screen exposes generated title, summary, unfinished tasks, selected window references, and an optional personal note. Only Save writes. `SessionCapsule`, the sole persistent record, has no screenshot or OCR fields, so transient capture content falls out of scope when draft generation ends or is cancelled. Resume resolves saved bundle identifiers through Launch Services, reopens missing apps, and asks the existing public Accessibility service to raise the first exact process/title match. If exact window control is unavailable, it activates a referenced app. Window geometry is never changed.

`WindowContextCapturing` and its display-safe candidate/snapshot values are intentionally independent of capsule state and persistence. This is the prepared seam for Window Scout: it can reuse current-window discovery, image capture, OCR, cancellation, and privacy boundaries without inheriting the capsule workflow.

Authored Swift Testing coverage checks approved-data persistence without capture fields, rejection and byte preservation for future document versions, draft trimming, and default decoding of the new feature setting. The app and test-source compilation results are recorded after final verification; test cases were not executed.

Remaining hands-on acceptance:

- Grant and deny Screen Recording from the capsule flow; verify the system prompt is never shown without the explicit Allow action and that the expected restart behavior is clear.
- Select titled and untitled windows across multiple apps, protected content, multiple displays, Spaces, and full-screen apps. Confirm discovery, selection limits, progress, cancellation, and transient-memory behavior.
- Review generated and fallback drafts in different system languages. Verify structured fields are grounded in visible context, editable, keyboard accessible, and never saved before approval.
- Save, reopen, delete, and resume capsules across an app restart. Exercise Resume and Delete from both context-menu locations. Confirm exact-window raising where Accessibility is usable and app-only fallback where the sandbox or permissions prevent it; confirm no window geometry changes.
- Exercise all four dock edges, auto-hide, another open popover, display disconnect, sleep/wake, Reduce Transparency, VoiceOver, and Focus Dock focus return.

Authored Swift Testing coverage covers Smart persistence, metadata loading, output normalization, duplicate and unknown item numbers, omitted items, stable alphabetical repair, and a fake streamed organizer. Tests do not invoke Apple Intelligence. The focused unsigned DeeDock Debug build compiles against the macOS 27 Foundation Models SDK. Live generation, model-unavailable UI, keyboard movement across groups, multi-selection while groups stream, and VoiceOver announcements still need hands-on acceptance.

### Required hands-on acceptance

- Confirm screenshots, PDFs, and images show their real Quick Look thumbnails, and that an unpreviewable file falls back to its type icon without an empty gap.
- Double-click an item and confirm it opens in the right application; double-click an unavailable one and confirm the panel reports it instead.
- Exercise every context-menu command with one item selected and with several, confirming the counts read correctly and each command acts on the whole selection.
- Switch Sort and Layout, close and reopen the panel, then restart DeeDock, confirming both choices persist.
- Confirm Copy pastes real files in Finder, not text.
- Confirm the grid layout's remove button is clickable and that rubber-band selection still works between grid tiles.
- Open Settings and confirm Features sits below Modes, that Behavior no longer shows Shelf or Trash, that Previews is gone, and that searching for "shelf", "trash", "peek", or "permissions" finds Features.
- Confirm a display's Use Defaults and the Customized pills no longer mention any feature, and that toggling a feature changes every display's dock at once.


## Spring-loaded folders and file previews

Implemented on 2026-09-04. Pinned folders accept native spring loading for file URL drags. Folder rows use the same AppKit protocol to descend through real subfolders inside the existing popover. Back and Delete return through the browsing history. Opening a stack by drag does not grant keyboard focus; an explicit click inside a folder or Shelf panel enables its keyboard commands.

File drops copy into the targeted folder. Private pin drags remain pin edits, and unsupported file promises remain rejected. The copy worker retains source and destination access through completion and does not overwrite existing entries. It preflights the batch for collisions and recursive destinations, then copies serially. Filesystem changes can still cause a later item to fail; the reported error includes the number already copied. Dismissal does not cancel an accepted filesystem operation. The destination dock receives copy errors even after the popover closes.

Folder stacks and the Shelf embed `QLPreviewView`. Select a file and press Space, or use the Quick Look context-menu or accessibility action. Space and Escape return to the list; arrow navigation updates the preview. The preview retains its file-access lease until the native view closes. Movie previews do not autoplay. Folder stack clicks now select, and double-click or Return opens. Aliases and packages remain leaf items.

The focused unsigned Debug app build succeeded against the macOS 27 SDK. The first sandboxed attempt could not access the installed Metal toolchain; the build succeeded outside the command sandbox. No tests, previews, automated visual checks, or app launch were performed. The existing Xcode configurations have `ENABLE_APP_SANDBOX = NO`; sandboxed filesystem acceptance is not established by this build, and those settings were not changed.

Required hands-on acceptance:

- Drag files from Finder over a pinned folder, wait for spring loading, descend at least two subfolders, and copy onto a folder row and into empty background space. Confirm the originals remain and the target files are correct.
- Repeat from the Shelf, from another folder stack, across displays, and with all four dock edges and auto-hide enabled. Confirm spring loading does not activate DeeDock and that dragging out retains readable file access after the source popover closes.
- Leave a target before it springs open, cancel with Escape, and drop outside DeeDock. Confirm no late open, abandoned preview, or held dock remains. A manually opened stack stays open after a cancelled outgoing drag.
- Copy a mixed batch with an existing destination name, a recursive folder destination, an unreadable source, and a read-only destination. Confirm existing files are not replaced and partial failures identify the completed count.
- Preview images, PDFs, text, movies, an unpreviewable file, and a missing Shelf reference. Exercise Space, Escape, arrow navigation, context menus, and VoiceOver. Confirm a preview closes before its owning list and no application opens merely to preview.
- Exercise nested browsing, Back, Delete, Grid, List, and Smart while directory contents change. Confirm older directory loads and semantic results never replace the current directory.
- Close the popover during a large copy, remove its display, and exercise sleep/wake. Confirm the accepted copy completes or reports its error, and transient monitors and preview leases are released.
- Check Reduce Motion and Reduce Transparency, including drag feedback, keyboard selection, and the embedded Quick Look view.

## Action Tiles

Implemented app-wide shortcut pins, explicit discovery, ordering, one active run per tile, file-drop input, and keyboard activation. Pins store stable Shortcuts UUIDs under `dock.action-tiles.v1`. Corrupt or unknown documents block edits until an explicit reset. Execution state is transient and is never replayed after launch. Native source grants are retained until the helper exits. CLI output uses temporary files to avoid pipe backpressure; ordinary shortcut output is discarded, so the shortcut owns saving or displaying results.

Xcode MCP `BuildProject`, with `buildForTesting: false`, built the app successfully with no errors. Shortcut listing was inspected to confirm identifier parsing; no shortcut was executed. No tests or native UI acceptance were run.

Remaining hands-on acceptance: pin and reorder shortcuts, restart, rename or remove a shortcut externally, exercise one and multiple dropped files from Finder and the Shelf, concurrent runs of different tiles, duplicate activation of a busy tile, helper errors, interactive shortcut prompts, cancellation, shutdown, keyboard navigation, VoiceOver, four dock edges, auto-hide, and reduced accessibility effects. Cancellation stops the CLI but cannot undo shortcut side effects. Sandbox support remains limited by the project's existing configuration.
