# App Fusion source review, 2026-09-19

This review covers pair creation, cancellation, replacement, window operations, setup,
Finder tools, proximity offers, and Fusion-specific dock dragging. It preserves the
existing uncommitted implementation. No build, app launch, tests, or automated visual
checks were run. The changes below have source-level evidence, not native acceptance.

## Corrections

- Creation rechecks application ownership after its asynchronous preflight. Two concurrent
  creation requests can no longer both claim the same app before either publishes its pair.
- Canceling setup also cancels the pair's placement task. Setup snapshots its session and
  inputs, rejects late results, and checks cancellation before launching applications.
- Selecting a replacement setup candidate keeps a previous token alive when the other
  side still lists that token. This matters when both sides use the same app.
- Replacement checks cancellation and pair membership before reinstalling observers after
  asynchronous handle cleanup. Unpair cannot be followed by an obsolete observer install.
- Canceled refreshes check ownership and cancellation after capability reads before changing
  pair state. Removed pairs cannot begin explicit operations through retained UI references.
- Restore reports display-size failure instead of leaving an apparently usable pair without
  controls. Creation validates the two-entry name and icon arrays used by the toolbar.
- Minimized-state reads propagate Accessibility failures instead of interpreting a failed
  read as an unminimized window.
- Restore polling reads readiness from the retained window instead of repeating full
  application capability scans. Layout still performs the full eligibility checks.
- Observer startup reuses an existing subscription for the same processes. Replacement
  forces a reinstall, including replacement by a new window in the same process.
- Every suspension path stops observation, cancels pending refreshes and Finder work,
  releases Compare captures, clears pending drag state, and hides the controls.
- Finder preview skips destination packages as well as source packages. Before committing
  a staged file, sync rechecks paths, root identities, and destination contents. This catches
  edits made during a long copy. File coordination cannot guarantee atomic behavior against
  unrelated processes that ignore coordination and mutate paths concurrently.
- Canceled Finder work does not publish a completed preview or success animation after its
  asynchronous operation returns.

## Observation, settle, refresh, unpair, and proximity (source, 2026-09-23)

`AppMeltObservation.start` resolves the pair's retained AX elements on the window-service actor.
It does not copy `AXWindows`. Notification registration stays on the main run loop, which is
the thread that delivers the callbacks, and it names only those retained elements. Moved,
resized, and destroyed must succeed on each member. A sibling window's success does not count.
The same elements and processes are reused until `forceRestart`, including a same-app
replacement. Title and frame are not used as identity.

Minimize and layout readback wait on those notifications. Minimize allows about 800 ms and
three reads. Layout's sleeps share a 1.6 s budget; each resize and position uses a handful of
reads. A timeout throws the existing failure and does not send the mutation again. The pair
then suspends with Restore and Unpair. No measured latency change is claimed.

Refresh keeps one trailing task per pair. It skips the full capability scan when the retained
frames still match the accepted frames. It does not minimize, restore, layout, or raise while
that pair's operation epoch, drag, or busy flag says another operation is in progress.

Unpair sets `invalidated` and seals the session before cancelling work or releasing handles.
Later App Fusion mutations on that session throw `CancellationError`. Setup cancellation seals
the same way. A cancelled operation stops observation and hides chrome before it clears `busy`.

Proximity converts the global AppKit cursor with the main display's top (`CGMainDisplayID`),
not `NSScreen.screens.first` and not the height of the display under the pointer. The offer
panel prefers the display under the pointer when it clamps. The 120 ms drag throttle and the
absence of idle window polling are unchanged.

No app launch, tests, or live multi-display checks were run for this pass. The editing
environment has no Swift toolchain or macOS SDK, so the DeeDock target was not compiled here.

## Manual checks

Build the `DeeDock` scheme for **My Mac** in Xcode, then check these interactions:

1. Create a pair, close setup during creation, and reopen setup immediately. Old results
   must not replace the new selections or leave an orphan pair.
2. Pair two Finder windows. Change a setup selection, replace a paired window with another
   Finder window, and drag or minimize that replacement. Controls must follow the new member.
3. Unpair during replacement or placement. No controls or observer-driven changes should
   return afterward.
4. Minimize and restore repeatedly, including through the source app. Exercise a slow app
   and an app with many open windows. Record any pause or recovery message.
5. Move and resize with the shared controls and native title bars. Check focus, app minimum
   sizes, multiple displays, sleep, and Space changes. Suspended pairs should require Restore.
6. Use disposable Finder folders for sync. Preview a replacement, edit the destination,
   and apply. Repeat with an edit during a large copy. The changed file must be rejected.
   Cancel a preview and a copy, then close and reopen the tools. Completed copies may remain.

Build success establishes compilation only. These checks are still pending.
