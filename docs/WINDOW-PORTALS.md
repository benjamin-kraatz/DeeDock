# Window portals

DEE-14 adds persistent, session-only window previews. In Window Peek, choose **Pin window portal**
from a card's context menu or VoiceOver actions. In Focus Dock, open Peek with Space, select a card,
and press P. Pinning closes Peek and opens an independent portal. The accessible menu action is
this issue's detach mechanism; card dragging is not implemented.

Drag the native title bar to move a portal and its edges to resize it. The image always fits its
source aspect ratio, with unused space when the panel has a different shape. **Show source** tries
to raise the selected window through public Accessibility access. If access or a unique match is
unavailable, it activates the original application and displays an explicit fallback message.
Clicks inside the image do not control the other app.

Use **Focus next portal** in the DDock menu to cycle through existing portals. With a portal focused,
arrow keys move it by 10 points, or 40 with Shift. Return shows the source, Space pauses or resumes
updates, and Escape or Command-W closes it. The context menu and VoiceOver actions also expose
movement, source navigation, and close. Mouse pinning does not make the portal key. Keyboard
pinning deliberately transfers keyboard focus. Hover has no focus handler.

## Window and capture policy

At most four portals can exist, including closed portals whose in-flight capture is still draining.
Each owns its panel, serial capture task, capture actor, and last image. Closing the portal removes
its UI and image immediately, cancels owned tasks, and prevents any later result from updating it.
The screenshot API has no cancellation handle. An already submitted request can finish after close;
its slot remains reserved until it returns. No new image request is submitted by that portal.

A portal uses AppKit's floating level above ordinary application windows. It joins Spaces and uses
`fullScreenAuxiliary`. These flags express the intended behavior, but do not guarantee visibility
over every full-screen or system window. On display changes, the panel fits within the visible
frame of the screen with greatest overlap. If its screen disappears, it moves to an available
screen and stays there on reconnection. It does not restore a disconnected screen's prior placement.
Coordinates are global AppKit points and support negative display origins. Capture dimensions use
the panel's current backing scale on the next update. No content or placement persists across quit.

The first explicit pin action binds a unique PID/title/bounds match using Window Peek's matcher.
After binding, capture follows that ScreenCaptureKit window ID despite title, size, or position
changes. It never repeats the title/bounds binding. A missing bound ID is terminal, requiring a new
pin. The original `NSRunningApplication` is retained to detect process termination rather than follow
a restarted app with a reused PID. Public window IDs have no documented lifetime generation, so
unobserved ID reuse within a still-running process remains an API limitation. Ambiguous initial
matches remain unavailable rather than selecting a different window.

Peek and portals share `WindowScreenshot`. The window-only content filter excludes overlapping
windows from its image. Child-window capture is disabled. Discovery and portal binding exclude
DDock's PID, so DDock portals cannot become capture sources. No OCR, model processing, content
persistence, cross-process input forwarding, or new permission prompt is added.

## Frame states and resource budget

| State | Meaning |
| --- | --- |
| Connecting | Waiting for the first capture or a resumed update |
| Live | A screenshot completed within the past five seconds |
| Paused | Occluded portal, off-screen source, sleep, or crop editing |
| Paused by you | Explicit user pause, or waiting for Resume after a privacy suspension |
| Frozen snapshot | Deliberately retained frame with a visible capture date and time; no new capture |
| Choose region again | Source dimensions changed; cropped presentation is hidden until reselection or Whole window |
| Source unavailable | Source process ended, the bound window disappeared, matching failed, or initial capture failed |
| Stale frame | Capture failed after an image was received, or no replacement arrived for five seconds |
| Screen Recording access required | The existing permission is absent or revoked; the retained image is cleared |

One update runs per portal, followed by a one-second delay, or three seconds in Low Power Mode.
There is no catch-up burst or overlapping scheduled capture within a portal. User-paused, occluded,
and sleeping portals submit no screenshots. Off-screen sources need metadata enumeration to detect
return, but submit no screenshots. Permission checks continue while user-paused. Sleep, display sleep,
and inactive-session reasons are tracked separately so one wake notification cannot resume the others.
An independent monotonic age check prevents a slow screenshot request from leaving an old image Live.

Each image fits within 1280 × 960 pixels, about 4.7 MiB at four bytes per pixel. Four retained images
have a calculated pixel budget of about 18.8 MiB, excluding AppKit/GPU/framework copies and a replacing
image in flight. Only the newest image is retained. The close log in the `WindowPortal` category records
successful frame count, cumulative successful capture milliseconds, and elapsed portal lifetime, without
window names or content. This instrumentation supports measuring cadence and capture latency. CPU,
GPU, actual retained memory, and live energy cost have **not** been measured.

