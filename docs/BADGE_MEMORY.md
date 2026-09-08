# Badge memory

Click a visible app badge, choose **Badge details** in its context menu, or press **B** on an app in Focus Dock. The native details window shows the current observation, the explicitly checked value and its date, and recent changes. **Mark checked** saves the current known value. Opening or activating an app never changes that baseline. **Reset baseline** removes the checked value without removing history.

App badges must be enabled in Settings. Badge memory uses the same reader and Accessibility permission as DEE-10. No window images, message text, summaries or urgency classifications are captured.

## Observation and identity rules

The single `DockBadgeReader` reads system Dock items through Accessibility. AX calls remain on its actor, with its existing coalescing, notifications and five-second fallback. History does not create another scraper or increase the polling frequency. Reading URLs for unbadged application items is necessary to distinguish explicit clears from missing items.

`AXStatusLabel` is a system Dock attribute, not a documented public cross-app badge API. Public AX calls can return unsupported attributes, timeouts or incomplete item lists. DDock cannot promise every application exposes a badge, or that every transition between samples is observed.

| Observation | Meaning | Numeric comparison |
| --- | --- | --- |
| Nonnegative ASCII integer that fits Int64 | Observed count | Current minus checked count |
| Empty status string or AX `noValue` | Explicitly cleared | Zero minus checked count |
| Other nonempty string, including `99+` | Text badge | Unavailable |
| Missing item, unsupported attribute, permission loss or failed scan | Unknown | Unavailable |

The reader keys observations by standardized installation path, matching DEE-10. A process restart at the same path keeps the explicit baseline. Multiple system Dock items for the same installation must agree; conflicting observations become unknown. Counts are never summed across processes. Moving an installation creates another identity. Source activation uses the recorded application URL and reports an error if opening fails.

Numeric deltas are net changes. For a checked value of 37, observations of 41, 35 and an explicit clear show +4, -2 and -37. None proves how many messages arrived or were read. Unknown and text observations preserve the baseline but suspend numeric comparison. A later reliable numeric value can be compared with that same explicit baseline. Counts larger than Int64 and formatted values such as `1,000` remain text.

## Focus collection

Collection is off by default. Enable **Collect badge changes in future Focus Sessions** in badge or Focus Session settings before beginning a new session. Enabling it during a session takes effect next session. Disabling it stops collection immediately and retains an incomplete digest for review.

The existing Focus Session ID, phase and deadline define the collection interval. Each app's first and last observations produce a net change, independently of its checked baseline. Identical samples do not add history or persist redundant values. The first reliable observation seeds an endpoint with zero changes. Only rows with an observed state change appear in the digest.

Pauses exclude samples and mark coverage incomplete. Sleep, permission loss and unavailable scans mark missing coverage. After DDock restarts, saved endpoints remain historical and current observations start unknown. A persisted active digest can continue for the same unexpired session, with a gap marker. Its deadline is retained separately so a relaunch after expiry closes it at the deadline, not the relaunch time. A completed or expired session closes before another sample is accepted. A scan begun before a start or resume boundary updates current details but is excluded from the digest. Relaunching DDock does not start collection for an existing session that has no active digest.

Open **Focus badge digest** from the timer panel, including after completion, or **Review badge history** in Settings. Dismissing the timer does not delete completed digests. Each digest offers source-app activation and a delete control. Deleting an active digest stops its collection for that session.

## Storage and deletion

Local UserDefaults data uses `dock.badge-memory.v1`. Current observations are not persisted. The first sample of an untracked app seeds live state; history starts with a subsequent distinct observation or an explicit checked baseline. The document stores explicit checked baselines, distinct observed values with timestamps, the focus opt-in preference, and bounded digest endpoints.

