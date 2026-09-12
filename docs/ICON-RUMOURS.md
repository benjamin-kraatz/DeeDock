# Icon rumours

DEE-43 uses Apple Foundation Models to invent short fictional exchanges between pinned application icons. Enable **Sims moods** and **AI icon rumours** in **Settings → Features → Dock Sims**. AI rumours are off by default. Disabling them keeps moods and care history.

## Playback

Each visible dock waits for 30 uninterrupted seconds without dock interaction, then requests an exchange for its fully visible pinned apps. The model chooses the speakers, topic, opening, and reply. After generation finishes, the first app speaks for five seconds and the second replies for five seconds. Another generation opportunity follows after 90 quiet seconds. These timing limits bound background work and give each line reading time. Folder pins, utility tiles, and running apps without pins do not participate.

The callout sits beside the speaking icon in DDock's existing tooltip space. It stays still, makes no sound, takes no focus, and passes clicks through. Move the pointer into the dock to skip an exchange. Keyboard focus, dragging, menus, popovers, errors, app launches, and timeline browsing also interrupt playback. An interrupted exchange is discarded.

Rumours pause while a DDock Focus Session is active, including a paused session, and while Reduce Motion is enabled. Reduce Transparency uses an opaque background. Hidden docks do not reveal themselves for rumours. Sleep, screen sleep, session changes, application switches, and Space changes cancel the current exchange and restart the quiet interval when eligible. Removing a display cancels its view-owned playback task and notification subscriptions.

Turning **AI icon rumours** off is the persistent quiet control. This feature does not inspect macOS Focus or Do Not Disturb settings.

## Dependency and data

Implementation was blocked on [DEE-33, Dock Sims](https://linear.app/d-zwei/issue/DEE-33/dock-sims-pet-mini-game), mirrored as [GitHub issue #69](https://github.com/benjamin-kraatz/DeeDock/issues/69). Before DEE-43 implementation began on 2026-09-12, Linear showed DEE-33 as Done, completed on 2026-09-10, and this checkout contained its merged [PR #110](https://github.com/benjamin-kraatz/DeeDock/pull/110), merge commit `6d14b3c`.

Playback requires the existing Sims store to be enabled and readable. The `aiRumoursEnabled` consent flag lives in `dock.sims.v1`. Older documents default it to false. The earlier canned-rumour flag does not grant AI consent. A corrupt document keeps edits frozen until the existing explicit reset. Up to three recent generated exchanges stay in memory to discourage repetition; disabling Sims or AI rumours clears that history. Dialogue never enters care history or durable storage.

The composer uses `SystemLanguageModel.default` on this Mac. Input consists of visible app names, fictional pet moods, the app locale, and recent generated dialogue. App identities are replaced with candidate numbers before prompting. It reads no app content, sends no network requests, and changes no system Dock settings. There is no cloud provider, tool calling, scripted dialogue, or canned fallback.

## Debug trigger

Debug builds add **Gerüchterunden → Nächste Gerüchterunde starten** in Dock Sims settings. The button skips the initial wait or the current cooldown for one round on the first eligible visible dock. It can replace an exchange already on screen. Hidden or busy docks wait until eligible; the button does not reveal them or override consent, Focus Sessions, or Reduce Motion. It is disabled while generation is in flight. Repeated clicks coalesce into one pending round. Turning Sims or AI rumours off clears that request.

The button, pending request, claim mechanism, and timing override compile only under `DEBUG`. Nothing is persisted.

## Generation contract

The user's follow-up on 2026-09-12 authorized AI generation in this slice, superseding the issue's original canned-only scope. AI still requires its own in-app opt-in.

`FoundationModelsRumourComposer` creates a fresh session for each exchange. Its instructions require a specific fictional secret or rumour about the app mascots, followed by mock disbelief, a knowing tease, or another juicy detail. The gossip stays affectionate and low-stakes, with idiomatic language and varied topics relative to recent dialogue. App names and prior model output are explicitly untrusted data. The model must not claim to have observed private activity or pressure the user to care for the pets.

[Apple's guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation) supplies typed candidate numbers and dialogue fields. The app validates candidate numbers, nonempty single-line dialogue, and a 65-character display limit. If the first draft fails validation, the model receives one concrete revision request with the failure reason and a shorter word target. An invalid revision is discarded. These are identity and display constraints, not a heuristic dialogue generator. Model output is rendered verbatim as text.

One shared composer permits a single in-flight request across display docks. Other docks skip that opportunity. Cancellation and consent are checked after generation before displaying anything. The model is checked for availability, guided-generation capability, and support for the requested locale before every request. A refusal, framework error, or still-invalid revision leaves the dock quiet until a later opportunity. Settings shows an explanation. No fallback model or canned line runs.

Compile checks cannot establish humour quality, localization quality, model latency, battery cost, or native input behavior. Those require hands-on acceptance on an Apple Intelligence-capable Mac.


## Diagnostics

Generation failures appear under **Settings → Features → Dock Sims → Fehlerdetails / Error details**. The selectable report includes a timestamp, request ID, failure reason, and error domain and code. Opening Settings preserves the last failure. A successful exchange or disabling Sims or AI rumours clears it.

Unified logs use the `IconRumours` category under the app bundle identifier. Starts and successes are info events, a validation revision is a notice, and final failures are error events. Cancellation and a busy composer are debug events. Public diagnostic records exclude app names, prompts, and dialogue. Framework descriptions are private debug fields.

To inspect live events in Terminal:

```sh
log stream --style compact --level info --predicate 'category == "IconRumours"'
```

To inspect recent failures:

```sh
log show --last 15m --style compact --info --predicate 'category == "IconRumours"'
```

On 2026-09-12, a live German reproduction returned lines of 79 and 72 characters. The model completed normally; the earlier app validator discarded both and exposed only a generic failure. A bounded prose regex guide was also rejected by the local model, so the implementation uses a bounded model revision rather than that guide. No canned fallback or character truncation is used.