ScreenCaptureKit metadata cannot distinguish minimization from another Space. Such off-screen sources
pause. Protected content can be blank even when capture succeeds; a successful screenshot does not
prove that protected pixels are fresh. Missing permission, hidden sources, closure, and screenshot
errors do not promise fresh images. Source navigation performs a fresh lookup of the bound ID before
conservatively matching an AX window with normalized titles and a two-point bounds tolerance; if that join fails, only the app is activated.

## SDK evidence

The implementation was compiled with the installed Xcode 27 beta macOS SDK, with deployment target
macOS 27.0, Swift 5 language mode, MainActor default isolation, and approachable concurrency. Local
`SCShareableContent.h`, `SCStream.h`, and `NSWindow.h` were inspected before selecting the APIs.
Apple documents the [single-window filter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter)
and [full-screen auxiliary behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary).
Runtime behavior still requires the following acceptance checks.

## Validation record

Focused app builds use:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/deedock-dee14-build build
```

Intermediate compilation found and repaired a localized error-message type mismatch and a closure's
missing explicit `self`. App compilation subsequently succeeded. Existing Launcher and DockBadge
warnings and the App Intents metadata-extraction notice are unrelated to this feature. String Catalog
JSON and the final diff passed inspection. All 20 portal keys in the built English and German
resources match the catalog. No tests, previews, automated visual checks, live
capture, or native manual acceptance have been run for DEE-14. Compilation does not complete the issue.

GPT 5.6 Luna reviewed the implementation at Extra High reasoning. Its three findings were addressed:
source navigation now shares Peek's metadata tolerance, rechecks the retained process after asynchronous
work, and capture checks cancellation immediately before screenshot submission. Final lifecycle review
also added per-request cancellation, independent permission revocation checks, and closed-slot focus guards.

### Model and state cases worth testing

- Binding refuses ambiguous, missing, self-owned, or terminated sources; a changed title or frame
  does not rebind an existing portal. A disappeared ID never binds again.
- The fifth pin fails without closing any portal. An in-flight closing portal still counts toward four.
- Close during enumeration, screenshot, source lookup, and pause rejects late results and frees the slot.
- Pause, permission loss, display-scale changes, and overlapping suspension reasons invalidate in-flight results.
- An image older than five seconds becomes stale even while another capture is pending.
- Geometry clamps fully outside and partially overlapping frames on negative-origin and small displays.
- Successful source navigation uses fresh bound-ID metadata; ambiguous AX matches fall back to the app.
- No capture backlog forms when requests take longer than the configured interval.

### Manual acceptance checklist

- Pin a changing export, clock, or dashboard. Verify readable live content, source aspect ratio during
  source and portal resizing, status changes, source jump, and close. Confirm hover never changes focus.
- Exercise menu, P in keyboard Peek, VoiceOver pin/move/source/close, Focus next portal, arrows, Shift arrows,
  Return, Space, Escape, Command-W, and native title-bar controls. Check long source names and German copy.
- Open four portals, attempt a fifth, close one during capture, and pin again after teardown. Verify the
  others continue updating. Check that own windows never appear recursively, including overlapping portals.
- Move between displays with different scales, including negative origins. Unplug and reconnect the active
  display, rearrange displays, and exercise all four dock edges. Confirm the portal stays reachable.
- Minimize, hide, resize, rename, close, and reopen the source. Move it across Spaces and enter full screen.
  Confirm missing sources never attach to replacement windows and off-screen content is marked paused.
- Revoke Screen Recording while live and user-paused. Verify old images clear, no prompt appears, and
  granting access via Settings permits resumption for an existing binding. Include denied AX access.
- Pause while capture is pending. Sleep/wake, display sleep/wake, lock/unlock, and session switch during
  capture. Verify no late frame overwrites paused state, and no duplicate update loop appears on resume.
- Exercise Reduce Motion and Reduce Transparency, keyboard focus visibility, and VoiceOver source labels.
- Measure one and four changing portals for 60 seconds each, repeat in Low Power Mode, then pause and
  close them. Record capture counts/latency from WindowPortal close logs, and CPU/GPU/memory in Instruments.
  Verify closed capture drains once and no subsequent screenshots or retained frame growth occur.

The final merge of `origin/main` preserved DEE-15's window search commands, coordinator lifecycle, and
all catalog entries alongside portals. The merged app build passed. All 78 portal/search keys match
both compiled languages. This merge validation did not launch either feature.

## DEE-23 cropped and frozen portals

In an existing portal, choose **Choose region…**. Drag across the full-window preview or use the
four percentage steppers for horizontal position, vertical position, width, and height. Keyboard
and VoiceOver users can adjust each stepper in one-percent increments. **Apply crop** confirms
the selection. **Whole window** in the editor resets the draft; the same context-menu action
immediately returns the portal to the full window. Each dimension has a five-percent minimum.
The existing Peek pin action and four-portal limit remain unchanged.

**Zoom** opens controls for magnification from 1× to 4× and horizontal and vertical position.
Drag the image to pan, or use the labeled sliders with keyboard or VoiceOver.
**Reset zoom and pan** fits the saved crop. Both crop and zoom preserve aspect ratio and leave
letterboxing when necessary. Image gestures change only the preview, never the source application.

**Freeze snapshot** keeps the current retained frame and its capture date and time. It cancels
pending work and rejects late results; an already submitted SDK screenshot may still finish.
The serial loop submits no screenshots or source discovery while frozen. Permission checks still run.
**Resume** revalidates capture permission, the original running process, the bound window ID,
on-screen status, and source dimensions before showing a new live frame. It never repeats title matching.
Closing clears the sole retained image. No file export, restoration, history, or disk storage is added.

Sleep, display sleep, inactive-session notifications, and permission loss clear all retained pixels,
including frozen snapshots and crop editor previews. Privacy suspension ends freeze and requires
explicit Resume after waking. An ordinary display disconnect repairs placement without clearing a
frozen frame. Source termination leaves a frozen snapshot labeled with its original time; Resume
reports unavailable. The timestamp is the screenshot completion time, not a source application's data time.

### Region and frame contract

`NormalizedWindowRegion` is shared with Watch through its existing type alias. Regions use top-left
unit coordinates of the entire source window. Preview gestures belong to the fitted image rectangle,
so centered letterbox margins do not enter normalization. SwiftUI image offsets use top-left image
coordinates; no bottom-left AppKit flip applies. Image dimensions are pixels. Window size checks use
ScreenCaptureKit global-point dimensions, independently of output pixels and backing scale.
Portal placement alone uses AppKit global points, including negative display origins.

The crop stores the source-point size at confirmation. Any observed size change pauses cropped
presentation and retains one new whole-window frame for reselection. The portal hides the mismatched
crop until the user confirms a region or returns to the whole window. The next capture checks again,
including after Resume. Moving between displays with unchanged source-point dimensions preserves the
region. Relative coordinates cannot track semantic content or detect layout changes at unchanged size.
Choose the region again after such a layout change.

Cropping is presentation-only. The retained full-window bitmap supports reselection and zoom without
a second image owner. Cropped capture uses at most 1280 × 960 pixels through the existing single
serial request. Whole-window capture retains its panel-size/backing-scale budget. Zoom changes no
capture cadence, creates no stream, and retains no additional bitmap. SDK/framework/GPU transient
copies are outside the calculated retained-pixel budget.

The installed macOS 27 `SCStream.h` exposes `sourceRect` in logical points to sample a subset of the
input and `destinationRect` in output pixels. Source cropping could reduce sampled/output data when
configured with smaller output dimensions. This implementation leaves those fields unset to retain
the full-window selection preview. No measured CPU, GPU, memory, or energy savings are claimed.

### Validation and pending acceptance

Focused unsigned app compilation uses the existing DeeDock target and Xcode 27. Tests and automated
visual checks are not authorized and were not run. Native acceptance and measurements remain pending;
DEE-23 must not be marked Done on compilation alone.

Model/state cases worth testing include minimum and boundary crops; letterbox exclusion; fit and pan
at all four corners and zoom limits; source-size changes before and after confirmation; freeze during
an in-flight request; privacy clearing while an editor is open; and Resume after process/window loss.

Native acceptance must cover a narrow progress bar and chart, all four dock edges, negative origins,
unequal displays, Retina and non-Retina scaling, source movement/resize/layout changes, and display
reconnection. Exercise keyboard/VoiceOver editing and sliders, Reduce Motion/Transparency, source
navigation, Spaces/full-screen, permission revocation, sleep/lock/display sleep, and closing frozen
portals. Measure four portals with live, frozen, and offscreen sources using Instruments and the
existing WindowPortal frame-count/capture-time close logs. No runtime measurements were collected.