- At most 100 application histories, with the most recent 20 distinct observations per app.
- Observations expire after seven days. Explicit checked baselines expire after 30 days, even if the app continues changing.
- At most ten completed digests and one active digest, each with at most 100 app rows. Digests expire after seven days.
- At capacity, new app histories or digest rows are omitted until space becomes available. Existing records continue updating. The UI states these retention limits.
- Text badge values are limited to 128 characters. Numeric values remain nonnegative Int64 values.
- Expiration runs on startup, observation, session changes and opening the history window. No history-only polling timer runs when badge observation is disabled.
- **Delete this app's history** removes its baseline, transitions and rows from all digests. The first sample after a relaunch only seeds live state for an untracked app, so it cannot recreate deleted history. Later distinct observations can create history again. Deleted app rows remain excluded from the current focus digest until the next session. Only their paths are retained as exclusion markers while that session is active; closing the digest removes those markers.
- **Clear all badge history** deletes all retained data and turns off collection. Source-app badges and notification settings remain untouched.
- Invalid storage is preserved and edits are blocked until an explicit clear. Both the reader and writer enforce a 4 MB payload limit. An oversized write leaves the previous readable payload intact and shows the storage error.

The history window uses native controls and an opaque system background. Opening it requires an explicit action, and closing it restores the prior application when DDock still owns focus. Source activation closes the window without restoring another app. It has no custom animation and does not depend on Reduce Motion. Placement uses the pointer display's visible frame and supports negative display origins; native verification remains pending.

## Model/state cases worth testing

No tests or automated visual checks were executed for this issue. These cases should be covered when test execution is authorized:

1. Check 37, then observe 41, 35, clear, text and unknown. Verify +4, -2, -37, no numeric comparison for text/unknown, and an unchanged checked baseline.
2. Check a text value or clear, reset the baseline, then explicitly check a numeric value. App activation must never call `markChecked`.
3. Duplicate samples do not append or save. Duplicate process items agree or resolve to unknown, never summed counts. Verify Int64 limits and text clipping.
4. A failed scan, absent item and unsupported AX attribute remain unknown. Only explicit empty status or `noValue` becomes cleared.
5. Opt-in before a new session collects; opt-in mid-session waits. Disabling stops immediately. Pauses, resume, extension, manual finish, deadline expiry, dismiss and new sessions maintain their boundaries.
6. Persist and restart with a running, paused or expired session. No stale saved value becomes current; no post-deadline sample enters the old digest.
7. Delete one app, one active/completed digest, and all history. Redundant samples must not recreate deleted rows. A later distinct observation can create a new app history.
8. Reach all capacity limits, expire histories and baselines independently, and load malformed/oversized documents without overwriting them.

## Manual acceptance checklist

- Observe 37 → 41 → 35 → cleared, text, unavailable data and an app restart. Check baseline dates and deltas, including explicit reset and activation without reset.
- Revoke and restore Accessibility, disable/re-enable app badges, restart the system Dock, and exercise multiple app processes. Confirm unknown states rather than false clears.
- Run and pause a Focus Session, sleep past its deadline, relaunch DDock before and after completion, extend and finish manually. Check incomplete coverage and digest boundaries.
- Delete individual and complete histories, restart, and confirm deletion and opt-in behavior. Check repeated unchanged samples and storage bounds.
- Click badges and use context menus on bottom, top, left and right docks. Use B in Focus Dock, Tab/Shift-Tab, Space/Return, Escape, disclosure groups, and VoiceOver source-app actions.
- Check successful and failed app activation, prior-app focus restoration, app removal/moves, and duplicate installation names.
- Exercise secondary displays with negative origins and mixed scaling, unplug/replug, Spaces and full-screen apps. Hover must not open the history window or steal focus.
- Inspect English and German copy, long app/text badges, light/dark appearance, Reduce Motion, Reduce Transparency and window resizing.

## Validation record

Implementation uses the existing Xcode project, macOS 27 deployment target, Swift 5 language mode, MainActor default isolation and Approachable Concurrency. Xcode 27.0 build 27A5252f is installed. The first focused build found a generated localized-number argument requiring Int rather than Int64; the call was corrected.

Focused build result and review findings are recorded in the DEE-17 section of [acceptance notes](ACCEPTANCE.md). Compilation does not establish native interaction acceptance. This issue must remain open until the relevant manual checks are accepted.
