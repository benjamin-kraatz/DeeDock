# Launcher suggestion model decision

DEE-26 defaults to Core ML nearest neighbors. A Debug-only selector retains the local frequency, recency, and transition baseline for comparison using the same history. Release always uses Core ML and ignores developer engine overrides. This default is a product decision; the original synthetic comparison established feasibility but did not establish a quality advantage.

## Selectable Core ML engine

Settings stores the engine choice separately from history. Switching cancels prior predictions and discards the model cache without changing consent or recorded examples.
Core ML trains from the bundled empty seed on the first prediction. Changed training examples trigger a full rebuild in batches of at most 256.
Exact snapshot and neighbor-count matching reuses a completed model; simultaneous requests share one rebuild. Training has an overall 30-second deadline and uses at most 10,000 eligible examples.
All model work uses CPU execution off MainActor. Preparing and unavailable states are explicit; failure never substitutes baseline results.

The production encoder uses the fixture's 256 Float32 dimensions. It encodes cyclic hour, weekday, foreground identity, recent identities,
a normalized running-app set, and Dock Mode with stable signed hashing in separate categorical regions. Hash collisions remain possible.
Foreground duration stays unset. The model defaults to 15 nearest neighbors, squared Euclidean distance, inverse-distance voting, and dynamic string app labels. Debug tuning can override the neighbor count from 1 through 100 at model loading and update time.

After prediction, each label's Core ML vote is multiplied by the mean `exp(-ageDays / 21)` of its retained examples.
Both engines then apply the same normalization, recent-use and running bonuses, and contextual feedback. This per-label age correction is not native per-neighbor recency weighting.
Comparisons should account for that distinction. App feedback retains the selected engine's version identifier.

Personalized model files exist only during a rebuild in a private temporary directory. Completion, cancellation, and failure remove the files.
The loaded model remains in memory; runtime tests verify further predictions after its files are removed. Reset, disable, pause, exclusions,
expiry, and engine switching cancel work and discard that cache. Startup and privacy cleanup remove abandoned directories from exited processes.
An empty, reproducibly generated seed is the only model packaged in the app.

## Evidence gates and diagnostics

