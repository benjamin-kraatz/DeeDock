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

## Remaining observation concern

`AppMeltObservation.start` still enumerates and registers all windows for each source process
on the main thread. It also combines supported notification names across those windows,
so registration success does not establish support for each exact pair member.
Repeated startup work is reduced, but the initial cost and exact-member coverage remain
unresolved. A follow-up should move preparation off the main thread and use the retained AX
identities. It must not substitute title or frame matching for those identities.

No measured latency, CPU, or frame-rate improvement is claimed.

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
