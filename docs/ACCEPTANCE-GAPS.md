# Acceptance gaps

Status checked on 2026-09-29. This record separates validation of implemented features from unfinished feature tickets.
The detailed scenarios and older evidence remain in [ACCEPTANCE.md](ACCEPTANCE.md).
An issue marked Done does not establish native acceptance.

## Current evidence

Automated checks used source commit `6d397fb` plus the `WindowMarkupTests` corrections below,
Xcode 27.0 `27A266a`, and macOS 27.0 `26A428`. Native checks used the installed
`/Applications/DeeDock.app`, version 0.11.0. These are separate evidence sources.
At validation time, the checkout's version was 0.10.0. The two newer main commits contained
the 0.11.0 release preparation and merge; they were incorporated before committing this record.

| Check | Result | Scope and limits |
| --- | --- | --- |
| `WindowPeekEnlargeTests` and `WindowMarkupTests` | 29 tests passed after correcting two expectations | Settings migration, geometry, hold regions, stow paths, destination choice, document operations, and filenames. Does not prove native pointer handling or file delivery. |
| `DockVisibilityTests`, `WindowPeekTests`, `WindowPeekSplitTests`, and `WindowPortalExportTests` | 25 tests passed | Model and geometry coverage. Does not prove animation quality, OS window behavior, or capture permissions. |
| `DockLocalHistoryTests/replayDwellAndGate()` | Resolved ([DEE-113](https://linear.app/d-zwei/issue/DEE-113)) | The test keeps a 25 ms dwell and suspends until `applyPreview` runs. It no longer treats a 2 s main-actor poll as success. |
| `FolderStackTests/mediaHeaders()` | Failed | WAV duration is still unavailable on this OS build. CoreMedia reports underlying error `-17770`. |
| Installed app and Settings | Opened and inspected | German Settings lists the built-in display and two external displays. This does not prove unplug, replug, scaling, or rearrangement behavior. |
| Launcher close and reopen | Passed in the current browse layout on one dock | The accessibility scroll value remained `0.4845446950710108` across Back to Dock and reopen. |
| Launcher empty search and reset | Passed | A unique nonmatching query displayed zero results. Clear restored 73 apps and scroll value `0`. |
| Enlarged Peek Save to Shelf | Passed, user-reported | The preview stayed open through the flight, the image landed in Shelf, and Peek closed automatically about 1–1.5 seconds later. Timing is an estimate. This confirms the exercised configuration, not every edge or display. |
| Peek pointer-exit dismissal | Passed, user-reported | The user separately confirmed that Peek dismisses when the pointer moves away, in the exercised configuration. |

The markup tests previously assumed that stroke width scaled linearly even below its readability floor,
and that a small capture opened a minimum-width panel. The implementation instead preserves readable
small marks and sizes the panel by picture aspect ratio and screen space. The corrected tests check
proportional scaling above the floor, readable small marks, equal frames for equal aspect ratios,
screen containment, minimum dimensions, and centering. Production behavior did not change.

The final focused results cover 56 distinct tests: 55 passed and one failed. This is not a full-suite run.
Individual Swift Testing method filters require parentheses; the first attempt without them selected
only the two whole suites. The separate recorded-failures run selected and executed both methods.

Local evidence files:

- `/tmp/dokk-peek-acceptance-20260929.log` and `.xcresult`: initial two markup failures.
- `/tmp/dokk-focused-acceptance-20260929.log` and `.xcresult`: corrected 29-test run.
- `/tmp/dokk-recorded-failures-20260929.log` and `.xcresult`: audio failure and pin-replay pass.
- `/tmp/dokk-peek-visibility-20260929.log` and `.xcresult`: 25 model and geometry tests.
- Derived data: `/tmp/dokk-acceptance-20260929`.

These temporary artifacts are local and may be removed by the OS. The results above are the durable record.
All runs used the `DeeDock` scheme, Debug configuration, and `platform=macOS` destination.
The first two used `test`; subsequent runs used `test-without-building` against the same derived data.

## Remaining native acceptance

These groups remain open. Passing model tests closes only the matching automated checks.

| Group | Remaining evidence |
| --- | --- |
| Enlarged Peek, markup, and Save to Shelf | Corridor boundaries, drawing, save/share dialogs, Finder export, failure cleanup, all dock edges, and secondary-display placement. Save-to-Shelf delivery, retention through landing, and pointer-exit dismissal passed in the user's exercised configuration; its auto-hide setting was not recorded. See [markup scenarios](WINDOW-MARKUP.md#pending-native-acceptance). |
| Core dock, settings, and displays | Hover focus and click passthrough, keyboard focus restoration, overflow, drag and drop, independent display overrides, unplug/replug, mirroring, negative origins, mixed scale, Spaces, full screen, Mission Control, and sleep/wake. |
| Launcher | Other browse layouts and groupings, favorites, Escape and outside-click dismissal, keyboard selection after reopening, independent offsets on two displays, suggestions, and file-action delivery. |
| Window integrations | Exact-window actions, permission loss, stale captures, file handoff, live portals, watch completion and cancellation, window search, OCR history, and App Fusion. |
| Files and local history | Shelf and Compost restoration, folder details and cloud placeholders, Clipboard Museum, Capsules, timeline replay, badge history, recipes, and Shortcut actions. |
| Appearance and accessibility | VoiceOver operation, Reduce Motion and Reduce Transparency in native windows, light/dark contrast, magnification, launch animations, indicators, and Atmosphere. |
| Onboarding and updates | First-launch paths, login-item behavior, update discovery, idle-install gates, and relaunch. Release publishing remains Esi's responsibility. |
| macOS Dock tuck-away | The user's manual `defaults` probe passed before implementation. The built switch still needs Settings and tour use, quit/relaunch, update relaunch, logout/login, force quit, edge following, and badge recovery after Dock restarts. See [checklist](ACCEPTANCE.md#tuck-away-hands-on-acceptance). |
| Resource use and teardown | Measured idle CPU and memory, capture shutdown, observer and task cleanup, and repeated lifecycle transitions. No performance acceptance was established by these tests. |

The native UI tool can inspect and click Settings and Launcher controls. Opening DOKK's application
menu repeatedly timed out, and the tool has no documented hover action. The user invoked Focus Dock,
but subsequent tool observations and key input did not establish retained keyboard selection.
Keyboard Peek and pointer acceptance therefore remain unverified, not failed product behavior.
The user completed the enlarged-Peek and Save-to-Shelf check: the preview stayed open through
the flight, the image landed in Shelf, and Peek closed automatically about 1–1.5 seconds later.
The user separately confirmed that Peek dismisses when the pointer moves away.
These are user-reported acceptance results, not agent-observed or instrumented results.

## Open tickets outside shipped-feature acceptance

Read-only reconciliation against Linear descriptions and comments on 2026-09-29:

| Ticket | Evidence | Disposition |
| --- | --- | --- |
| [DEE-7](https://linear.app/d-zwei/issue/DEE-7) window groups | Implementation was reported on a separate branch; linked PR 10 remains open. No window-group implementation was found in this checkout. | Unmerged feature work, not a shipped-feature validation gap. |
| [DEE-38](https://linear.app/d-zwei/issue/DEE-38) comic notes | [Template](releases/COMIC-TEMPLATE.md), [release example](releases/0.5.0-comic.md), renderer, and process documentation exist. | Artifact requirements exist. Explicit Esi tone/format sign-off was not found in the inspected issue discussion; leave closure open. |
| [DEE-40](https://linear.app/d-zwei/issue/DEE-40) App Divorce Court | September 13 owner comment keeps it for local experiments, outside production toward 1.0. | Excluded from this acceptance pass. |
| [DEE-53](https://linear.app/d-zwei/issue/DEE-53) calendar cues | In Progress; no EventKit implementation found in current app sources. | Planned feature, not verified as shipped. |
| [DEE-60](https://linear.app/d-zwei/issue/DEE-60) flag badges | In Progress; no matching flag-status implementation found in current app sources. | Planned feature, not verified as shipped. |
| [DEE-61](https://linear.app/d-zwei/issue/DEE-61) configurable digest | Existing badge digest does not establish the requested frequency, verbosity, and section controls. | Feature scope remains open. |

No Linear status or GitHub issue was changed. Deprecated personality features and withdrawn Metal
indicators do not need acceptance as enabled production features; their disabled-on-launch and
migration behavior still matters.

## Confirmed follow-up for the stability pass

- WAV duration loading still fails on this macOS build. Investigate the reader and platform fallback without hiding the failing expectation.
- Pin-replay timing was a historical intermittent failure. [DEE-113](https://linear.app/d-zwei/issue/DEE-113) resumes `replayDwellAndGate()` from `applyPreview` instead of a wall-clock poll.

The broader stability pass has not started. Native acceptance remains open as listed above.
