# Window Peek actions

DEE-22 adds individual-window commands to Window Peek. Use the ellipsis button, the
card's context menu, or its Window actions VoiceOver action. In keyboard Peek, A opens
the selected card's native menu. Arrow keys and Return operate that menu; Escape cancels.
The existing C, W, F, and P shortcuts keep their meanings.

The menu offers Minimize or Restore, Close window, Move to display, Left half, Right half,
Center window, Fill usable area, and one-step Undo for geometry. Unavailable actions are hidden.
When no actions are supported, Peek shows a short explanation outside the menu. Capture-only
cards explain that Window Access is required. No command falls back to Hide, Quit, or an app-wide mutation.

## Target and command lifetime

The existing Accessibility service retains each window element under its discovery-session
token. Commands require the original process launch date and exactly one equal element in
fresh AX window enumeration. There is no title, geometry, or window-number fallback.
Capabilities are read when the menu opens and before each write. Cancellation and permission
are checked immediately before native mutation. Dismissing Peek cancels queued work and
invalidates the session. Sleep and session suspension use the existing coordinator cleanup.
Display rearrangement during the menu or command cancels the presentation; geometry writes
also reject changed or disconnected display bounds. No new poller is installed.

AX calls cannot be interrupted once the operating system receives them. Cancellation prevents
subsequent writes, but cannot undo a write already sent. A geometry command may therefore
partially complete. DDock reports failure or an app-constrained result and refreshes metadata.

Close activates the source deliberately, revalidates, then presses its enabled AX close button
once. The token is consumed before that call, including on timeout. Peek dismisses without
restoring focus. Native unsaved-document dialogs remain under the source app's control. Cancel
in that dialog keeps the document; reopen Peek to discover it again. DDock does not undo Close.
Minimize, Restore, and geometry do not activate or raise the source.

## Geometry policy

The policy receives immutable display snapshots from the existing display store. It converts
AppKit screen rectangles to global AX coordinates using the primary screen's top edge.
Everything is in points. Backing pixel scale does not multiply window dimensions.

A spanning window belongs to the display with the largest full-frame intersection. Ties use
snapshot order. A completely offscreen window uses the first display on a tie. Movement carries
its relative origin to the destination usable frame and shrinks an oversized resizable window
to fit. Fixed-size windows can move or center, but cannot choose a half or fill placement.

An app can impose a minimum size without exposing a portable minimum-size attribute. DDock
requests size, reads back the accepted size, and clamps the position to the usable frame. If the
accepted size exceeds that frame, its upper-left corner stays inside it so the title bar remains
reachable. The app's accepted geometry is authoritative; a mismatch is reported, not retried.
This is rectangular placement, not macOS tiling or a Space transition.

Full-screen, sheet, modal, nonstandard, and unknown window states are conservatively unavailable.
The implementation uses public AX attribute queries for roles, children, modal state, enabled
state, position, size, minimized state, and the close button. Fullscreen detection uses optional
app-advertised `AXFullScreen` metadata, read only when public attribute enumeration exposes it.
The SDK has no portable fullscreen-state constant; its fullscreen button does not distinguish
entry from exit. An app that omits this metadata has unavailable actions rather than an assumed
windowed state. Unknown modal state is also unavailable. A normal fixed-size window may still minimize or close when those
capabilities are exposed.

Undo retains only the preceding geometry for that exact token during the current presentation.
It revalidates the same window, uses the current display arrangement, and consumes the record.
App constraints still apply. A failed placement can leave an Undo record for its partial change.
No state or preferences are persisted.

## Validation

Focused unsigned Debug app compilation passed during implementation with Xcode 27, Swift 5
language mode, and the macOS 27 SDK. Compilation does not establish native behavior.

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/DeeDock-dee22-build \
  CODE_SIGNING_ALLOWED=NO build
```

Tests, previews, automated visual checks, and native acceptance were not run. Before marking
DEE-22 Done, exercise:

- Two same-app windows, duplicate titles, closure and relaunch while the menu is open.
- Unsaved Close, cancellation of its prompt, and AX timeout without repeated Close.
- Queued cancellation, revoked permission, sleep, Spaces, and display reconnection.
- Minimize and Restore, including apps that reject or delay a write.
- Negative origins, unequal displays, mixed scales, spanning and offscreen windows.
- Fixed and minimum sizes, fullscreen, modal windows, sheets, and capture-only cards.
- A partial resize followed by failed movement, Undo, and changed constraints before Undo.
- Mouse travel into the menu, all four dock edges, keyboard A, VoiceOver, Reduce Motion,
  Reduce Transparency, and continued Watch, Fusion, Portal, and ordinary card selection.

Model cases worth automated tests include overlap ties, coordinate conversion, clamping oversized
windows, relative movement, half placement, accepted-size positioning, token invalidation,
process-birth mismatch, permission loss between writes, and consuming Close on timeout.

Public API reference: [AXUIElementIsAttributeSettable](https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable)
and [AXUIElementPerformAction](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction).
