# Launcher app suggestions

App suggestions are off by default. **Settings → Features → App suggestions** controls the feature for every display.
When enabled, DDock learns from application activity observed while it runs. It does not import earlier Launcher history.

## Temporary engine comparison

The **Development** card in App suggestions selects **Weighted baseline** or **Core ML nearest neighbors**.
Core ML is the default. The temporary engine selector is compiled only into Debug builds.
Release always uses Core ML and ignores developer overrides. Legacy engine values in shared consent preferences are ignored;
an explicit Debug selection is stored separately without changing consent or history.
Switching keeps the same local history, feedback, exclusions, and consent. It cancels outstanding predictions and clears the cached model.
The next Launcher presentation uses the selected engine. This control is intended for development comparison and will be removed after an engine is chosen.

Core ML uses an updatable nearest-neighbor classifier trained on the retained app transitions.
The first prediction trains it locally; later predictions reuse the completed model until its training examples change.
Training runs off the UI actor, in batches of at most 256 examples, with a 10,000-example cap and a 30-second overall deadline.
Launcher and Settings show a preparing state during that work. Empty history needs no training and produces no suggestions.
If Core ML fails, an unavailable message appears. It does not silently use the baseline; ordinary Launcher results remain available.

Both engines use the same explicit feedback and exclusion rules. Core ML class votes receive a mean age adjustment for each app,
then the shared normalization, recent-use bonus, running-app bonus, and contextual feedback adjustment.
The age adjustment uses the same 21-day decay scale as the baseline, but does not weight individual neighbors by age.
This difference matters when comparing predictions.

## Evidence requirements

Both engines abstain when the evidence is too thin. The default requirements are:

- At least 30 retained, qualified training examples overall.
- At least three supporting examples among the 15 nearest examples.
- Supporting examples on at least two distinct UTC dates.
- At least 60% of reconstructed neighbor weight supporting the candidate within the distance limit.
- A nearest supporting example within squared feature distance 2.0.

Support uses the same context features as Core ML: time, weekday, preceding foreground app,
recent app sequence, running apps, and Dock Mode. Distance is squared Euclidean distance over
the 256 Float32 features. Reconstruction uses `1 / max(distance, 0.000001)` as the weight.
The denominator includes all selected neighbors; support counts only neighbors within the distance limit.
Equal distances are ordered by newest date, then persistent example identity. Target identity never selects the evidence neighborhood.
These reconstructed neighbors are explicit evidence for the shared gates, not internal records exported by Core ML.

A candidate must also have positive raw engine evidence and a positive final ranking score.
Feedback and recency bonuses cannot create evidence or bypass a gate. Every displayed candidate must qualify separately.
The 60% default permits at most one qualifying candidate. Lower agreement thresholds can permit more.
The two-date requirement can reject a pattern when its nearest examples all come from today, even if older history exists.
These defaults favor abstention and are experimental; they do not guarantee a useful first suggestion.

## Debug tuning and inspector

Debug builds add bounded evidence controls and an inspector to App suggestions settings.
Release builds use the model-owned defaults and ignore saved Debug tuning values.
The engine selector is also Debug-only. Release has no developer engine, tuning, inspector, or synthetic controls.

The inspector freezes an actual Launcher request, including its context, history, feedback, exclusions, and evaluation time.
**Capture latest request** replaces it with the newest captured request. **Replay both engines** applies the current tuning
to that same frozen input using a separate Core ML instance. Replay never records app activity, feedback, or impressions.
Controls are also available inside the inspector so tuning and comparison can happen without closing it.

Summary shows both engines side by side. Candidate details separate raw scores, age factors, normalization,
recent-use and running bonuses, contextual feedback, final scores, and the exact failed gates.
Neighbors are labeled as reconstructed evidence; History shows the qualified transitions and their preceding context.
Model diagnostics separate preparation time, inference time, and total evaluation time. Preparation includes any model load,
rebuild, or wait for shared training. The inspector also shows cache reuse and the model's effective neighbor count when available.
None of these scores is a calibrated probability of correctness.

