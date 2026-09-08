# Launcher app suggestions

App suggestions are off by default. **Settings → Features → App suggestions** controls the feature for every display.
When enabled, DDock learns from application activity observed while it runs. It does not import earlier Launcher history.

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
New observations affect the next presentation. An empty history can produce no suggestions, and learning does not require waiting 90 days.

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
Reset preserves deliberate exclusions and the feedback-prompt preference. There is no personalized model file to restore after reset.

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
Safety caps retain at most 20,000 events, 10,000 examples, 2,000 app feedback records, and 2,000 impressions.
The atomic history file is limited to 16 MiB. When it exceeds that limit, the newest half of each collection is retained until it fits.
These limits can shorten the retained history on busy installations. Exclusions and consent are separate preferences and do not expire.

History lives in `~/Library/Application Support/DDock/LauncherSuggestions/history-v1.json`, with private filesystem permissions and exclusion from system backup.
Unreadable or unsupported storage stops the feature and leaves normal Launcher use available. Reset is the explicit recovery action.
No detailed behavioral history is added to general logs or exported diagnostics.

## Predictor and validation

The initial predictor combines decayed frequency, transitions, time, weekday, Dock Mode, recent apps, and recency.
Recent examples receive more weight, using a 21-day decay scale. Feedback adjusts normalized scores for matching contexts.
These constants are tuning defaults, not measured optima.

The [model decision and measurements](LAUNCHER-SUGGESTIONS-MODEL.md) describe the Core ML feasibility prototype and chronological synthetic comparison.
The [acceptance record](ACCEPTANCE.md#dee-26-app-suggestions) separates compilation and focused tests from native scenarios that remain unverified.
