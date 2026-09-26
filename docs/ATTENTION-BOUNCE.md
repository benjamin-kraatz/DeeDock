# Detect app attention through system Dock geometry

Tracked in [DEE-81](https://linear.app/d-zwei/issue/DEE-81/detect-system-dock-attention-bounces-through-ax-geometry).

## Outcome and scope

A live Rattention experiment on 26 September 2026 confirmed that the system Dock exposes attention-bounce motion through `AXPosition` and `AXFrame`. DDock can potentially use this motion as evidence to animate its own matching app icon. This is a feasibility result, not a production detector or a semantic "requires attention" API.

The next implementation should be opt-in and best-effort. Do not substitute badge changes for attention detection without separate product approval. An app can request attention without changing its badge, and badge changes need not request attention.

## Observed evidence

Environment: macOS 27.0 build 26A428, existing bottom-edge system Dock, auto-hide enabled, existing Accessibility access. No Dock preferences, permissions, or machine settings were changed. A stale Xcode Preview instance was stopped to avoid confusing it with the actual Rattention process.

| Observation | Result |
| --- | --- |
| Informational request while app logged `active=false` | One approximately one-second motion group. Rest Y was 1445 points; sampled peak was about 1376 points, approximately 69 points inward. |
| Critical request while app logged `active=false` | Repeated approximately one-second motion groups, roughly two seconds apart. |
| Activate requesting app | The external foreground log confirmed Rattention briefly became frontmost. No later geometry changes were recorded during the remaining observation period. |
| Position and frame | Both followed bounce motion. Separate reads are not atomic and can disagree within a sample. |
| Size | Stayed at 47 × 59 points for the observed icon. |
| Badge and progress | `AXStatusLabel` and `AXProgressValue` stayed nil. |
| Attribute discovery | 16 attributes; no explicit attention flag. Parameterized attribute list was empty. |
| Sampling | 1,642 full-attribute passes in 52 seconds, approximately 31.6 Hz. This is diagnostic throughput, not a production performance recommendation. |

Exposed attributes: `AXRole`, `AXRoleDescription`, `AXSubrole`, `AXTitle`, `AXParent`, `AXChildren`, `AXPosition`, `AXSize`, `AXFrame`, `AXTopLevelUIElement`, `AXSelected`, `AXShownMenuUIElement`, `AXStatusLabel`, `AXProgressValue`, `AXURL`, `AXIsApplicationRunning`.

Dock-item registrations for `AXMoved`, `AXResized`, `AXValueChanged`, `AXTitleChanged`, `AXLayoutChanged`, `AXSelectedChildrenChanged`, and `AXAnnouncementRequested` returned `-25207`, notification unsupported. `AXCreated` and `AXUIElementDestroyed` registration succeeded but produced no attention signal. This does not rule out a useful notification on another element; it means an event-only detector has not been demonstrated.

Cancellation requests were logged, but residual geometry after cancellation was mixed with layout/menu changes. Do not claim exact cancellation timing from this run. Activation-related cessation was observed. Initial UI-driven informational attempts were inconclusive; the finite in-app sequence supplied the controlled positive result.

## Evidence and reproduction

Tracked evidence:

- `scripts/probe-dock-attention.swift`: the external read-only AX sampler used for the controlled run.
- `docs/evidence/attention-bounce/sequence-ax.log`: controlled sequence. Item 1 is the test app under `/private/tmp/rattention-probe/build`; item 0 is the previous app installation.
- `docs/evidence/attention-bounce/requests.log`: request, cancellation, and activation markers from Rattention. Its relative clock starts about 5.6 seconds before the AX sampler's clock.
- `docs/evidence/attention-bounce/critical-live.log`: initial successful UI-triggered critical-request trace.

Home-directory names in committed traces are replaced with `USER`. Geometry and timing are unchanged. The unsigned app logged a sandbox-extension warning, but the sequence ran and the Dock geometry changed. Two app installations initially appeared, and removing the older item moved the remaining icon horizontally. Match by installation URL, not just title or index.

Rattention contains the existing informational/critical buttons with a 1.2-second delay. `AttentionProbe.runIfRequested()` adds a once-per-process sequence only when launched with `--attention-probe`. Normal launches and previews do not run it. The sequence hides its own window, requests informational attention, cancels it, requests critical attention, cancels it, repeats critical attention, and activates the app. Its defer cancels any remaining request. The test app was stopped after collection.

The narrow unsigned Debug target build passed:

```sh
xcodebuild -project DeeDock.xcodeproj -target Rattention -configuration Debug CONFIGURATION_BUILD_DIR=/tmp/rattention-probe/build CODE_SIGNING_ALLOWED=NO build
swiftc scripts/probe-dock-attention.swift -o /tmp/rattention-probe/probe
```

Run the helper with `--attention-probe`, then immediately run the sampler in another terminal:

```sh
/tmp/rattention-probe/build/Rattention.app/Contents/MacOS/Rattention --attention-probe > /tmp/rattention-probe/requests.log 2>&1
```

```sh
/tmp/rattention-probe/probe 52 > /tmp/rattention-probe/sequence-ax.log
```

Use an environment with existing AX access; the sampler exits with `AX_NOT_TRUSTED` otherwise. It does not request permission. Keep the pointer away from the Dock during baseline runs. Stop the helper after capture. Before more detailed latency measurements, give both processes a shared monotonic or absolute timestamp; the original relative clocks only support approximate alignment.

## Proposed implementation sequence

1. **Make the experiment repeatable.** Add shared timestamps, typed geometry, request markers, explicit inactive-state checks, stable app identity, and bounded capture duration. Collect clean cancellation, active-app no-op, informational, and critical runs. Keep diagnostics separate from shipping observation.
2. **Choose a detection budget.** Investigate broader AX notifications before committing to polling. Benchmark cached position reads at candidate rates such as 5, 10, and 20 Hz with realistic Dock sizes. Measure detection latency, misses, CPU, energy, and IPC failures. Do not copy the full-attribute 31.6 Hz diagnostic loop into production.
3. **Build one shared observer.** Reuse identity and permission patterns from `DockBadgeReader` and `DockBadgeController`, without accelerating badge scans. Cache AX handles, rediscover on Dock restart or item changes, use bounded messaging timeouts, and pass immutable samples out of the reader. Own and cancel tasks explicitly; keep AX IPC off pointer/render paths and UI mutation on MainActor.
4. **Separate geometry classification from AX plumbing.** Track stable baseline, displacement, return motion, sample confidence, and app lifecycle. Normalize inward motion for bottom/left/right system Dock placement using AX screen coordinates in points. Do not reuse AppKit coordinates without conversion. Suppress classification during common movement of neighboring icons, magnification, resizing, drag/reorder, reveal/hide, menus, display changes, and uncertain baselines. Suppress known launch activity and foreground apps. A single frame displacement is insufficient evidence.
5. **Represent evidence, not certainty.** A small state machine can use idle, candidate, detected, and cooldown states. Detect a short informational bounce without requiring multiple full cycles. Avoid inferring critical severity or indefinite urgency from motion alone. Clear on activation, termination, permission loss, stale samples, Dock restart, disable, and timeout. Do not retain an urgent state forever after missed cancellation.
6. **Connect presentation separately.** Reuse poses/edge direction from `DockLaunchAnimation` and `DockLaunchMotion`, but give attention its own trigger and lifecycle. Preserve layout, icon size, running markers, magnification, hit targets, and focus. Deduplicate across DDock displays; decide whether all visible instances or one selected display animates. Define precedence when launch/attention/drag animations overlap.
7. **Add an explicit preference.** Start off by default with an explanation of Accessibility access and best-effort detection. Use the existing permission flow; no startup prompt or changes to Apple's Dock settings. Keep UI copy in `Localizable.xcstrings`, including unavailable states. Respect Reduce Motion with a non-moving indication if approved. Do not automatically reveal a hidden DDock until that behavior is explicitly chosen.
8. **Validate before enabling by default.** Use recorded geometry fixtures for classifier behavior and native acceptance for macOS integration. Run tests only when separately authorized under repository rules. Record measured limitations in `docs/ACCEPTANCE.md`.

Relevant current code: `DeeDock/Dock/Badges/DockBadgeReader.swift`, `DockBadgeController.swift`, `DeeDock/Dock/LaunchAnimations/DockLaunchMotion.swift`, `DockLaunchAnimation.swift`, `DeeDock/Dock/State/ApplicationCatalog.swift`, and per-display visibility state.

## Tradeoffs and decisions

| Option | Benefit | Cost or limitation |
| --- | --- | --- |
| Higher-rate geometry sampling | Catches shorter informational motion with lower latency | Recurring AX IPC, CPU/energy cost, more failure handling; no budget measured yet |
| Slow or adaptive sampling | Lower idle cost | Can miss the first or entire informational bounce; adaptive sampling needs an initial signal |
| Read only cached geometry | Much cheaper candidate than full attribute scans | Requires reliable identity, invalidation, and baseline management |
| Wait for repeated cycles | Stronger motion evidence | Misses single informational requests and increases latency |
| Classify one bounce trajectory | Supports informational requests | More false-positive risk from launch and pointer-driven movement |
| Badge-change trigger | Can reuse existing badge observation | Different semantics; misses attention without badges and animates unrelated badge changes |
| Observe only apps shown in DDock | Reduces work | Hidden/filtered apps are intentionally not covered; per-display visibility must be reconciled |
| Direct app integration | Can provide semantic start/cancel information | Requires each app to cooperate; not a general solution |

Geometry provides no attention reason or authoritative severity. No bounce means no evidence, not proof that no app needs attention. Disabled system bouncing, unsupported Dock behavior, absent Dock items, or Reduce Motion may remove the observable signal. Do not use private Dock injection, screen recording, or preference changes as incidental workarounds.

## Acceptance and remaining risks

- Reproduce informational, repeated critical, explicit cancel, activation, termination, and already-active request behavior with timestamped evidence.
- Distinguish launch bouncing, pointer magnification, resizing, reordering, contextual menus, global reveal/hide, and item insertion/removal from attention.
- Cover system Dock bottom/left/right, permanently visible and auto-hidden modes, display scaling and negative origins, multiple monitors, Spaces, full-screen apps, and Dock relocation/restart.
- Cover sleep/wake, session changes, Accessibility denial/revocation, AX timeouts, stale handles, and disable/reenable. Release observers and tasks on teardown.
- Verify DDock motion on all four DDock edges, independent per-display state, hidden/faded behavior, Reduce Motion, keyboard/accessibility behavior, and no focus stealing.
- Measure idle CPU/energy, worst-case AX latency, app-count scaling, detection latency, missed short bounces, and false positives. Agree on budgets before release.
- Recheck other supported OS builds. AX geometry behavior is observed, not a documented cross-app attention contract.

Only Rattention compilation and the described live probe were validated. DDock was not built or tested for this investigation. Existing working-tree performance/UI edits are included on the requested branch in a separate commit; they are not evidence that a production attention detector exists.
