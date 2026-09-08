# Watch a window

Choose **Watch this** on a Window Peek card, in its context menu, or through its VoiceOver action.
In keyboard Peek, select a card and press W. The persistent panel takes keyboard focus only after
this explicit action. Choose **Whole window**, drag a rectangle over the preview, or use the four
labeled sliders with the keyboard. Slider values and the orange outline show the same bounded region.
Choose a condition and select **Start watching**. Only one watch runs at a time; another request
reveals the existing panel without replacing its source.

The watch samples after each previous request finishes, with a three-second delay. It keeps the
indicator and Stop control in a floating panel across Spaces. **Stop watching**, Command-period,
**Dismiss**, Escape, and the panel's close button do not activate the source application. Stop and Dismiss remain in a fixed footer when the preview scrolls. Dismiss
also releases the preview. A detected event ends the one-shot watch and leaves the result visible.
Delivery is a silent panel cue by default. The user can explicitly enable a sound before starting.
This slice does not send system notifications or request notification permission.

**Show watched window** checks the capture identity again and raises a uniquely matched Accessibility
window. Missing Window Access or an ambiguous match produces an explanation. **Show source app** is
a separate, explicitly labeled fallback that can activate a different frontmost window in that app.
Neither command runs automatically on detection.

## Detection rules

- Stable visible change compares 192 by 192 color samples against the first sample after Start.
  A pixel counts as changed when any RGB channel differs by at least 24 out of 255. At least 0.5
  percent of pixels must change from the baseline, while fewer than 0.2 percent change between
  consecutive samples for three confirmations. This preserves localized and color-only changes
  that a whole-region grayscale average missed. Allow roughly nine seconds after the image settles,
  plus capture time. Moving imagery may never settle. Very small changes can still be missed.
- Completion phrase uses local Vision OCR on the selected region. An entire recognized line must
  match the user-entered phrase, ignoring case and diacritics. The phrase must first be absent and
  then appear in three consecutive samples. A phrase present at Start does not immediately alert.
- A phrase result is visible text evidence. It is not an integration with the export or build system,
  and OCR can miss or misread text. Timers and pixel changes never imply completion. Progress is
  indeterminate because this implementation has no trustworthy source percentage.
- Resize, raster-scale changes, capture failures, and suspension reset evidence. After resume, the
  phrase must again be absent before it can trigger. Repeated alerts cannot occur after completion.

## Capture and lifecycle boundaries

The initial explicit Watch action reuses Peek's conservative public title/geometry matcher to obtain
a ScreenCaptureKit window. The confirmation preview lets the user inspect that source before Start.
An ambiguous or missing initial match fails. After preparation, capture retains the selected window
handle and checks its window ID and PID against current metadata. It never rematches by title to
continue monitoring. The running application instance and a required launch date guard against process restart before and after capture. Missing launch identity fails closed.
Window IDs are OS identities, not durable document identities; this feature does not persist watches
or claim detection of an ID recycled entirely between two samples in the same process.

Regions use top-left unit coordinates relative to the full captured window. They resize proportionally,
not as a semantic attachment to a button or status label. The outline and CGImage crop share raster
coordinates, independent of global Quartz origins. Every sample reads current window bounds and
ScreenCaptureKit pixel scale. Raster dimensions are capped at 1,600 on the longest side. Shadows,
child windows, cursor, and audio are excluded. A separate display observer keeps panel controls on a
remaining screen when the arrangement changes.

| State | Behavior |
| --- | --- |
| Hidden app, minimized window, other Space, disconnected source display | No hidden-window guarantee. Offscreen metadata pauses capture, labels the preview stale, and retries after three seconds, including initial setup. Metadata lookup still detects a closed window while its app is hidden. |
| Window missing or process exited | Stop, clear preview, explain the missing source. No replacement window. |
| Screen Recording access missing or revoked | Stop, clear preview, direct the user to Settings and a new explicit selection. |
| Capture failure | Label retained preview stale, reset evidence, retry only while active. |
| Capture exceeds 15 seconds | Show stale status; do not queue overlapping capture requests. Stop remains available. |
| System sleep, display sleep, inactive session | Cancel owned work and clear preview. Independent suspension reasons must all clear before resume. |
| Wake or session return | Await the cancelled request before a new capture, then take a new baseline. Setup interrupted by sleep requires a fresh explicit selection. |
| Stop, dismiss, app shutdown | Cancel tasks and remove observers. No periodic capture remains. An OS request already in flight may finish; cancelled results are ignored. A replacement watch waits for the previous request to drain before preparing another source. |

ScreenCaptureKit may return stale or blank pixels even when a window is listed as onscreen. Identical
pixels cannot distinguish a static source from frozen source rendering. Last successful capture time
reports API success, not a guarantee that the source application repainted. Protected content and
occluded-window behavior require native verification. No universal hidden-window capture is claimed.

Capture and OCR live on a dedicated actor. One full image, transient crop, two small comparison arrays,
and at most 128 OCR lines of 512 characters are retained during processing. No image history, disk
storage, network call, or Foundation Models inference is used. Captured text is comparison data and
never becomes an instruction. Merely hovering Peek does not start this feature's capture or OCR.

The implementation uses Apple's [single-window content filter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:))
and [Vision text recognition](https://developer.apple.com/documentation/vision/recognizetextrequest).
