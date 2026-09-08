# Future suggestion model

This document describes a possible successor to DDock's local suggestion engines. It is a technical direction, not an approved implementation plan or a claim that a learned model will outperform the current baseline.

The proposed system starts with a model trained from consented population data, then adapts a small part of that model on each Mac. Population training should learn patterns that transfer between people. On-device learning should own each person's app identities, routines, exclusions, and feedback.

The current implementation and measurements remain documented in [Launcher suggestion model decision](LAUNCHER-SUGGESTIONS-MODEL.md). Current product behavior and local data limits remain documented in [Launcher app suggestions](LAUNCHER-SUGGESTIONS.md).

## Why a hybrid model may help

The local engines need observed transitions before they can offer useful suggestions. A population model could reduce that cold-start period by learning common relationships between context and app characteristics.

Population data may reveal patterns such as these:

- Development apps often lead to a terminal, browser, or source-control app.
- Communication and calendar apps follow time-of-day and weekday patterns.
- Running state, recent use, and app category affect the likelihood of an app switch.
- Some context signals transfer between users even when their installed apps differ.

Personal data still matters more for exact choices. A population model cannot know that one person opens a private company app after Xcode or prefers one browser in a particular Dock Mode.

## Score candidates instead of classifying fixed apps

A global classifier with one output class per bundle identifier has a structural problem. Each Mac has a different app set, and that set changes. Private, enterprise, new, and uncommon apps may never appear in the population training set.

The future model should score a pair:

```text
score(current context, candidate app)
```

At prediction time, DDock supplies eligible installed apps as candidates. The model scores each candidate and returns a ranking. This design can score an app that was absent from population training, provided that the app has useful candidate features.

The candidate set must continue to apply the current product rules before ranking. DDock, the pre-Launcher foreground app, unavailable apps, background helpers, and explicit exclusions remain ineligible.

## Proposed architecture

```text
Current context ──> pretrained context encoder ─┐
                                                ├──> candidate scorer ──> population score
Candidate app ────> pretrained app encoder ─────┘
                                                              │
Personal transition state ─────────────────────────────────────┤
Local feedback and exclusions ─────────────────────────────────┤
Transparent baseline ──────────────────────────────────────────┘
                                                              │
                                                              v
                                                        final ranking
```

The system has four parts.

### Pretrained context encoder

The context encoder converts non-content metadata into a compact representation. Initial inputs may include:

- Cyclic local time and weekday.
- The preceding foreground app's transferable features.
- Features for up to three recent apps.
- A bounded summary of eligible running apps.
- Whether a candidate is running or pinned.
- Time since the candidate was last used.
- A local Dock Mode feature when a privacy review permits it.

The encoder must not consume window titles, document names, paths, URLs, screenshots, keystrokes, or app content.

### Pretrained app encoder

The app encoder represents a candidate without requiring a globally known output class. Candidate features could include:

- A coarse application category.
- A privacy-reviewed representation of the bundle identifier.
- Running and pinned state.
- Local frequency and recency values.
- Whether the app was seen during population training.

A raw bundle identifier is useful but sensitive. Rare identifiers can reveal an employer, a client, or specialized work. Population training must either omit raw identifiers, place them behind a strict frequency threshold, or transform them under a documented privacy mechanism. Hashing alone does not make a small identifier space private.

### Candidate scorer

The scorer combines the context and candidate representations and produces one ranking score. Suitable starting designs include a small multilayer perceptron or a two-tower model with a shallow interaction head.

The first model should stay small enough to score every eligible local candidate without blocking Launcher. The resource budget must cover the complete candidate pass, not one prediction in isolation.

### Personalization layer

The first personalized version should freeze the population encoders. DDock should update only a small local component, such as:

- Per-app local embeddings.
- A small candidate-scoring head.
- A calibration layer over population scores.
- A transition table blended with model output.

Updating the full model on each Mac creates more failure modes. A few accidental transitions can distort the model, older habits can be forgotten, and removing expired data becomes harder to prove. A small personalization layer gives reset, expiry, and rollback clearer boundaries.

## Training examples

The label remains the next meaningful foreground app. DDock should keep the current observation rules unless evidence supports a change:

- Capture the context before the outcome.
- Require a stable foreground activation before accepting the target.
- Treat launches and terminations as context, not automatic positive targets.
- End sessions across observed sleep, inactive user sessions, and long idle gaps.
- Keep missing observation periods unknown.
- Exclude DDock and apps without an approved stable identity.

Population training should convert each accepted transition into one positive candidate and sampled negatives from apps that were eligible at that moment. Negative sampling must not label every unchosen app as unwanted. The user chose one next app, but may still have considered other candidates useful.

