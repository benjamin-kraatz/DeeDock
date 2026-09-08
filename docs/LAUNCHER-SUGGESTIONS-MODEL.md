# Launcher suggestion model decision

DEE-26 uses a local frequency, recency, and transition baseline as its initial predictor. The Core ML nearest-neighbor candidate remains an evaluation fixture. Synthetic evaluation confirmed that it works, but did not establish a quality advantage over a context-transition baseline. Shipping another model would add persistence and cancellation complexity without measured benefit.

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

Any future production model needs an independent generation check before publishing or saving an update. Reset, disable, pause, exclusions, or expiry must invalidate outstanding work immediately. A cancelled task may finish internally. A personalized model containing expired examples must be retired until a valid replacement exists.

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

These are single-run developer-machine measurements. Each scale update uses one synthetic batch to measure rebuild cost. They do not measure background energy, app memory peaks, or incremental updates under UI load. Initial evaluation budgets are 10,000 examples, a 16 MB compiled model, a 250 ms rebuild, and 5 ms p95 inference. These are engineering limits, not product guarantees. Future production updates should use batches of at most 256 and benchmark their cumulative cost separately.

The reproducible files are [the seed generator](../scripts/generate-suggestions-model.py), [the synthetic prototype](../scripts/benchmark-suggestions-model.swift), and [the empty seed](../scripts/fixtures/LauncherSuggestions.mlmodel). The generator requires `coremltools==9.0` in separate development tooling. The app has no Python dependency or packaged personalized model. These commands compile and run the prototype from the repository root. The prototype uses temporary model directories and reads no app-use history.

```sh
xcrun swiftc -O DeeDock/Launcher/Suggestions/Models/LauncherSuggestionModels.swift DeeDock/Launcher/Suggestions/Prediction/LauncherSuggestionBaseline.swift scripts/benchmark-suggestions-model.swift -o /tmp/dee26-benchmark
/tmp/dee26-benchmark scripts/fixtures/LauncherSuggestions.mlmodel
```

## Public observation limits

[NSWorkspace session notifications](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification) describe user-session switching. They do not promise an exact screen-lock notification. Sleep, screen-sleep, session switching, and idle gaps are conservative session boundaries. Exact lock behavior still needs native acceptance.

[CGEventSource.secondsSinceLastEventType](https://developer.apple.com/documentation/coregraphics/cgeventsource/secondssincelasteventtype(_:eventtype:)) returns elapsed time since input. The any-input value covers keyboard, mouse, and tablet input without reading their content. Apple's reference does not state a permission requirement for this accessor. Permission-denied behavior was not exercised. Invalid or unavailable idle readings must not become invented active-use duration.

## Focused behavior verification

The three suggestion suites passed 20 tests in an isolated Swift Testing runner on 8 September 2026. They cover consent, pause, reset, stale feedback, exclusions, preceding context, dwell, session gaps, expiry, corrupt storage, bounded persistence, and keyboard ordering. The oversized persistence case verifies that a document exceeding 16 MiB saves a smaller document and reloads it successfully.

The existing Xcode test target could not compile because unrelated shared-source dependencies were missing, including `WindowActionModels` and `BossFightConfiguration`. Only DEE-26 source memberships were retained in the project. The temporary runner copied the actual production files and tests, with Swift 5 language mode and MainActor default isolation. It does not exercise app integration or native UI.

The [focused test script](../scripts/test-launcher-suggestions.sh) reproduces the runner from the repository root. It copies an explicit list of production sources and the three suites, then removes the temporary package on exit.

```sh
scripts/test-launcher-suggestions.sh
```
