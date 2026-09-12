# Icon rumours

DEE-43 uses Apple Foundation Models to invent short fictional exchanges between pinned application icons. Enable **Sims moods** and **AI icon rumours** in **Settings → Features → Dock Sims**. AI rumours are off by default. Disabling them keeps moods and care history.

## Playback

Each visible dock waits for 30 uninterrupted seconds without dock interaction, then requests an exchange for its fully visible pinned apps. The model chooses the speakers, topic, and dialogue. Each turn is shown for 5–15 seconds according to its length and can wrap across four lines. Another generation opportunity follows after 90 quiet seconds. These timing limits bound background work and give each line reading time. Folder pins, utility tiles, and running apps without pins do not participate.

The **Gossip intensity** slider is available in production and persists independently of animation strength. Older preferences default to **Light chatter**.

- **Light chatter**: two icons, one turn each, affectionate gossip.
- **Loud whispering**: two icons, three alternating turns, sharper shade and a cutting comeback.
- **Egregious echoing**: every eligible app when there are at most five, otherwise five model-selected apps. Each speaks twice, giving 4–10 turns of an escalating roast about an invented absent mascot.

Group rounds have a shared five-minute cooldown across displays, measured from successful generation. It survives style and consent changes during the app session, includes sleep time, and resets when DDock quits. A reservation prevents concurrent group requests. The Debug button bypasses the cooldown for one attempt; automatic rounds after it still observe the limit. Changing intensity discards current generation and playback. The sharper styles target fictional mascots, never the user or real people.

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

`FoundationModelsRumourComposer` creates a fresh session for each exchange. Its instructions require a specific fictional secret or rumour about the app mascots, followed by mock disbelief, a knowing tease, or another juicy detail. The selected style controls tone and turn count, from affectionate gossip to a theatrical fictional roast. Language stays idiomatic and topics vary relative to recent dialogue. App names and prior model output are explicitly untrusted data. The model must not claim to have observed private activity or pressure the user to care for the pets.

[Apple's guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation) supplies typed candidate numbers and dialogue fields. The app validates candidate numbers, the exact turn count, distinct speaker coverage, alternating speakers, and nonempty dialogue. Group rounds require two turns from every selected participant. If the first draft fails validation, the model receives one concrete revision request with the structural failure reason. An invalid revision is discarded. Line length and line breaks do not reject an exchange; concise phrasing is advisory. These are identity and conversation-structure constraints, not a heuristic dialogue generator. Model output is rendered verbatim as text.

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
