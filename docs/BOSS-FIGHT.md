# Boss Fight (DEE-18)

Boss Fight is an optional skin for Focus Sessions. Enable it in Settings > Features >
Focus Sessions, choose up to eight work apps, then start a Focus Session from a Dock Mode
as usual. The party appears in the timer panel. The dock tile shows a boss portrait,
remaining-time health bar, and timer; a pause symbol replaces the portrait while paused.

Health is the existing timer's remaining fraction. It does not measure productivity or
app usage. Extending a session adds five minutes through the existing timer and can
increase the health fraction. Changing Dock Modes does not change the running session.

Disable Boss Fight in Settings or the timer panel to return to the normal skin immediately.
Enabling or disabling it during a session preserves its ID, deadline, phase, and remaining
paused time. Party changes apply immediately. An empty party is allowed; unavailable apps
retain their saved name and use a system app symbol until they can be resolved again.

Completion shows a silent trophy in the existing dock tile for three seconds. Open the
timer panel and choose Dismiss celebration to end it sooner. The ordinary completed timer
and Save as Session Capsule action remain after the ornament expires. Finishing early
uses the same completion behavior. Cancel session removes the timer without celebrating
or capturing anything. Starting another session, disabling the skin, resetting storage,
or shutting down cancels the pending celebration. Startup reconciles expired sessions
without replaying a celebration; waking an already running process uses normal completion.

The optional distraction cue and sound are not implemented. No app activation observers,
launch interception, permissions, notifications, capture, or content analysis are added.
Selecting party apps does not open them or restrict any other app. The portrait and trophy
use SF Symbols, with no new assets, packages, or dependencies.

## Storage and lifecycle

`FocusSessionsDocument.bossFight` is optional in `dock.focus-sessions.v1`. An absent value
decodes to the disabled behavior, preserving existing timers and preferences. Party entries
store only a bundle identifier and display name, with unique IDs and a maximum of eight.
Invalid configuration follows the existing explicit-reset path without overwriting the
stored bytes. App names and identifiers are bounded to 512 characters.

The controller resolves and caches at most eight icons when enabled at startup or after
explicit configuration changes. Views never resolve apps or read their bundles. Disabling
clears the cache. The skin shares the existing visible one-second timeline and deadline;
there is no additional idle polling. The only extra controller task expires a celebration
after three seconds and is owned, cancelled, and checked against its event ID.

Reduce Motion prevents trophy movement. Health changes have no ornamental animation.
Reduce Transparency retains the existing opaque panel and dock appearance handling.
The timer panel exposes phase, remaining time, health percentage, party names, and native
buttons to VoiceOver without posting per-tick announcements. It scrolls when its contents
exceed available space, including when enabled while a smaller normal panel is open.

## Model and state cases worth testing

These cases are documented for future authorized tests; no tests were executed.

- Decode old documents without `bossFight`; preserve active, paused, and completed sessions.
- Reject duplicate/empty/oversized party records through the storage-reset path.
- Enable, disable, and edit party membership in every phase without changing timer identity.
- Check full, partial, paused, extended, and completed health against `FocusSession.fraction`.
- Reconcile before, at, and after a deadline on wake and restart; never replay startup victory.
- Cancel before expiry; begin a new session during victory; disable/reset/stop during victory.
  Stale tasks must not clear a newer event or finish a cancelled session.
- Add more than eight apps, select duplicates, remove an app, cancel the picker, and reload
  with an unavailable app. Confirm bounded state and fallback artwork.
- Expire/dismiss victory while retaining the completed session and explicit Capsule handoff.

## Manual acceptance checklist

All items remain unexercised until a hands-on run is authorized.

- [ ] Run normal Focus Sessions with Boss Fight disabled, including the existing normal
      completion animation preference and Capsule creation/cancellation.
- [ ] Enable the skin, choose/remove work apps, and start from the current and another mode.
      Check German and English copy, long app names, an empty party, and unavailable apps.
- [ ] Enable/disable mid-session from Settings and disable from the panel. Keep the panel
      open while toggling in Settings; all controls must remain reachable.
- [ ] Pause/resume, extend, finish early, cancel, sleep/wake, and restart just before and
      after completion. Verify timer/health agreement and no startup victory replay.
- [ ] Let a session complete with the panel closed/open and docks hidden/visible. Verify a
      brief trophy, immediate dismissal, and return to normal completion without focus theft.
- [ ] Open party and other apps from the dock, keyboard, Finder, and elsewhere. No launch
      should be delayed, blocked, intercepted, or require an extra confirmation.
- [ ] Exercise all four dock edges, small/large tiles, overflow, auto-hide, negative display
      origins, mixed scaling, display unplug/replug, Spaces, and full-screen apps.
- [ ] Navigate Settings and timer controls by keyboard and VoiceOver. Check remaining time,
      paused state, party names, remove labels, disable/cancel, and Capsule focus return.
- [ ] Enable Reduce Motion before completion and during victory: no trophy movement. Check
      Reduce Transparency and contrast in light/dark appearance.

Compilation and static resource checks are recorded in `ACCEPTANCE.md`. They do not prove
native behavior, accessible navigation, animation quality, or passing model assertions.
