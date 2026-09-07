# Session Capsule breadcrumbs

DEE-13 adds a deliberate leave-and-return workflow to Session Capsules. It uses the existing `dock.session-capsules.v1` collection, including its limit of 30 records and existing oldest-record eviction. Optional fields let older saved capsules load without migration or a second store. Existing capsule creation, launcher checkpoints, and focus-session handoff remain available.

## Leave and return

1. Open Session Capsules and choose **Leave a breadcrumb**, or press Command-B in the collection.
2. Select relevant windows and choose **Continue to note**. **Write manually**, also available with Command-M, continues without capture or model access.
3. Write a note or next step. Optionally choose **Capture & draft with Apple Intelligence** to read the selected windows once. This action retains no pixels after the operation. Its editable AI interpretation stays separate from personal writing.
4. Review the text previews. Add an HTTP or HTTPS link yourself, or choose a saved document through the native file picker. Remove any source or captured text that should not be retained.
5. Choose **Save Capsule**. A manual note, manual next step, or generated recap is sufficient. Return opens the saved recap without capturing content.
6. Use the source actions individually. **Show window** rechecks a unique app/title match. **Open app** opens or activates its app. **Open link** opens the supplied web URL. **Open saved document** resolves the bookmark for the selected file.
7. Choose **Edit**, also available with Command-E, to revise saved text or sources. Save keeps the original record identity and creation time. Delete requires the existing confirmation.

Editing a saved breadcrumb does not rediscover or recapture its windows. Create a new breadcrumb for a fresh capture. A changed, closed, unreadable, or protected source can have no text preview. Capture or model failures leave manual writing intact. Cancel during generation returns to the manual draft; Back or Escape leaves the flow and discards unsaved changes.

## Retained data and public API limits

A breadcrumb stores app bundle identity, window title, selection time, capture-attempt time, optional captured text, user-provided links, and security-scoped document bookmarks. A text preview is always labeled historical and stale, even when a matching window exists. Availability checks read Accessibility metadata without screenshots or OCR. Unavailable, unverified, and ambiguous matches have different labels. A title match cannot prove durable window identity across restarts.

Each source retains at most 2,000 OCR characters, a 2,048-character web link, and a 64 KiB document bookmark. Each breadcrumb has at most twelve sources, an 8,000-character note, an 8,000-character generated recap, a 2,000-character next step, and six suggestions of at most 2,000 characters each. Screenshots remain serially captured, at most 1,200 by 900 pixels each, and transient. The composer uses the existing 500-token output limit. Source text and model output never become commands or reopening paths.

Capture validates the selected window's process, bundle, and title again to avoid reusing a stale window number. Sources without readable OCR are excluded from model input. If no readable source remains, generation falls back to manual editing. The prompt requires explicit evidence of unfinished work and permits an empty task list. This reduces unsupported suggestions; model correctness still requires user review.

Removing a source and saving removes its excerpt, link, and bookmark from the record. Removing a preview alone preserves the other source metadata. Deleting or evicting a capsule removes all of its associated data from the active collection. There are no capture sidecar files to orphan. Original documents are never deleted. This is ordinary local storage deletion, not a promise of secure erasure from OS backups.

Document reopening requires an explicitly selected saved file. Stale bookmarks or missing files produce an error and require selection again in Edit. Arbitrary URL schemes and URLs containing credentials are rejected. Window actions use public Accessibility APIs and may be unavailable because of permissions, App Sandbox policy, Spaces, or full-screen behavior. DDock does not restore unsaved documents, exact geometry, or Space membership.

Capture and generation run on their existing actors, outside pointer and rendering paths. The coordinator owns cancellation through Back, Cancel, panel close, and display teardown. Source navigation owns a separate cancellable task; every discovery session discards its AX handles. User notes and next steps never pass through the model. No idle, app-switch, or break-return observer captures content.

## Model and state cases worth testing

These are specifications for future tests. No tests were run for this implementation.

