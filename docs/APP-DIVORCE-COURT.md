# App divorce court

DEE-40 is a branch-only experiment on `feature/dee-40`. It is not intended for production toward 1.0. No release configuration or version changes are part of this work.

## Try it

Open **Settings → Features → App divorce court**. **Sample hearing** and **Sample with witness** use isolated fictional characters and do not change pins, real court records, or saved stage placement. They require an available on-device Apple Intelligence model supporting the current language.

**Enable automatic hearings** opts into occasional hearings after successful app unpins. Unpin is never delayed for model generation or subject to a verdict. **Skip forever** disables the experiment across launches until explicitly re-enabled. **Clear court data** removes its local biographies, case summaries, eligibility dates, and consent. The stage position is an independent UI preference.

Drag the stage's grip to place it on the desktop. When the stage has keyboard focus, Option-arrow keys move it and Escape closes it. **Pause**, **Resume**, and **Next** control reading time between statements. **Character stories** and **Transcript** expand within the stage. Closing cancels generation. **Pin again** is the only court control that can restore the app, and it revalidates the original display and Dock Mode first.

## Fiction and evidence

Apple Foundation Models creates each participating app's biography, recurring app counsel, opposing counsel, and the recurring judge. Saved canon is reused. Separate relationship records establish shared fictional incidents without rewriting biographies. The character library shows biographies, relationships, and completed cases; deleting a character also deletes its related cases and relationship records.

Only app names, saved fiction, prior completed case summaries, and separately consented aggregate activation counts enter model prompts. No screenshots, document contents, window titles, or browsing history enter court generation. Generated prose cannot execute tools or mutate pins. Full transcripts stay in memory; the final four completed statements form the saved case summary. The most recent 100 completed cases are retained.

Automatic eligibility requires 14 days since the pin was first observed after court opt-in, or at least 10 recorded activations across five days in the last 30 days. The usage path requires active App suggestions consent. It excludes excluded/revoked apps and future events, and never reads the separate synthetic Debug history. One hearing can open per seven days globally. There is one active hearing and no backlog.

Each automatic case has a 30% witness opportunity. Candidates are other pinned apps on that dock, preferring established relationships and then least-recent appearances. The chosen cast remains fixed across retries. Witness preparation failure falls back to an ordinary hearing. A witness adds testimony and a credibility assessment before closing arguments; prompts require both lawyers and the judge to address it. Semantic consistency still requires live-model review.

## Lifecycle and limits

The native transparent panel follows desktop Spaces without taking focus on appearance. Mouse monitors exist only while it is open and use the visible stage regions to pass empty-space clicks through. Sleep, context loss, and relevant usage-consent revocation close the hearing. Display changes repair stage placement.

Automatic presentation uses a conservative, permission-free window-bounds check to suppress hearings over full-screen windows, plus the panel's full-screen exclusion behavior. A borderless window covering an entire display may also suppress a hearing. No Screen Recording or Accessibility permission is requested by this feature.

Court records use the independent `court.experiment.v1` UserDefaults key. Unreadable or unsupported-version data disables court writes until explicit reset; normal pin storage remains independent.

## Validation

The Debug DeeDock target has compiled with Xcode 27 on macOS. No tests or automated visual suites were run. Inert previews cover ordinary hearings, witness streaming, preparation, errors, completed hearings, and expanded lore with local accessibility flags.

Native inspection confirmed the German Features entry, disabled initial opt-in, both sample controls, and on-device model availability. A witness sample was requested with automatic hearings left off. Subsequent desktop-control state changes prevented verification of its stage and completion. No real app pins were changed.

Native acceptance remains to be recorded for transparency over varied wallpapers, click-through behavior, movement between displays, saved placement, Spaces/full-screen behavior, keyboard and VoiceOver, reduced motion/transparency, live model consistency, cancellation, and Pin again after intervening edits. Compilation does not establish those behaviors.
