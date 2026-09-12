# Pin Jury

Pin Jury helps decide whether a frequently used app should replace an existing pin
when a display's dock is crowded. It uses Apple Foundation Models from its first
version, as requested for DEE-39. This supersedes the issue's original heuristics-only
slice. Heuristics qualify the pair; three on-device jurors supply the arguments and votes.

## Open a hearing

Choose **Pin Jury** from DDock's menu, or **Settings → Features → App suggestions →
Open Pin Jury**. Launcher also offers **Dock getting crowded? Ask the Pin Jury**
when the resting dock shrinks icons below the configured size or needs scrolling.
Transient drag insertion gaps do not count. Menu and Settings commands select the
enabled display under the pointer, falling back to the primary enabled display.
The Launcher action uses its own display.

The window shows the incumbent pin and challenger with the exact evidence supplied
to the jurors. **Let the jury discuss** starts generation. Keeper argues for established
habits, Scout considers recent demand, and Steward weighs evidence and uncertainty.
Each speaks once, then responds to earlier arguments and casts a final vote. The
conversation streams into the window. Turn off **Follow live** to read earlier turns.

All six statements must complete with valid ballots. A majority of the three final
ballots recommends either keeping the incumbent or swapping it for the challenger.
**Accept** applies that specific decision. Keeping a pin writes nothing. A swap
replaces one slot in the captured display and Dock Mode, preserving every other pin
and its position. It makes one persistence call and records the edit in Local History.
**Reject** leaves pins unchanged. Accept has no default Return shortcut. Escape stops
generation, rejects a pending recommendation, or closes the window otherwise.

## Evidence and admission rules

App suggestions must already be enabled, unpaused, and able to read its storage.
Pin Jury never enables collection. It reads only real settled activation examples
from that store, including in Debug builds with synthetic experiments selected.
These app-wide observations cover periods when DDock was collecting. They are not
screen time, per-display use, productivity, or a complete system history.

The evidence card includes activations over the preceding 30 days, the subset from
the preceding seven days, distinct local calendar dates used, and calendar days since
the last observed activation. Excluded apps, revoked contexts and future-dated records
are ignored. At most the latest 10,000 retained examples contribute. A rolling 30-day
window can cross 31 local dates. Existing App suggestions retention remains 90 days.

`PinJuryPolicy` assigns each app a score:

```text
30-day activations + 2 × 7-day activations + 2 × active dates
```

The weakest eligible visible app pin competes with the strongest eligible unpinned
app. Candidates come from the known Launcher catalog, running apps, and a Launch
Services lookup of the 50 highest-scoring unpinned app identities in the evidence.
That lookup lets the menu consider recently quit apps before Launcher first opens.
Scores tie by stable application ID. A challenger needs at least six activations,
three active dates, three activations in the last week, and a score advantage of three.
`PinJuryTuning` exposes these four bounded thresholds independently of the model.
The weights and evidence windows are defined in `PinJuryPolicy` and
`LauncherSuggestionsStore.pinJuryEvidence(now:)`.

Finder, DDock, unavailable or quarantined apps, parked magnetic pins, folders, and
hidden pins are excluded. An incumbent needs at least one observed activation.
Missing history does not prove a deliberate pin is unwanted. Insufficient evidence
shows an explanation and leaves the ordinary Pin and Unpin commands available.

## Model and lifecycle boundaries

Each turn uses a fresh `LanguageModelSession` with the same two candidates and all
preceding statements. Prompts request the current locale and treat app names and
earlier generated statements as untrusted data. Only app names and aggregate counts
reach the model. No paths, window contents, raw history, tools or external providers
are attached. The model cannot pin, unpin or launch anything.

Structured generation restricts each ballot to `keep` or `replace`. Partial ballots
never contribute to a verdict. Input and schema token counts reserve room for output;
oversized, refused, malformed, unavailable and unsupported-model responses fail with
an explanation. There is no scripted fallback masquerading as a model conversation.

The pending decision revalidates consent, exclusion epochs, exact ordered pins,
the Dock Mode, app availability and the source display before applying. Changes
invalidate the hearing. Drag, file-picker and menu conflicts block the save. No pin
or magnetic placement changes occur if persistence fails. Cancellation rejects late
callbacks, and a retry waits for the previous request to unwind. Generation has a
three-minute deadline; the whole hearing expires after 15 minutes.

Transcripts and case evidence are memory-only. Close, sleep, session resignation,
display removal and app termination cancel generation and clear them. Resetting,
pausing or disabling App suggestions, or changing exclusions, also clears a hearing.
No extra history file or model transcript is persisted.

## Validation

The Debug `DeeDock` app target compiled on 2026-09-12 with Xcode 27 and
`CODE_SIGNING_ALLOWED=NO`. The build did not run tests or launch the app.

Native acceptance remains pending. Inspect the ordinary and crowded entry points,
live arguments in English and German, cancellation and model-unavailable states,
Accept and Reject, failed persistence, privacy changes and stale decisions. Check
keyboard focus, VoiceOver, reduced motion/transparency, narrow windows, all four dock
edges, multiple displays, Spaces/fullscreen, display removal and sleep/wake.

The view uses native opaque backgrounds and no animated auto-scroll. Preview fixtures
have inert application URLs and start no collection or inference. Focused regression
cases use injected generators and in-memory reviews; they require explicit approval
before execution under the repository's validation policy.
