# Send files through Window Peek

DEE-12 adds a file handoff to the existing Window Peek. Implementation is on
`feature/dee-12`. Native acceptance is pending.

## Choose a destination

1. Drag up to 100 files or folders from Finder, a nested folder stack, or Shelf onto a running app.
2. Hold over the icon for the configured Peek hover delay. The app stays in the background.
3. Move onto a window card. Drop to select that destination and open the file handoff panel.
4. Choose **Activate selected window**, then drag **Drag these files** into the real app window.

The initial drop retains references in DDock. It does not send files to another process.
The second drag is a native drag performed by the user, and offers only Copy.
The receiving app decides whether it can accept those files. DDock does not report verified receipt.

Dropping on the app-level target, or selecting a card with only ScreenCaptureKit metadata,
opens a handoff labeled **App-level destination**. That handoff offers **Activate app**.
It does not claim to activate the pictured window.

**Request app-level open** submits each file to the application through NSWorkspace in source order.
The app can create new windows or select a different window. The result counts requests accepted
by macOS, not documents received or attached. Failures list filenames and system errors. A submitted
batch cannot be retried from the same panel, to avoid reopening successful files inadvertently.

**Copy file references** replaces the clipboard with the selected file URLs. Activate the destination
and paste only if that app supports file references. Keep the handoff panel open while using the files.
**Preview file** opens the existing embedded Quick Look view after an explicit action.
Closing the panel releases its temporary grants and cancels any remaining queued requests.
An open request already sent to macOS cannot be recalled.

## Use the keyboard

1. Choose **Focus Dock**, select a running app, and press Space to open Peek.
2. Press C, or use **Choose files for a window…**, to open the native file picker.
3. Select files, then use arrows to select a destination card and Return to open the handoff.
4. Use Tab to reach activation, clipboard, app-level open, and preview controls.
5. Press Command-C to copy file references, or Escape to close the handoff.

Return on the app fallback chooses an app-level handoff. Escape cancels selection without opening files.

## Public API findings

Inspected Xcode 27.0, build 27A5252f, the installed macOS SDK headers, and this target's build settings.
The target deploys to macOS 27, uses Swift 5 language mode, MainActor default isolation, and approachable
concurrency. No signing, sandbox, permission, or dependency setting changed.

[NSWorkspace document opening](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:))
accepts file URLs, an application URL, and launch configuration. There is no destination-window argument
in the installed SDK's `NSWorkspace.h`. This implementation therefore labels that operation app-level.

[NSDraggingDestination](https://developer.apple.com/documentation/appkit/nsdraggingdestination) delivers
an AppKit drag to DDock's own registered views. A Peek thumbnail is not the other process's view.
The implementation does not synthesize events or redirect a drag into another process.
Exact activation uses the existing public Accessibility window token, with trust, process, and AX
window validation before activation. If this fails, DDock reports the failure and retains the files.
It does not replace exact activation with app activation silently.

[App Intents](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent)
expose actions implemented by the owning app. No app-specific Attach or Add to project contract was
established here. Those actions are absent. Existing user-configured Shortcuts Action Tiles remain a
separate choice and do not prove delivery to a Peek window. No Foundation Models action, content
interpretation, or Summarize into Shelf action is introduced.

## Ownership and limits

The native drag coordinator validates the pasteboard once off the UI actor. Peek accepts only the
same pasteboard generation and a copy-capable document batch. Moving between dock and cards shares
that batch. A 650 ms exit grace spans the panel gap. Escape, native drag completion, source changes,
display changes, and dismissal invalidate pending presentation work.

A private in-process lease token allows nested-folder and Shelf drags to transfer their existing
source grants. A destination retains the lease before the source releases its session. The handoff
owns at most one batch of 100 unique URLs, preserving first occurrence order. It retains no file
contents. Opening and metadata validation happen outside native drag callbacks. Outgoing native drags
retain grants even if the handoff closes during the drag. The clipboard is an explicit user action,
not a permanent bookmark store.

Peek reuses its existing conservative thumbnails and permission fallback. Its deliberate file-drag
dwell or keyboard action opens the feature. It does not capture at startup or while waiting for dwell.
Quick Look requires its own click. Window contents never become instructions or model input.

## Model and state cases worth testing

No tests or automated visual checks were executed for this issue. These cases should receive focused
coverage when test execution is authorized:

- Same drag entering dock, crossing the panel gap, selecting different cards, and returning to dock, including re-entry after an expired dwell.
- New pasteboard generations, private pin payloads, non-copy source masks, and cancelled imports rejected by Peek. Copy-only outgoing drags rejected by real Trash.
- Dwell cancellation, Escape, native end, changed app target, and late discovery results after dismissal.
- Picker cancellation and selected files retaining their immutable app destination across focus changes.
- Parent-folder and Shelf scope transfer, source dismissal before handoff, and exactly-once scope release.
- A closed AX window, terminated app, reused PID, lost Accessibility permission, and capture-only cards.
- Ordered deduplication, empty and over-limit batches, unreadable files, and deletion after initial validation.
- Serial app-open requests with mixed success, cancellation between files, no automatic retries, and accurate counts.
- One transferred discovery session released after activation or cancellation, including an action queued behind AX work.
- Four-edge Peek placement with extra routing controls, small screens, negative origins, and keyboard scrolling.

## Manual acceptance checklist

All items below remain untested. Compilation alone does not complete DEE-12.

- Use two windows of one app and then two different apps. Confirm exact window identity and duplicate-title handling.
- Drag multiple ordered files from Finder, nested folders, and Shelf. Close each source panel before completing handoff.
- Use a protected or external source requiring scoped access. Keep the handoff open, preview, and drag out after source closure.
- Confirm no application activation before an explicit activation or app-level open action. Test Escape during dwell,
  while crossing the gap, over a card, and after drop. Confirm files and Shelf entries remain intact.
- Confirm unsupported and capture-only targets read as app-level. Test an app that rejects documents and an app that
  accepts native drops. Do not accept request counts as proof that a specific window received files.
- Close the selected window, terminate its app, revoke Window Access, remove one file, and remove the source volume.
  Check visible errors, retained files, and partial open-request reporting without retries.
- Exercise the keyboard route, VoiceOver labels and actions, Quick Look, and manual paste in a supporting app.
- Test bottom, top, left, and right docks; all Peek layouts; crowded docks; auto-hide; multiple displays with negative
  origins and mixed scales; display unplug; Spaces; full-screen windows; sleep, wake, and lock.
- Check German and English copy, long filenames, Reduce Motion, Reduce Transparency, and panels on a small display.
- Dismiss the panel during an outgoing drag and an app-open request. Confirm the current grant survives to its consumer,
  later requests stop, and no stale window activation occurs.