[Evidence requirements and Debug controls](LAUNCHER-SUGGESTIONS.md#evidence-requirements) describe the implemented defaults.
Both production engines now pass through `LauncherSuggestionEvidence` after scoring. It reconstructs neighbors from the same
Float32 features and applies history, support, distinct UTC date, agreement, distance, and positive-score requirements.
The reconstruction is a separate shared policy. Core ML returns aggregate label votes without neighbor identities or distances;
its equal-distance selection is not asserted to match the diagnostic tie ordering.

The ranking normalization makes the strongest positive score equal to one before bonuses. It cannot measure confidence.
The agreement gate uses reconstructed evidence before any ranking adjustment. Per-candidate diagnostics retain negative final
scores so a rejected candidate still shows the actual feedback contribution.

Frozen replay uses a separate model and never enters the recorder or impression paths. Privacy invalidation clears its input,
results, and pending work. Runtime overrides and detailed captured history are compiled only into Debug builds.
Preparation and inference timings are measured per Core ML call rather than read from shared mutable last-call state.

The [synthetic inspector](LAUNCHER-SUGGESTIONS.md#synthetic-scenarios-in-debug-builds) generates deterministic contexts and outcomes without importing or modifying real activity. Chronological playback evaluates each outcome before adding it to history. Its conflicting-routine fixture exposed a target-label bias in equal-distance neighbor selection; the evidence policy now breaks ties by date and example identity. Synthetic metrics remain separate from claims about real-world accuracy.

## Core ML feasibility evidence

The focused prototype ran on 8 September 2026 with an Apple M4, macOS 27.0, and the macOS 27.0 SDK from Xcode-beta. The app uses Swift 5 language mode, MainActor default isolation, and approachable concurrency. The standalone prototype explicitly uses CPU execution.

The fixture accepts 256 Float32 values named `context`. Its training label and predicted label are strings named `appIdentity`. Its score dictionary is `appIdentityProbs`. It starts empty, uses 15 nearest neighbors, squared Euclidean distance, an inverse-distance vote, and a linear index.

The prototype confirmed these behaviors:

- Empty inference returns the sentinel `__no_suggestion__` with score 1. Callers must suppress that sentinel.
- Updates accept previously unseen string identities. A second update introduced `new.dynamic.B` without a predefined label vocabulary.
- Inference returns multiple label scores. Scores were unchanged after model write and reload.
- Rebuilding from the empty seed with only retained examples removed the other labels from effective predictions.
- Calling `cancel()` immediately after `resume()` produced task state 4, completed, without a completion callback within five seconds. Production code must not depend on that callback to finish cancellation. The observed state does not establish that an update was safely published.

Apple documents [empty updatable nearest-neighbor models](https://apple.github.io/coremltools/docs-guides/source/updatable-nearest-neighbor-classifier.html) and [the model format](https://apple.github.io/coremltools/mlmodel/Format/NearestNeighbors.html). The public format supports uniform or inverse-distance votes. It exposes no per-example age weight, negative training label, or sample deletion operation. Recency and contextual feedback therefore need a separate score adjustment or a supported data representation. Expiry requires a rebuild from retained examples.

The selectable production engine checks its generation before publishing or saving an update. Reset, disable, pause, exclusions, or expiry must invalidate outstanding work immediately. A cancelled task may finish internally. A personalized model containing expired examples must be retired until a valid replacement exists.

## Synthetic comparison and resource measurements

The chronological stream contains 120 examples and 12 identities. Each context deterministically selects one identity. Each predictor scores the next outcome before seeing it, then receives the outcome. Ranking ties use string order. The first 12 observations have no prior examples for their contexts.

| Predictor | Top-3 hits out of 120 |
| --- | ---: |
| Inverse-distance nearest neighbors | 108 |
| Most frequent identity | 9 |
| Frequency conditioned on exact context | 108 |
| Production `LauncherSuggestionBaseline` | 108 |
| Three most recently used identities | 0 |

The final stream uses the production `LauncherSuggestionContext.featureVector` for model input and the same context for the app baseline. Foreground identity and hour vary. Other fields use fixed or empty values. All five predictors missed the first 12 outcomes. In the remaining 108 outcomes, the candidate, exact-context comparator, and production baseline each scored 108 hits, frequency scored nine, and most-recent scored zero. Every predictor covered 119 of 120 presentations except the exact-context comparator, which covered 108. Coverage counts any available candidate after suppressing the empty-model sentinel.

An earlier orthogonal-category experiment gave 95 hits for uniform votes and 108 for inverse-distance votes, which selected the latter for the final fixture. Neither stream measures real habits, feedback, changing preferences, or relevance. Neither justifies an accuracy claim. The exact-context comparator is a mechanics baseline, distinct from the production predictor. Real evaluation must remain chronological and local. Ranking stability across real presentations and results by real history age remain unmeasured.

The final inverse-distance run produced these measurements:

| Samples | Update, save, and reload | Prediction p95, 100 calls | Compiled model size |
| --- | ---: | ---: | ---: |
| 1,000 | 3.97 ms | 0.155 ms | 1,060,984 bytes |
| 10,000 | 29.37 ms | 0.302 ms | 10,563,581 bytes |

The production baseline scored the same 1,000-example and 10,000-example inputs with p95 times of 0.096 ms and 0.682 ms respectively. These numbers use an optimized Swift compilation and include no UI work.

These are single-run developer-machine measurements. Each scale update uses one synthetic batch to measure rebuild cost. They do not measure background energy, app memory peaks, or incremental updates under UI load. Initial evaluation budgets are 10,000 examples, a 16 MB compiled model, a 250 ms rebuild, and 5 ms p95 inference. These are engineering limits, not product guarantees. The selectable production engine now uses batches of at most 256. Its full 10,000-example rebuild took roughly one second in focused behavior tests, exceeding the original 250 ms target. That test duration is not an optimized benchmark; cumulative rebuild cost under UI load remains unmeasured.

The reproducible files are [the seed generator](../scripts/generate-suggestions-model.py), [the synthetic prototype](../benchmarks/micro/suggestions-model.swift), and [the empty seed](../scripts/fixtures/LauncherSuggestions.mlmodel). The generator requires `coremltools==9.0` in separate development tooling. The app has no Python dependency or packaged personalized model. These commands compile and run the prototype from the repository root. The prototype uses temporary model directories and reads no app-use history.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -O \
  DeeDock/Launcher/Suggestions/Models/LauncherSuggestionModels.swift \
  DeeDock/Launcher/Suggestions/Prediction/LauncherSuggestionBaseline.swift \
  DeeDock/Launcher/Suggestions/Prediction/LauncherSuggestionRanking.swift \
  DeeDock/Launcher/Suggestions/Prediction/LauncherSuggestionCoreML.swift \
  benchmarks/micro/suggestions-model.swift -o /tmp/dee26-benchmark
/tmp/dee26-benchmark scripts/fixtures/LauncherSuggestions.mlmodel
```

## Public observation limits

[NSWorkspace session notifications](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification) describe user-session switching. They do not promise an exact screen-lock notification. Sleep, screen-sleep, session switching, and idle gaps are conservative session boundaries. Exact lock behavior still needs native acceptance.

[CGEventSource.secondsSinceLastEventType](https://developer.apple.com/documentation/coregraphics/cgeventsource/secondssincelasteventtype(_:eventtype:)) returns elapsed time since input. The any-input value covers keyboard, mouse, and tablet input without reading their content. Apple's reference does not state a permission requirement for this accessor. Permission-denied behavior was not exercised. Invalid or unavailable idle readings must not become invented active-use duration.

## Focused behavior verification

The seven suggestion suites passed 61 tests in an isolated Swift Testing runner using Xcode-beta on 8 September 2026. They cover consent, pause, reset, stale feedback, exclusions, preceding context, dwell, session gaps, expiry, corrupt storage, bounded persistence, and keyboard ordering. The oversized persistence case verifies that a document exceeding 16 MiB saves a smaller document and reloads it successfully.

Additional Core ML coverage verifies dynamic labels, cache reuse after temporary-file deletion, changed and expired history, the 10,000-example cap, concurrent requests, cancellation, privacy invalidation, isolated abandoned-file cleanup, preference migration, baseline score preservation, and explicit model failure without fallback. The latest run includes evidence gates, runtime neighbor overrides, per-call diagnostics, Debug tuning persistence and clamping, frozen replay without learning side effects, and reset during replay. Synthetic coverage also verifies seeded reproducibility, input/outcome separation, off-consent isolation, chronological learning, clock shifts, cancellation, and a complete 60-step run with both engines. A balanced equal-distance fixture verifies that target labels cannot bias the reconstructed neighborhood. The final run completed in 1.132 seconds after a 6.38-second test build, with no warnings or errors. These are verification timings rather than performance measurements. Log: `/tmp/dee26-synthetic-final-focused-tests.log`.

The existing Xcode test target could not compile because unrelated shared-source dependencies were missing, including `WindowActionModels` and `BossFightConfiguration`. Only DEE-26 source memberships were retained in the project. The temporary runner copied the actual production files and tests, with Swift 5 language mode and MainActor default isolation. It does not exercise app integration or native UI.

The [focused test script](../scripts/test-launcher-suggestions.sh) reproduces the runner from the repository root. It copies an explicit list of production sources and the seven suites, then removes the temporary package on exit.

```sh
scripts/test-launcher-suggestions.sh
```