Changing a display threshold affects the next prediction without rebuilding the model.
Changing the neighbor count recreates the cached model with Core ML's runtime parameter override.
Closing the inspector cancels its replay. Reset, pause, disable, exclusion changes, and expiry also discard frozen diagnostics.
Debug tuning survives a history reset; **Restore defaults** resets only the tuning controls.
No inspector, diagnostic history capture, or tuning controls are compiled into Release builds.

## Synthetic scenarios in Debug builds

Open the inspector and select **Synthetic scenario**. This mode works while real app suggestions are off.
It generates fictional app identities entirely in memory and uses an independent model. It does not inject
examples into the actual Launcher, write your history file, enable recording, or change consent.

Choose one of six scenarios:

| Scenario | Generated behavior |
| --- | --- |
| Cold start | Starts with five examples by default; the count remains adjustable. |
| Clear routine | Repeats a dominant outcome across the configured days. |
| One-day burst | Compresses historical examples into one UTC date. |
| Conflicting routines | Distributes pattern-following outcomes among three apps. |
| Changed habits | Historical outcomes favor Terminal; future outcomes favor Browser. |
| Unfamiliar context | Queries use a different foreground app, mode, recent sequence, and running set. |

Controls set the example count, history span, pattern strength, context noise, random seed, and reference date.
The reference date uses UTC. Generation is reproducible, including example identities: the same settings and
seed produce the same history, contexts, and future outcomes. Strength affects outcome selection; noise
independently perturbs context. No generated target is encoded into its preceding context.
History is capped at 1,000 examples, and every scenario has 60 future outcomes, scheduled four per day.

Editing these controls changes a draft. Select **Generate scenario** to replace the generated dataset.
**Replay both engines** evaluates the current frozen query and history without learning an outcome.
Use the existing Summary, Candidates, Neighbors, and History tabs to inspect the results and tune the gates.

**Step next outcome** predicts first, reveals the generated target, then adds that outcome to the isolated
history. **Run remaining outcomes** repeats that sequence to the end. Results and the History tab show the
input *before* the latest outcome was learned. **Stop** cancels pending work and preserves completed steps.
The shared source switch cancels work too. Restart returns to the originally generated history and clock.
Changing tuning resets chronological playback and its metrics while keeping the frozen input available for Replay.

The simulated-clock buttons advance time without changing existing history dates or identities. Remaining
future events shift by the same interval, preserving their spacing. This lets decay and expiry be inspected
without accidentally converting the remaining daily routine into a burst. Synthetic replay does not run
maintenance against real history, and its simulated date is independent of the computer's clock.

Playback reports separate values for each engine:

- Attempts and model failures.
- Offers: successful predictions with at least one eligible suggestion.
- Hits: offered sets whose first three suggestions contain the generated next app.
- Coverage: offers divided by successful predictions, excluding failures.
- Hit rate: hits divided by offers; unavailable until at least one offer exists.
- First changed-pattern hit: steps after the generated habit change until a suggestion contains the new
  dominant outcome on an occasion where it actually occurs. A hit on a noisy old outcome does not count.

A first changed-pattern hit does not prove stable adaptation. All measurements describe the selected
synthetic scenario; they do not establish accuracy or usefulness on real habits. No scenario data is saved
or exported, and the generator, session, controls, and playback metrics are compiled only into Debug builds.

## Launcher behavior

An empty query can show a **Suggested** section below the search controls and above ordinary app results.
Grid layout shows up to three apps in one row, reducing the count for narrow windows. List layout shows up to three rows.
An app can appear in both Suggested and ordinary results. Each occurrence has a separate selection identity.
Arrow keys move through both sections, and Return opens or activates the selected app through the existing application service.

Suggestions respect the Launcher filters and the current display's hidden app groups.
DDock, the app that was foreground before Launcher opened, excluded apps, helpers, and unavailable apps are ineligible.
Typing a query uses ordinary search. Suggestions do not replace Ask Robi or use Apple Intelligence.

Ranking stays fixed while Launcher is open. Filters and availability can remove candidates without reordering the snapshot.
Excluding an app removes its suggestion immediately. If a selected suggestion disappears, Return does nothing until another selection is made.
New observations affect the next presentation. History below the evidence requirements produces no suggestions. Learning does not require waiting 90 days.