The training objective should optimize ranking. Pairwise ranking loss or sampled softmax is a better fit than independent binary classification. Evaluation must use complete candidate rankings and report top-k outcomes.

## Combine population and personal evidence

The final score can blend several sources:

```text
final score =
    population weight × population score
  + personal weight × personal score
  + baseline weight × transparent baseline score
  + explicit feedback adjustment
```

The weights must be learned or tuned through chronological evaluation. Fixed example values in design discussions are not defaults.

The blend should depend on evidence volume. A new installation can rely mostly on the population score. Personal influence can grow as the Mac accumulates valid transitions. The model should retain the transparent baseline until the hybrid wins for both new and established users.

Explicit exclusions remain hard filters. A contextual rejection remains a local score adjustment. Neither action should depend on population training.

## On-device personalization with Core ML

Core ML supports on-device updates for models prepared with updatable layers. A future model package must identify the trainable layers, loss, optimizer, and training inputs before export.

The update lifecycle should preserve the current guarantees:

- Train away from the UI path in bounded batches.
- Predict from the last complete model while an update runs.
- Publish an updated model only when its data generation remains current.
- Cancel and invalidate pending work after disable, pause, reset, exclusion, expiry, or an engine change.
- Save replacements atomically.
- Keep a valid population model and baseline available when personalization fails.

Core ML cancellation does not remove the need for generation checks. A cancelled update can finish internally. DDock must reject stale output before it becomes active or reaches persistent storage.

The first production experiment should update only the personalization layer. Full-model adaptation should require evidence that the smaller update cannot reach the quality target.

## Data-sharing choices

The data-sharing design must be chosen before population collection begins. An opt-in toggle provides consent, but it does not define what DDock sends or what the service can infer.

### Central upload

DDock uploads selected training records to a service. This design is operationally direct and supports flexible offline training. It also exposes app-use sequences to the service. Rare app identities and transitions may reveal work, health, financial, or personal activity.

Central upload should be considered only for a clearly described research program. The consent screen must list the exact fields, retention period, deletion path, and purpose. Product consent for local suggestions must remain separate from research consent for sharing.

### Minimized or transformed records

DDock uploads reduced features instead of complete events. This reduces collected detail but does not automatically provide anonymity. Embeddings, hashes, timestamps, and rare transitions can still identify a user or organization when combined.

The design needs an attack analysis, frequency thresholds, time coarsening, contribution limits, and deletion semantics. Calling a value anonymous is not a technical control.

### Private federated learning

Each Mac computes a bounded local update. A service aggregates updates from many participating Macs without receiving raw event histories.

Federated learning alone does not guarantee privacy. A stronger design also needs secure aggregation, user-level differential privacy, per-user contribution limits, clipping, and audited server retention. Differential privacy introduces noise, so a small participant population can produce poor utility.

The first shared-data experiment should not begin with a full federated training system. A consented, tightly scoped research dataset can establish whether transferable signal exists. A production collection design should follow only after the team can state the privacy guarantee and measure its effect on model quality.

## Consent and user control

Local learning and population data sharing require separate choices:

- **Local suggestions** permits on-device collection and personalization.
- **Share data to improve suggestions** permits the documented population-training contribution.

Turning off sharing must stop new contributions without disabling local suggestions. The user must be able to inspect a plain-language field list, withdraw consent, and request deletion of centrally retained records when the chosen architecture permits central retention.

Resetting local suggestions must remove the personalization state and pending local updates. It must not silently change the sharing preference. Conversely, withdrawing sharing consent must not delete deliberate local exclusions unless the user asks to reset local suggestions.

## Population dataset requirements

The dataset must represent users as separate evaluation units. Randomly splitting neighboring events leaks future habits into training and overstates quality.

Before training, define these policies:

- Minimum participant and event counts.
- Maximum contribution per person and time window.
- Treatment of rare apps and identifiers.
- Geographic and locale coverage.
- Timezone and clock-change handling.
- App-category quality and missing metadata.
- Retention, deletion, and model-retraining obligations.
- Protection against scripted, corrupted, or malicious event streams.

The team should publish a versioned dataset schema and a data card. Each model should have a model card that names the dataset period, privacy mechanism, metrics, limits, and intended use.

## Evaluation

Every evaluation must replay each user's history chronologically. For each step, predict first, reveal the actual next app, then allow the local component to update.

Compare at least these systems:

- Most recent apps.
- Most frequent apps.
- The current weighted baseline.
- The current local Core ML nearest-neighbor engine.
- The frozen population model.
- The locally personalized model without population pretraining.
- The hybrid population and personal model.

Report these measures:

