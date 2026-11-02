# App Health

App Health records how running apps use CPU, memory, wake-ups, and energy, and lets the person
label moments when an app misbehaves. The goal is a local training set for a future Create ML
`TimeSeriesClassifier` that tells misbehaving apps (a spin, a memory leak, a wake-up storm, a hang)
apart from legitimately busy ones (a build, an export, indexing).

App Health ships no model, no alerts, no hang badge, and no upload. It is off by default. The German
name is "App-Monitor". Code uses the `AppHealth` prefix; the feature lives in `DeeDock/AppHealth`.

## Turn it on

**Settings → Dock Extras → App Health** (under the sidebar's Features heading) holds:

- **Collect app health data**: starts and stops the collector.
- **Labelling mode**: lets DOKK ask about busy apps now and then. Disabled while collection is off.
  Turning collection off makes labelling inert; the labelling switch keeps its value.
- **Labelling paused until tomorrow — Resume**, after "Pause labelling for today".
- **Stored data**: total size and first day ("2.4 MB · since 30 Oct"), or "No data yet".
- **Export data…** (a `.zip` through a save panel) and **Delete all data** (with confirmation).
  Deleting keeps collection running if it is on. An open question closes as interrupted, the
  in-memory history is dropped, and sampling restarts from a baseline: the new file begins with
  `collectorStart` (`enabled`).
- What is recorded, in plain words.
- **Not asked about**: apps on the "Don't ask" list, each with a button to ask about it again.

Both switches persist as JSON under the `UserDefaults` key `appHealth.settings.v1`
(`{"collecting": false, "labelling": false}`). The "Don't ask" list and the pause persist under
`appHealth.prompts.v1`, together with the prompt policy's own state.

## What is recorded

Every 20 seconds, per running app with a bundle identifier (DOKK included, so its own cost shows up
in the data):

- CPU time of the main process and of attributed helpers.
- Memory footprint (what Activity Monitor shows as Memory).
- Idle wake-ups (Activity Monitor's "Idle Wake Ups").
- Energy, where the kernel reports it.
- Whether the app responds, only if Accessibility is already allowed for DOKK.
- Which app is in front, and how long since the last keyboard, mouse, or trackpad input.

Also recorded: app launches and terminations, sleep and wake, display sleep, session switches,
power source, thermal state, and the person's labels.

App identity is the bundle identifier only. App Health never stores window titles, file names or
paths, executable paths, or any content. Executable paths and bundle paths are used in memory for
attribution and the crash-report lookup, and never written or logged.

## Files

Records live in `~/Library/Application Support/DOKK/AppHealth/`. The folder is created with
permissions 0700 and excluded from backups. Each local calendar day gets one file,
`app-health-YYYY-MM-DD.jsonl`, created with permissions 0600. A time-zone change can make two days
share a file; `ts` in every record is absolute, so nothing is lost. **Show in Finder**, at the end of the
privacy note in Settings, opens the folder once it holds data.

Each line is one JSON object (JSON Lines), schema version 1. Every record has:

| Field | Meaning |
| --- | --- |
| `v` | Schema version, `1` |
| `type` | `tick`, `sample`, `event`, `prompt`, or `label` |
| `ts` | Unix time in seconds, millisecond precision |

Optional fields are omitted when they have no value. CPU and interval values are rounded to
milliseconds, percentages and rates to one decimal. Memory and energy are whole bytes and
nanojoules.

### `tick`

One per written tick: the context shared by that tick's `sample` rows.

| Field | Meaning |
| --- | --- |
| `interval` | Seconds actually elapsed since the previous tick |
| `frontmost` | Frontmost app's bundle identifier; omitted when none |
| `idle` | Whole seconds since the last input event in this login session |
| `power` | `ac`, `battery`, `ups`, or `unknown` |
| `thermal` | `nominal`, `fair`, `serious`, or `critical` |
| `apps` | Watched apps this tick |
| `written` | `sample` rows this tick wrote |
| `costMs` | Thread CPU time the sampler spent in libproc this tick |
| `ax` | Accessibility was already allowed, so responsiveness checks ran |

### `sample`

One app over one tick.

| Field | Meaning |
| --- | --- |
| `app` | Bundle identifier |
| `kind` | `regular`, `accessory`, or `background` (from the activation policy) |
| `interval` | Seconds the values cover |
| `cpu`, `cpuMain`, `cpuHelpers` | CPU time in core-seconds: total, main process, attributed helpers |
| `cpuPct` | `cpu / interval × 100`; 100 is one core fully busy |
| `mem`, `memMain` | Memory footprint in bytes: all attributed processes, main process |
| `procs` | Attributed processes, main included |
| `wakeups`, `wakeupsPerSec` | Package idle wake-ups over the interval, and per second |
| `energy` | Nanojoules over the interval; omitted when the kernel reports none |
| `load` | `main` (main ≥ helpers), `helpers` (helpers > main), or `none` (no CPU) |
| `frontmost` | The app was in front |
| `hang`, `hangMs` | Responsiveness check `ok`, `timeout`, or `error`, and its latency; omitted when not checked |
| `why` | `active`, `baseline`, `growth`, or `backfill` (see [Write rules](#write-rules)) |

### `event`

| `event` | Extra fields |
| --- | --- |
| `launched` | `app`, `kind` |
| `terminated` | `app`, `kind`, `runSeconds`, `heavyBefore`, `hangFailing`, `frontmostRecently`, `crashReport` |
| `sleep`, `wake`, `displaySleep`, `displayWake`, `sessionInactive`, `sessionActive` | none |
| `power` | `power` |
| `thermal` | `thermal` |
| `collectorStart`, `collectorStop` | `reason`: `enabled`, `disabled`, `sleep`, `displaySleep`, `session`, `quit` |
| `dontAsk`, `allowAsk` | `app` |
| `pauseToday`, `resume` | none |

`collectorStart` and `collectorStop` mark every transition of the sampling loop. `enabled` is also
used when DOKK launches with collection on.

For `terminated`:

- `runSeconds`: seconds since launch, when macOS reported a launch date.
- `heavyBefore`: mean CPU of at least 50 % over the last two minutes of in-memory history.
- `hangFailing`: the app's last responsiveness check timed out.
- `frontmostRecently`: the app was in front in a tick of the last two minutes.
- `crashReport`: an `.ips` crash report for the app appeared (see below). Omitted when the lookup
  could not finish because collection stopped.

The event is written after the crash-report lookup, about five seconds later, with `ts` set to the
termination. Files are therefore not strictly sorted by `ts`.

### `prompt`

Written when a labelling prompt appears, or when the person picks an app from the menu bar.

| Field | Meaning |
| --- | --- |
| `id` | UUID, shared with the matching `label` |
| `app`, `kind` | The app |
| `trigger` | `rule`, `ordinary`, or `manual` |
| `reasons` | Suspicion flags that held: `cpu`, `background`, `idleUser`, `memory`, `wakeups`, `hang`. Empty for `ordinary` and `manual` |
| `anchor` | Where the prompt attached: `tile`, `dock`, or `screen` |

### `label`

| Field | Meaning |
| --- | --- |
| `id` | The prompt's `id` |
| `app` | Bundle identifier |
| `answer` | `expected`, `misbehaving`, `notSure`, or `noAnswer` |
| `detail` | After Misbehaving: `spinning`, `memoryGrowing`, `frozen`, or `drainingBattery`; omitted otherwise |
| `from`, `to` | The labelled window, Unix seconds |
| `source` | `prompt` or `manual` |
| `responseSeconds` | Seconds from the prompt appearing to the answer |
| `dismissed` | The person closed the prompt |
| `interrupted` | Sleep, turning collection off, or quitting closed the prompt |

## Signals

**Process list and attribution.** Each tick lists every process (`proc_listallpids`) and reads its
owner and parent (`proc_pidinfo(PROC_PIDTBSDINFO)`). Other users' processes are skipped. An app's
main process counts as `main`. Any process whose parent chain reaches a main process is a helper of
that app. When the chain reaches launchd (pid 1) or a process outside the table, the executable
path (`proc_pidpath`) is compared with the running apps' bundle paths; a path inside a bundle makes
the process a helper of that app, the longest bundle path winning. Paths are read at most once per
process lifetime and stay inside the sampler. Unattributed processes are ignored.

**CPU, memory, wake-ups, energy.** `proc_pid_rusage(RUSAGE_INFO_V6)` per attributed process:
`ri_user_time + ri_system_time` (CPU), `ri_phys_footprint` (memory footprint),
`ri_pkg_idle_wkups` (idle wake-ups), `ri_energy_nj` (energy). The time fields are mach absolute
time units, converted with `mach_timebase_info` once (125/3 on Apple Silicon). Counters are
cumulative; a tick records the difference from the previous tick for the same process instance
(pid plus `ri_proc_start_abstime`). A process first seen this tick that started after the previous
tick contributes everything it accumulated; one that started earlier only sets its baseline. A
counter that moves backwards contributes zero. An app's energy is omitted when none of its
processes reports a non-zero value.

**Responsiveness.** Only when `AXIsProcessTrusted()` is already true; App Health never asks for
Accessibility. Up to four regular apps per tick are checked: the frontmost app, apps at 50 % CPU or
more, and apps whose last check timed out. A check asks the app's Accessibility element for its
role with a 0.5 s messaging timeout: `ok`, `timeout` (`kAXErrorCannotComplete`), or `error` (any
other failure, such as an app without an Accessibility tree). Checks run one at a time on a
dedicated utility queue.

**Crash reports.** Five seconds after a termination, App Health lists
`~/Library/Logs/DiagnosticReports` for `.ips` files whose name starts with the app's executable
name and a hyphen and whose modification date is no more than ten seconds before the termination.
Only the yes/no answer is kept.

**Idle, power, thermal.** Idle time is
`CGEventSource.secondsSinceLastEventType(.combinedSessionState, …)` for any input event. The power
source comes from `IOPSGetProvidingPowerSourceType`, updated by an IOKit run-loop notification. The
thermal state comes from `ProcessInfo`, updated by its notification. Changes write `power` and
`thermal` events.

## Write rules

Every app is sampled every tick and kept in memory. Rows are written selectively so 30 days fit
under 50 MB:

- `active`: CPU at 2 % or more, 20 or more idle wake-ups per second, or a responsiveness check that
  was not `ok`; and the next three quiet ticks, so each busy series has a tail.
- `growth`: the memory footprint changed by 50 MB or more, in either direction, since the app's last
  written row.
- `baseline`: an app's first sample, then every 30 minutes if nothing else wrote a row for it.
- `backfill`: when a prompt is shown or a manual label is given, every in-memory tick of that app in
  the label window that is not on disk yet. A labelled window is therefore always complete.

The in-memory history keeps the last ten minutes (30 ticks) per app, with whether each tick is on
disk. An app's history is dropped once its termination event is written. Ticks from a new instance
that launched in the meantime stay.

## Labelling

### Suspicion rule

Evaluated after every written tick per app over the in-memory history, only while labelling is
active and only when the caps below allow a prompt at all. DOKK itself and apps on the "Don't ask"
list are never evaluated. The thresholds live in one place,
`AppHealthSuspicionRule.Thresholds`.

| Flag | Holds when |
| --- | --- |
| `cpu` | Mean CPU of at least 80 % over the last 3 minutes (9 ticks, all present) |
| `background` | The app was not in front in any of those ticks |
| `idleUser` | No input for at least 180 seconds now |
| `memory` | Footprint now at least 1.3 × the footprint 10 minutes ago and at least 400 MB (decimal) more, with at least 80 % of tick-to-tick steps not decreasing |
| `wakeups` | Mean of at least 400 idle wake-ups per second over 3 minutes, and `background` |
| `hang` | The last two responsiveness checks timed out, the latest one in this tick |

"All present" means consecutive ticks no more than 30 seconds apart; a window with a missing tick
(the app was not running, or sampling paused) does not count. The 10-minute window is the whole
history of 30 consecutive ticks, and "10 minutes ago" is its oldest tick.

An app is suspicious on a spin (`cpu` and either `background` or `idleUser`), `memory`, `wakeups`,
or `hang`. The prompt's `reasons` lists every flag that held, `background` and `idleUser` included,
in the order of the table. When several apps are suspicious in one tick, the one with more flags is
asked about, then the one with more CPU.

### Ordinary heavy use

About a quarter of prompts ask about apps that are busy but not suspicious, so the data also holds
legitimately busy examples. A candidate has a mean CPU of at least 40 % over the last 3 minutes and
is not suspicious. The last 100 shown `rule` and `ordinary` prompts are remembered. An ordinary
prompt is allowed only while `ordinary < 0.25 × (rule + ordinary + 1)`, and then picked with
probability 1/3 per eligible tick. A suspicious candidate always wins over an ordinary one in the
same tick.

### Caps

- At most 8 prompts per rolling hour, and at most 1 per app per 20 minutes.
- One prompt visible at a time; none while the manual picker is open.
- "Don't ask about this app" adds the app to a persisted list (event `dontAsk`). Settings can remove
  it again (event `allowAsk`).
- "Pause labelling for today" silences prompts until the next local midnight (event `pauseToday`).
  Settings can resume early (event `resume`).
- Manual labels bypass every cap and do not count toward any.

Prompt times, the last prompt per app, and the triggers of the last 100 prompts persist under
`appHealth.prompts.v1` (`promptHistory`), so the caps survive a relaunch. Entries dated after the
current time (a clock set back) are ignored.

### Label window

A label covers `from = prompt shown − 5 minutes` to `to = prompt shown`. For a manual label, `to` is
the moment the person picked the app. Sample rows for that window are backfilled when the prompt
appears or the app is picked.

Each prompt writes exactly one label:

| What happened | `answer` | `detail` | Flags |
| --- | --- | --- | --- |
| Expected or Not sure | `expected`, `notSure` | none | |
| Misbehaving, then a detail | `misbehaving` | the detail | |
| Misbehaving, then Skip, close, Escape, or 20 seconds without a choice | `misbehaving` | none | |
| 60 seconds without an answer | `noAnswer` | none | |
| Close button, Escape, or a "…" menu command before answering | `noAnswer` | none | `dismissed` |
| Sleep, display sleep, an inactive session, a switch turned off, or quit | what was known: `noAnswer`, or `misbehaving` in the follow-up | none | `interrupted` |

The 60-second countdown pauses while the pointer is over the prompt or the prompt has keyboard
focus, and continues with the time that was left. The 20-second follow-up timer does not pause.
`responseSeconds` runs from the prompt appearing to the first answer, so a Misbehaving label with a
detail counts the click on Misbehaving. After an answer, a short "Thanks, noted." shows for about a
second before the prompt goes away. Turning labelling off closes an open prompt the same way as
turning collection off.

### Prompt

The prompt shows the app's icon and name as macOS reports them, "Is <App> behaving as expected?",
and one reason line with the measured numbers. With several flags, the line shows the first of:
`hang` ("Didn't respond to a check"), a spin ("Using 140% CPU for 3 minutes in the background", or
"… while you were away"), `memory` ("Memory grew 1.2 GB in 10 minutes"), `wakeups` ("Waking the Mac
600 times a second"). Ordinary prompts say "Busy for a few minutes". The buttons are Expected,
Misbehaving, and Not sure, in one shared style so none is suggested. After Misbehaving come
Spinning, Memory growing, Frozen, Draining battery, and Skip. A "…" menu holds Don't Ask About This
App and Pause Labelling for Today; the close button and Escape dismiss. A thin ring around the
close button empties as the time runs out and stops while the pointer is over the prompt.

The prompt is a borderless, non-activating panel at pop-up-menu level, on every Space like the
dock popovers. Showing it never activates DOKK and never makes it key, and clicking elsewhere does
not close it. It attaches to the app's tile on a fully shown dock, else to the primary display's
dock, else to the lower-right corner of the main screen, and follows display changes. Hidden
auto-hide docks are never used as anchors. It is independent of folder stacks and other dock
popovers: neither closes the other.

A click inside the prompt gives it keyboard focus, without activating DOKK. Then Tab, Shift-Tab, and
the arrow keys move a highlight through the buttons, Return or Space activates it, and Escape
dismisses. VoiceOver announces each new prompt without moving focus, and every control has a label
and a hint. With Reduce Motion the prompt fades in and out without sliding; with Reduce
Transparency its background is opaque.

### Something's off right now…

While labelling is active, the menu-bar menu has **Something's Off Right Now…**. It opens a small
panel near the top of the display under the pointer, listing the apps of the latest tick by CPU
use, with icon, name, CPU, and memory: the busiest ten, then **Show all**. Typing filters by name.
The arrow keys move through the list, Return picks, and Escape closes without writing anything.
Opening it is a deliberate action, so it takes keyboard focus; DOKK hands focus back to the previous
app when it closes, and it closes when focus moves to another window.

Picking an app writes its `prompt` (`trigger: manual`, `anchor: screen`) and backfills the five
minutes before the pick, then shows the same choices as a prompt, without the countdown or the "…"
menu. Closing the picker after picking an app writes `noAnswer` with `dismissed: true`; sleep or a
switch turned off writes it as `interrupted`. Manual labels bypass the caps.

## Lifecycle

The collector runs while collection is on and none of these hold: the Mac is asleep, the displays
are asleep, or the login session is inactive (fast user switching). Each pause writes its event and
`collectorStop`; each resume writes its event and `collectorStart`. A display waking does not
resume sampling while the Mac sleeps or the session is inactive.

The first tick after any start or resume only re-establishes counter baselines and writes nothing,
since deltas across a pause mean nothing.

Turning collection off, quitting, and every pause:

- cancel the sampling loop and any responsiveness checks it is waiting on;
- cancel pending crash-report lookups and write their `terminated` events without `crashReport`;
- close an open prompt, which writes `noAnswer` with `interrupted: true`;
- turning collection off and quitting also remove every observer.

At quit, DOKK waits up to one second for these final records to reach the disk.

## Export

**Export data…** writes a `.zip` (default name `DOKK App Health YYYY-MM-DD.zip`) containing a
`DOKK App Health` folder with every `.jsonl` file and `manifest.json`:

| Field | Meaning |
| --- | --- |
| `schema` | Record schema version |
| `exportedAt` | Unix seconds |
| `dokkVersion` | Version and build, such as `0.24.3 (74)` |
| `files` | The `.jsonl` file names, oldest first |
| `sampleInterval` | Seconds between ticks (20) |

The archive is built with `NSFileCoordinator`'s `.forUploading` reading option, which zips a folder
through public API. All of it runs off the main actor.

## Retention

When the store opens, after each daily rotation, and whenever the tracked total passes the cap:

1. Files dated more than 30 days before today are deleted.
2. While the total exceeds 50 MB (decimal megabytes), the oldest remaining file is deleted.

Today's file is never deleted. If today's file alone reaches 50 MB, appending stops until the next
day and a log message records it.

## Analytics

Counts only; never an app's identity, an answer, or a reason. A prompt closed by sleep, a switch, or
quitting counts as neither answered nor ignored, and a manual pick closed without an answer counts
as nothing. See [ANALYTICS.md](ANALYTICS.md):
`app_health_enabled` and `app_health_labelling` (feature settings), and the `usage_summary`
counters `app_health_prompt_answered`, `app_health_prompt_ignored`, `app_health_manual_label`, and
`app_health_exported`.

## API notes and limits

- `proc_pid_rusage` and `proc_pidinfo` succeed only for processes of the current user (measured:
  532 of 532 same-user processes, no other-user process). Root and other users' processes are not
  sampled.
- `ri_user_time`, `ri_system_time`, and `ri_proc_start_abstime` are mach absolute time, not
  nanoseconds.
- `ri_energy_nj` was populated on the Mac this was built on; a zero value is treated as
  unavailable.
- System-owned helpers that launchd starts on an app's behalf from `/System/…`, such as Safari's
  WebKit `WebContent` processes, are not attributed to the app.
- Responsiveness checks need Accessibility to be allowed already; without it, `hang` is never set
  and `ax` is false.
- A crash report means an unexpected termination. No crash report after heavy use reads as "quit
  shortly after heavy use". A last check that timed out without a crash report suggests a force quit
  of a frozen app. Public API cannot tell a Force Quit (SIGKILL) from a normal quit, so these
  meanings are derived at analysis time and not stored.
- macOS posts no notification for per-process resource use, so the collector uses a 20-second timer
  with 2 seconds of tolerance so the system can coalesce the wake-up.

## Cost

A full pass over all processes (about 860 on the development Mac: process info plus resource usage)
measured about 4 ms of thread CPU, about 0.02 % of one core at a 20-second interval. The budget is
0.1 %. Each `tick` record carries the sampler's own cost in `costMs`, so the real cost can be read
from the data. It has not yet been measured in a long real run.