## Feedback and controls

Each suggestion has contextual menu and accessibility actions:

- **Useful suggestion** reinforces the app for the original foreground, Dock Mode, weekday, and three-hour time band.
- **Not useful right now** reduces the score in that context. It does not permanently exclude the app.
- **Never suggest this app** excludes the app immediately. Settings can reverse the exclusion. Previously removed learning does not return.

Ignoring a suggestion is not negative feedback. Actual foreground transitions teach the predictor regardless of which app launched or activated the target.

An optional inline question appears after at least seven days and ten suggestion presentations.
Answering or dismissing it suppresses the question for 30 days. **Don't ask again** turns off these prompts in Settings.
Section-level answers are aggregate feedback. They do not assign a negative label to every suggested app.

Pause and disable stop observation, predictions, and pending ranking work immediately. Existing history remains subject to expiry.
**Reset learned suggestions** removes behavioral history, soft feedback, impressions, and pending results.
Reset preserves deliberate exclusions, the feedback-prompt preference, and the engine choice. It also discards the personalized Core ML cache.

## Local data and limits

One recorder receives application-wide Workspace notifications. The history stores bundle identifiers, event times, foreground and recent apps,
running-app identifiers, recency metadata, local hour and weekday, and the Dock Mode identifier.
It also stores suggestion impressions and explicit feedback with the original context and predictor version.
It stores no document names, paths, URLs, titles, images, keystrokes, or app content. The feature has no upload, account, or sync service.

Only an activation sustained for three seconds becomes a training target. Launch and termination events supply context.
The first five seconds of an observation session do not create targets. Startup snapshots cannot reconstruct missing activity.
Closing an application window is not a termination, and one process ending does not imply the app's last instance quit.
Apps without bundle identifiers are omitted to avoid storing their filesystem paths as identities.

Sleep, screen sleep, user-session switching, idle readings of at least five minutes, and observed clock gaps end sessions.
Clock rollback and timezone changes discard transient context. Public session notifications do not guarantee an exact screen-lock boundary.
The recorder omits foreground duration because these signals cannot establish active use through every lock state.
Invalid idle readings end the session. The feature does not request Accessibility or Input Monitoring access.

Behavioral records expire after 90 days. Cleanup runs before predictions, on startup, and once a minute while DDock runs, including while disabled.
Predictions rebuild scores from eligible examples, so no separate aggregate can retain expired learning.
Core ML rebuilds from the remaining examples after removal or expiry; a model from an older privacy generation cannot publish predictions.
Safety caps retain at most 20,000 events, 10,000 examples, 2,000 app feedback records, and 2,000 impressions.
The atomic history file is limited to 16 MiB. When it exceeds that limit, the newest half of each collection is retained until it fits.
These limits can shorten the retained history on busy installations. Exclusions and consent are separate preferences and do not expire.

History lives in `~/Library/Application Support/DDock/LauncherSuggestions/history-v1.json`, with private filesystem permissions and exclusion from system backup.
Unreadable or unsupported storage stops the feature and leaves normal Launcher use available. Reset is the explicit recovery action.
No detailed behavioral history is added to general logs or exported diagnostics.

Core ML uses private temporary directories during training and removes them on completion, cancellation, or failure.
The completed model is cached in memory. Startup and privacy cleanup remove abandoned training directories belonging to exited processes,
while leaving another live process's files alone. The packaged model contains no personal examples.

## Predictor and validation

The baseline predictor combines decayed frequency, transitions, time, weekday, Dock Mode, recent apps, and recency.
Recent examples receive more weight, using a 21-day decay scale. Feedback adjusts normalized scores for matching contexts.
These constants are tuning defaults, not measured optima.

The [model decision and measurements](LAUNCHER-SUGGESTIONS-MODEL.md) describe the Core ML feasibility prototype and chronological synthetic comparison.
The [acceptance record](ACCEPTANCE.md#dee-26-app-suggestions) separates compilation and focused tests from native scenarios that remain unverified.