- Top-1 and top-3 hit rate.
- Mean reciprocal rank or normalized discounted cumulative gain.
- Suggestion coverage.
- Calibration or abstention quality when the model can withhold weak suggestions.
- Results for new users and established users.
- Results by personal-history age and app-set size.
- Results for common, rare, new, and private apps.
- Quality after a user's habits change.
- Update time, full candidate-ranking latency, model size, memory, and energy.

Aggregate results can hide regressions. Report per-user improvement distributions and the fraction of users for whom each model is worse than the baseline.

Evaluate feedback separately. Recommendation clicks are biased toward what the model already showed. Actual app transitions remain the main outcome signal, while explicit feedback measures correction behavior.

## Experiment design

An online comparison should assign models before recording outcomes and keep assignments stable for a defined period. Useful experiments include:

- Population model versus current baseline during cold start.
- Frozen population model versus locally personalized population model.
- Hybrid model versus local-only personalization.
- Different evidence thresholds for increasing personal weight.
- Suggestion display with and without a calibrated abstention threshold.

The experiment must measure suggestion usefulness without encouraging extra app openings. Launcher open rate and suggestion click rate alone are insufficient. The primary outcome should remain whether a suggested app matches the next meaningful app transition.

## Distribution and versioning

DDock should ship a signed population model as an application resource or a separately signed update. The model needs its own schema version, feature version, and training-data version.

The application must reject incompatible models before prediction. A model rollout needs rollback support. A new population model must not overwrite a valid local personalization state until migration or reset behavior is defined.

Personalization compatibility can follow one of three policies:

- Preserve the local layer when the input and representation schemas match exactly.
- Rebuild the local layer from retained eligible examples.
- Retire the local layer and restart personalization when migration cannot be proved correct.

Rebuilding from retained examples is the safest default because it applies current expiry and exclusion rules.

## Security and abuse cases

The design must handle these failures deliberately:

- A malicious or automated app produces repeated transitions to influence ranking.
- A rare bundle identifier encodes a person's employer or sensitive activity.
- A model update is interrupted during write or process termination.
- A stale update completes after reset or consent withdrawal.
- A downloaded model is corrupted, incompatible, or unsigned.
- Population training overfits one organization, locale, or work pattern.
- Differential privacy reduces quality unevenly for underrepresented users.

DDock should cap contributions, validate every identity and feature, sign distributed models, and keep generation checks around all model publication. Ordinary Launcher behavior must remain available when the model fails.

## Proposed development stages

### Stage 1: prove transferable signal

Collect no new population data yet. Use synthetic data and a small consented internal dataset to test candidate scoring. Compare a frozen population-style model with the existing engines.

### Stage 2: define the research program

Write the field schema, consent copy, privacy analysis, retention policy, deletion path, and minimum cohort size. Decide whether the research dataset is central, transformed, or federated.

### Stage 3: train a frozen population model

Train and evaluate the model with user-level chronological splits. Ship it only to an internal or opt-in test group. Do not enable on-device updates yet.

### Stage 4: add bounded personalization

Freeze the population encoders and update a small local layer. Compare frozen, personalized, local-only, and hybrid variants on the same histories.

### Stage 5: choose the production engine

Remove temporary engine choices only after one design wins on quality, resource use, privacy, reset correctness, and failure behavior. Keep a non-model fallback even after choosing the primary engine.

## Go and no-go criteria

Population pretraining is worth shipping only if it produces a meaningful cold-start gain and the gain survives user-level chronological evaluation. The hybrid must also improve established-user results without making a substantial group worse.

Before production, require all of these conditions:

- The team can state exactly what leaves the Mac and why.
- Consent for sharing is separate from consent for local learning.
- The privacy mechanism and its limits are documented.
- The model scores unseen local apps through candidate features.
- Reset, expiry, exclusion, model replacement, and consent withdrawal pass race tests.
- Full candidate ranking meets an agreed latency and energy budget.
- The hybrid beats the current baseline on held-out users.
- The model can abstain when evidence is weak.
- A signed population model and a safe fallback can roll back independently.

If the population model does not beat the local engines for enough users, DDock should keep local learning. More model complexity is useful only when it improves the product under the same privacy and reliability constraints.

## Open decisions

The following decisions need evidence rather than implementation preference:

- Which app features transfer without exposing rare identities.
- Whether the context and app encoders should share an embedding space.
- Which local component Core ML can update efficiently and reliably.
- How much evidence should increase the personal score weight.
- Whether a calibrated abstention model is better than always showing three apps.
- Whether central research collection can answer the first model question before federated infrastructure exists.
- Which differential privacy target provides useful protection without removing the signal.
- How population model updates migrate or rebuild personal state.
