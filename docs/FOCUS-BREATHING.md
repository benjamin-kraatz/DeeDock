# Focus breathing

This feature is deprecated and will be removed in version 1.0.0. Launch turns it off.
Settings remain under **Settings → Features → Deprecated → Focus breathing**.

Enable **Breathe dock background** on that Deprecated page. The switch starts off and applies to all displays.
**Breathing intensity** controls the highlight amplitude from 0 to 100 percent.
Reset restores 30 percent. Zero removes the effect.

Running DDock Focus Sessions trigger breathing when their checkbox is on.
Paused and completed sessions do not trigger it. Select individual Dock Modes to
make them trigger breathing too. No modes are selected by default.
Any active trigger is enough, so pausing a session does not stop breathing if a
selected Dock Mode or configured macOS Focus filter remains active.

## Connect a macOS Focus

1. Enable Focus breathing in **Settings → Features → Deprecated**.
2. Open **System Settings → Focus** and choose a Focus.
3. Add DDock under **Focus Filters**.
4. Turn on **Breathe dock background** in that filter.

DDock uses Apple's public `SetFocusFilterIntent`. The filter's boolean defaults to
false because macOS delivers default values when a filter stops applying.
DDock queries `DockFocusFilterIntent.current` on startup, re-enabling the feature,
app activation, wake, and session activation. Intent delivery updates the running app
without polling. An unavailable current-filter query leaves the system trigger inactive.

This is an app-specific filter, not passive detection of every system Focus.
It does not read Focus names, private preferences, private notifications, or other apps.
It does not request communication-app Focus status access or change notification delivery.
No extension is needed for this app-only appearance change, as described in
[Apple's Focus filter session](https://developer.apple.com/videos/play/wwdc2022/10121/).
Filter discovery and delivery still require native acceptance on the target macOS build.

## Appearance and lifecycle

The six-second cycle varies an accent-color fill and an inset one-point border
inside DDock's existing background. Icons, labels, badges, hit regions, layout,
the Launcher, and the system Dock are unaffected. Every display uses the same
clock phase. Only the decorative view owns the timeline, capped at 30 frames per second.

Reduce Motion removes the effect entirely. Reduce Transparency retains the opaque
background and permits the highlight unless Reduce Motion is also enabled.
A hidden background, hidden dock, zero intensity, sleep, or inactive login session
removes the timeline. Idle fading also scales the highlight's opacity.

Preferences use `dock.focus-breathing.*` keys independently of display profiles
and Dock Mode documents. Selected modes use UUIDs, so renaming keeps the selection.
Duplicating a mode creates an unselected identity. Deleted mode IDs cannot trigger
the effect. Live macOS Focus state is never persisted.

## Native acceptance still required

- Confirm the master switch starts off and settings survive a restart.
- Configure DDock's filter, switch Focus on and off, edit or remove the filter,
  and launch DDock while the configured Focus is already active.
- Select and switch Dock Modes, including a renamed or deleted mode.
- Start, pause, resume, and finish a Focus Session, with overlapping triggers.
- Compare intensity at 0, 30, and 100 percent and use the reset button.
- Toggle Reduce Motion during a cycle. Check Reduce Transparency independently.
- Check hidden backgrounds, idle fading, auto-hide, Launcher transitions, and all edges.
- Check multiple displays, unplug/replug, Spaces, fullscreen, sleep/wake, and login-session changes.
- Check keyboard and VoiceOver controls and long German mode names.

The implementation has not been accepted for native appearance or interaction yet.