- Decode an old v1 fixture without breadcrumb fields; preserve ordinary capsules and their creation dates when round-tripping. Reject invalid versions without overwriting saved evidence.
- Save a note-only, next-step-only, or AI-recap-only breadcrumb. Reject empty content and bound all new retained data. Reopen an edited breadcrumb with the same ID and creation date.
- Discover without permission, without windows, or with an error; manual editing remains available. Verify no capture call before the explicit capture action.
- Exclude missing OCR from model input. With no readable source, skip generation. Check partial input, unrelated text, prompt-injection text, contradictory context, duplicate titles, and empty generated suggestions.
- Preserve personal note, next step, user links, and bookmarks across model unavailability, generation failure, cancellation, and retries. Reject late completions after Back or a newer operation.
- Remove a selected source before generation and verify it is not captured. Match capture results by draft reference identity, including duplicate window titles.
- Validate HTTP(S) schemes, hosts, credentials, length bounds, missing files, oversized bookmarks, and stale bookmarks. Never derive a reopening URL from generated output.
- Match source navigation across multiple running instances. Zero matches are unavailable; duplicate titles are ambiguous. Recheck on Show window and discard every AX session on failure, cancellation, or success.
- Delete the capsule after saving captured text and bookmarks. Verify the serialized record is absent, no sidecar exists, and source files remain unchanged. Check existing capacity eviction.
- Verify original New Capsule, app checkpoint creation, focus completion handoff, Resume menus, and corruption/reset behavior.

## Manual acceptance checklist

All items below remain untested. Use a signed installed build for TCC and sandbox-sensitive behavior.

- [ ] Save a manual next step without Screen Recording or Apple Intelligence. Restart DDock, edit it, save, restart again, and confirm there is one updated capsule.
- [ ] Capture two sources deliberately, review previews and AI interpretation, and save. Close one source window, restart DDock, and inspect the recap. The closed source is unavailable or unverified; every preview remains historical.
- [ ] Use Show window, then rename or close that window and retry. Check duplicate titles and multiple processes sharing a bundle ID. Open app must not promise restoration of an unsaved document.
- [ ] Add a real web link and selected saved document. Open both after restart. Move or delete the file, revoke access, and check the actionable error. Reject invalid links without disabling manual writing.
- [ ] Remove a source before capture. Confirm only remaining selected sources are processed. Remove captured text and save; reopen and verify it is gone.
- [ ] Turn off Apple Intelligence or use an unavailable model. Exercise unreadable/protected content, model failure, cancellation, retry, and denied capture. Notes and next steps remain usable, with no invented tasks from missing text.
- [ ] Delete a saved breadcrumb. Confirm its dock item, text previews, links, and bookmarks disappear from the saved collection while original files remain intact.
- [ ] Check all four dock edges, negative display origins, different scaling, narrow displays, auto-hide, and display unplug/replug. Verify panel positioning and scrolling.
- [ ] Check full-screen apps, Spaces, sleep/wake, and app relaunch. Availability labels must stay honest; no layout restoration is implied.
- [ ] Use keyboard-only navigation, Command-B, Command-M, Command-E, Return, Tab, and Escape. Exercise the file picker, VoiceOver names, German and English copy, Reduce Motion, and Reduce Transparency. Hover must not steal focus.
- [ ] Confirm original capsule creation and focus-session completion still work. Verify no capture happens on idle, app switch, or return from a break.

## Compilation and delivery

The focused Debug app build uses Xcode 27.0, build 27A5252f, the macOS 27.0 SDK and deployment target, Swift 5 language mode, and MainActor default isolation. The final focused build succeeded on 2026-09-07. The initial clean build reported existing unused-value warnings in `LauncherPresentationController.swift` and `DockBadgeController.swift`. The final incremental build reported only the App Intents metadata notice for a target without that framework dependency. There were no build failures.

`jq empty DeeDock/Resources/Localizable.xcstrings` and `git diff --check` passed. All 45 breadcrumb keys matched their intended values in both compiled `en.lproj/Localizable.strings` and `de.lproj/Localizable.strings`, inspected with `plutil -convert json -o -`. This verifies resource contents, not native presentation or translation acceptance.

Implementation branch: `feature/dee-13`. Persistence and grounding commit: `b537067`. Editor and source navigation commit: `6d47248`. Delivery references [DEE-13](https://linear.app/d-zwei/issue/DEE-13/where-was-i-resume-work-from-session-capsule-breadcrumbs) and [GitHub issue 18](https://github.com/benjamin-kraatz/DeeDock/issues/18).

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/dee13-build \
  CODE_SIGNING_ALLOWED=NO build
```

No tests, app launches, previews, automated visual checks, or native acceptance were performed. Compilation does not establish window matching, capture quality, model grounding, accessibility, or multi-display acceptance. The issue must not be marked Done from build success.
