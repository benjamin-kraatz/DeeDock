# DeeDock acceptance record

Recorded on 2026-09-02 with macOS 27.0 (26A5425a) and Xcode 27.0 (27A5252f). Earlier sections retain historical observations; the final section records the current auto-hide slice.

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
