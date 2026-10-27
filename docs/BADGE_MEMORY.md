# Badge memory

Click a visible app badge, choose **Badge details** in its context menu, or press **B** on an app in Focus Dock. The native details window shows the current observation, the explicitly checked value and its date, and recent changes. **Mark checked** saves the current known value. Opening or activating an app never changes that baseline. **Reset baseline** removes the checked value without removing history.

App badges must be enabled in Settings. Badge memory uses the same reader and Accessibility permission as DEE-10. No window images, message text, summaries or urgency classifications are captured.

## Observation and identity rules

The single `DockBadgeReader` reads system Dock items through Accessibility. Blocking AX copies for one pass run on a private serial queue, so they do not occupy the cooperative thread pool. Coalescing, notifications, and the five-second fallback stay as they are. History does not create another scraper or increase the polling frequency. Reading URLs for unbadged application items is necessary to distinguish explicit clears from missing items.

`AXStatusLabel` is a system Dock attribute, not a documented public cross-app badge API. Public AX calls can return unsupported attributes, timeouts or incomplete item lists. DDock cannot promise every application exposes a badge, or that every transition between samples is observed.

| Observation | Meaning | Numeric comparison |
| --- | --- | --- |
| Nonnegative ASCII integer that fits Int64 | Observed count | Current minus checked count |
| Empty status string or AX `noValue` | Explicitly cleared | Zero minus checked count |
| Other nonempty string, including `99+` | Text badge | Unavailable |
| Missing item, unsupported attribute, permission loss, or scans failing for 15 seconds | Unknown | Unavailable |

The reader keys observations by the resolved installation path, the same key the tile uses. An existing file keeps the on-disk spelling, so a symlink and its target share a badge without lowercasing the app name. A saved record whose path changes because it was a symlink is rekeyed once; its checked baseline moves with it, and the old key is not stored as unknown. A case-only difference joins to the stored spelling. A process restart at the same installation keeps the explicit baseline. Multiple system Dock items for the same installation must agree; conflicting observations become unknown. Counts are never summed across processes. Moving an installation creates another identity. Source activation uses the recorded application URL and reports an error if opening fails.

Numeric deltas are net changes. For a checked value of 37, observations of 41, 35 and an explicit clear show +4, -2 and -37. None proves how many messages arrived or were read. Unknown and text observations preserve the baseline but suspend numeric comparison. A later reliable numeric value can be compared with that same explicit baseline. Counts larger than Int64 and formatted values such as `1,000` remain text.

## Gaps in observation

Sleep, display sleep, and session resign hide the badges on screen. History keeps its recorded values, and the 15-second grace keeps running from the last successful scan. A failed scan inside that grace shows the hidden badges again and leaves history unchanged. A transient Accessibility timeout cannot add unknown transitions to history.

After DOKK restarts, saved values remain historical and current observations start unknown.

Badge memory used to offer an optional Focus Session digest. It was removed with Focus Sessions in DEE-148. Saved documents from older builds still load; their digest fields are ignored and dropped on the next save.

## Storage and deletion

Local UserDefaults data uses `dock.badge-memory.v1`. Current observations are not persisted. The first sample of an untracked app seeds live state; history starts with a subsequent distinct observation or an explicit checked baseline. The document stores explicit checked baselines, distinct observed values with timestamps, and their dates.

- At most 100 application histories, with the most recent 20 distinct observations per app.
- Observations expire after seven days. Explicit checked baselines expire after 30 days, even if the app continues changing.
- At capacity, new app histories are omitted until space becomes available. Existing records continue updating. The UI states these retention limits.
- Text badge values are limited to 128 characters. Numeric values remain nonnegative Int64 values.
- Expiration runs on startup and observation. No history-only polling timer runs when badge observation is disabled.
- **Delete this app's history** removes its baseline and transitions. The first sample after a relaunch only seeds live state for an untracked app, so it cannot recreate deleted history. Later distinct observations can create history again.
- **Clear all badge history** deletes all retained data. Source-app badges and notification settings remain untouched.
- Invalid storage is preserved and edits are blocked until an explicit clear. Both the reader and writer enforce a 4 MB payload limit. An oversized write leaves the previous readable payload intact and shows the storage error.

The history window uses native controls and an opaque system background. Opening it requires an explicit action, and closing it restores the prior application when DDock still owns focus. Source activation closes the window without restoring another app. It has no custom animation and does not depend on Reduce Motion. Placement uses the pointer display's visible frame and supports negative display origins; native verification remains pending.

## Model/state cases worth testing

No tests or automated visual checks were executed for this issue. These cases should be covered when test execution is authorized:

1. Check 37, then observe 41, 35, clear, text and unknown. Verify +4, -2, -37, no numeric comparison for text/unknown, and an unchanged checked baseline.
2. Check a text value or clear, reset the baseline, then explicitly check a numeric value. App activation must never call `markChecked`.
3. Duplicate samples do not append or save. Duplicate process items agree or resolve to unknown, never summed counts. Verify Int64 limits and text clipping.
4. Scans failing for 15 seconds, absent items and unsupported AX attributes remain unknown. A failed scan inside that window keeps current values and history. Only explicit empty status or `noValue` becomes cleared.
5. Persist and restart. No stale saved value becomes current. A document saved with digest fields by an older build still loads.
6. Delete one app and all history. Redundant samples must not recreate deleted rows. A later distinct observation can create a new app history.
7. Reach all capacity limits, expire histories and baselines independently, and load malformed/oversized documents without overwriting them.

## Manual acceptance checklist

- Observe 37 → 41 → 35 → cleared, text, unavailable data and an app restart. Check baseline dates and deltas, including explicit reset and activation without reset.
- Revoke and restore Accessibility, disable/re-enable app badges, restart the system Dock, and exercise multiple app processes. Confirm unknown states rather than false clears.
- Sleep and wake with badges visible, then relaunch DOKK. Check that history gains no unknown transitions inside the grace period.
- Delete individual and complete histories, restart, and confirm deletion. Check repeated unchanged samples and storage bounds.
- Click badges and use context menus on bottom, top, left and right docks. Use B in Focus Dock, Tab/Shift-Tab, Space/Return, Escape, and VoiceOver source-app actions.
- Check successful and failed app activation, prior-app focus restoration, app removal/moves, and duplicate installation names.
- Exercise secondary displays with negative origins and mixed scaling, unplug/replug, Spaces and full-screen apps. Hover must not open the history window or steal focus.
- Inspect English and German copy, long app/text badges, light/dark appearance, Reduce Motion, Reduce Transparency and window resizing.

## Validation record

Implementation uses the existing Xcode project, macOS 27 deployment target, Swift 5 language mode, MainActor default isolation and Approachable Concurrency. Xcode 27.0 build 27A5252f is installed. The first focused build found a generated localized-number argument requiring Int rather than Int64; the call was corrected.

Focused build result and review findings are recorded in the DEE-17 section of [acceptance notes](ACCEPTANCE.md). Compilation does not establish native interaction acceptance. This issue must remain open until the relevant manual checks are accepted.
