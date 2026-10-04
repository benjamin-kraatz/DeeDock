# Usage analytics

DOKK sends anonymous usage data to PostHog (EU cloud) so we can see which features are used, in
which configuration, Dock Mode, and appearance. This page is the complete list of what is sent
and the rules for adding to it. It is linked from Settings › General › Privacy.

## What is never collected

These are prohibited in every product event, property, and person property. There is one
exception, [Apple Intelligence observability](#apple-intelligence-observability), which sends
prompt and answer text and is described below.

- App names and bundle IDs. This is the rule most likely to be broken by accident, because almost
  everything in a dock is named after an app.
- Icons, file names, paths, and file contents.
- Window titles and URLs.
- Launcher and search query text.
- Names a person typed: Dock Modes, watches and watch presets, Shortcuts, drives, displays.
- Clipboard contents.
- Apple Intelligence prompts and output.
- Error message strings. Failures are reported as enum codes.
- Display names and serial numbers.

Settings that hold a path, such as the markup folder, are reported only as "set" or "not set".

## How the code enforces it

- `AnalyticsEvent` (`DeeDock/Analytics/Events/AnalyticsEvent.swift`) is the only way to send an
  event. Its cases take enums, Bools, and numbers. No case takes a `String`.
- `AnalyticsValue` has no `String` initializer. Text becomes a value in three places only:
  an enum that conforms to `AnalyticsToken`, `AnalyticsFileType`, and the settings reflection
  in `AnalyticsValue.swift`, which emits property names and enum case names and reduces any
  text field to a Bool.
- Property keys written in source must be string literals (`StaticString`).
- `PostHogAnalyticsBackend.swift` is the only file that imports the SDK.

Two channels sit outside this guard and take free-form text: `Analytics.captureAI` and
`Analytics.log`. Both are described below. Do not add callers that pass anything but literals to
`Analytics.log`.

When you add an event: add a case to `AnalyticsEvent`, map it in `AnalyticsEvent+Record.swift`,
and add it to the tables below. If a value you want to send is text, it does not belong in
analytics. Make it an enum or a count.

## Consent

- Analytics are on by default during 0.x and can be turned off in Settings › General › Privacy.
- A new user sees an informational page in the first-launch tour. Nothing is sent before that
  page, or the Privacy card in Settings, has been on screen. Events from before that moment wait
  in memory and are discarded if the app quits first.
- People updating from a version without analytics get no notice.
- Turning sharing off takes effect immediately: collection stops, counters are cleared, and
  events not yet uploaded are deleted.
- The stored consent record carries a notice version (`AnalyticsConsentStore.currentNoticeVersion`),
  so 1.0 can ask again by raising it.
- "Keep an anonymous profile" controls PostHog person profiles. "Reset" on the Anonymous ID row
  replaces the random ID.

## Builds and channels

| Build | Sends | `channel` |
| --- | --- | --- |
| Direct (Developer ID) | yes | `direct` |
| Debug | only with the debug-menu switch "Debug: Send Analytics" | `debug` |

Both share one PostHog project. A build without a project token sends nothing, and the
Privacy card then shows "This build does not send usage data." No token is hard-coded.

## Supplying the PostHog token

The token and host are two build settings, `POSTHOG_PROJECT_TOKEN` and `POSTHOG_HOST`. `Configuration/Direct-Info.plist` copies them into the `DOKKAnalyticsAPIKey` and
`DOKKAnalyticsHost` keys, which `AnalyticsCredentials` reads at launch.

### Running from Xcode

Xcode does not read `.env` files, and a scheme's environment variables only reach the running
process, not the build. Builds made in Xcode take both settings from a local xcconfig file:

1. Copy `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig`.
2. Set `POSTHOG_PROJECT_TOKEN` to the project token (it starts with `phc_`).
3. Leave `POSTHOG_HOST` as it is for the EU cloud. `//` starts a comment in an xcconfig file, so
   the URL is written `https:/$()/eu.i.posthog.com`.
4. Clean the build folder once, so Info.plist is regenerated.

`Local.xcconfig` is git-ignored. `App.xcconfig` includes it with `#include?`, so a checkout
without the file still builds and sends nothing. Every scheme picks it up.
Each checkout and worktree needs its own copy.

To see events arrive during development, run the **DeeDock Release** scheme. It builds the
Release configuration, which sends like a shipped build with `channel=direct`. The Debug
configuration sends only while the debug-menu switch is on.

### Command line and CI

`xcodebuild` takes the two settings from its environment when no `Local.xcconfig` defines them.
`.env.example` lists the names. A value in `Local.xcconfig` wins over the environment.

The Release workflow passes both settings to `xcodebuild archive` as arguments. The token comes
from the `POSTHOG_PROJECT_TOKEN` repository secret. The host comes from the `POSTHOG_HOST`
repository variable and falls back to `https://eu.i.posthog.com`. The archive step fails when
the built `Info.plist` lacks a `phc_` token or an `https` host, so a release can no longer ship
with analytics silently off.

## What the SDK sends by itself

DOKK does not modify SDK payloads and installs no sanitizer. IP handling and GDPR processing
happen in PostHog-side middleware.

- Default properties stay as the SDK sets them, including `$app_version`, `$app_build`,
  `$os_version`, `$device_model`, `$device_name` (the Mac model's marketing name), `$locale`,
  `$timezone`, and screen size.
- Lifecycle events: `Application Installed`, `Application Updated`, `Application Opened`,
  `Application Backgrounded`. DOKK sends no events of its own for these, and none for
  "active today".
- Session replay is off. It does not exist for macOS in the SDK.
- Crash autocapture is on (`errorTrackingConfig.autoCapture`). A crash is sent as an
  `$exception` event with its stack trace on the next launch.

### Autocapture must be rechecked on every SDK upgrade

Autocapture is left at what the SDK offers. On macOS in posthog-ios 3.89.0 that is lifecycle
events only: element autocapture (`captureElementInteractions`) is compiled for iOS and Mac
Catalyst, not AppKit.

If a later posthog-ios version adds AppKit element autocapture, it would read accessibility
labels. In DOKK, the accessibility label of a dock tile is the app's name, so autocapture would
send app names. Before raising the SDK version:

1. Read the SDK changelog for autocapture, element capture, and macOS changes.
2. Confirm that no AppKit or SwiftUI-on-macOS element capture is enabled by default.
3. If one exists, keep it off, or mark the dock views as excluded, before shipping.

The project requires posthog-ios 3.59.3 up to the next major version, and `Package.resolved`
currently holds 3.89.0. Updating the resolved version is the moment to run this check.

## Context on every event

Registered with the SDK's `register`, so every event carries them.

| Property | Value |
| --- | --- |
| `channel` | `direct`, `debug` |
| `chip_family`, `chip_generation`, `chip_tier` | for example `apple_silicon`, `3`, `pro` |
| `app_language` | `en`, `de`, `other` |
| `appearance` | `light`, `dark` |
| `reduce_motion`, `reduce_transparency`, `increase_contrast` | Bool |
| `display_count`, `builtin_display_count`, `external_display_count` | exact |
| `main_display_builtin`, `main_display_width`, `main_display_height`, `main_display_scale` | points and backing scale |
| `secondary_N_display_*` | the same for each other display, numbered from 1 |
| `dock_count` | displays that host a dock |
| `dock_mode_count` | exact |
| `system_dock_hidden` | whether the macOS Dock has released its desktop space |
| `login_item` | `not_registered`, `enabled`, `requires_approval`, `not_found`, `unknown` |
| `updates_check_automatically`, `updates_install_automatically`, `updates_install_when_idle` | Bool |
| `dock_edge`, `dock_alignment`, `dock_position_reference` | main dock |
| `dock_icon_size`, `dock_magnification` | exact |
| `dock_auto_hide`, `dock_activation_location`, `dock_animation_style` | |
| `dock_indicator_style`, `dock_tooltip_preset`, `dock_launch_animation` | |
| `dock_show_background`, `dock_fade_when_idle` | |
| `window_peek_enabled`, `window_peek_layout` | |
| `show_shelf`, `show_trash`, `show_session_capsules`, `show_volumes`, `soap_bubble_effects` | |

The marketing version, build number, and macOS version come from the SDK's default properties.

## Person profile

Set with the SDK's person-properties call at launch, after "Reset", and with each
`usage_summary`. It holds everything above plus the full configuration:

- `shared_*`: every field of the shared dock settings (`DockSettings`), reflected automatically.
- `main_*` and `secondary_N_*`: for each display, the effective settings after its overrides,
  plus `dock_enabled`, `overrides_shared_defaults`, `override_count`, `pinned_app_count`,
  `pinned_folder_count`, and `running_app_count`.

Keys are the Swift property names in snake case, for example `shared_icon_size` or
`main_behavior_auto_hide`. Numbers are exact. A new field in `DockSettings` appears here without
a code change.

## Events

Every feature event carries a `trigger` where the entry point can tell: `click`, `keyboard`,
`voice_over`, `menu`, `drag`, `spring_load`, `hover`, `hotkey`, `automatic`, `launcher`.
Entry points that do not mark themselves report `click`.

### Settings and periodic

| Event | Properties |
| --- | --- |
| `setting_changed` | `key`, `old_value`, `new_value` (enum, Bool, or exact number), `area` (`shared_dock`, `display`, `atmosphere`, `menu_bar`), `display_role` |
| `usage_summary` | `period_seconds`, the counters below, and per-display `pinned_app_count`, `pinned_folder_count`, `running_app_count` |

`setting_changed` is generated by comparing two versions of a settings model, so new settings are
tracked without new analytics code. Edits to one setting within two seconds, such as a slider
drag, become one event. Configuration history is the sequence of these events.

`usage_summary` is sent about once a day and at quit. Counters are exact, kept on disk between
launches, and reset when sent:

| Counter | Counts |
| --- | --- |
| `tooltip_shown_hover`, `tooltip_shown_keyboard` | labels shown |
| `auto_hide_reveal_<zone>_<edge>` | auto-hide reveals by activation zone and dock edge |
| `spring_load_folder`, `spring_load_drive`, `spring_load_downloads` | spring-loaded opens |
| `peek_enlarge` | Window Peek enlarge-on-hover |
| `drag_to_eject_armed` | a dragged drive crossing the eject distance |
| `app_activated_<trigger>` | app tile activations |
| `soap_bubble_burst` | bursts played |

Magnification itself is not tracked. Its settings are.

### Onboarding

| Event | Properties |
| --- | --- |
| `onboarding_step_reached` | `step`, `step_index` |
| `onboarding_step_skipped` | `step` |
| `onboarding_finished` | `last_step`, `completed`, `system_dock_hidden` |
| `onboarding_completed` | none. Sent once, the first time the tour is completed or dismissed. |

### Stacks

| Event | Properties |
| --- | --- |
| `stack_opened` | `kind` (`downloads`, `folder`, `drive`), `presentation`, `sort`, `trigger` |
| `stack_presentation_changed` | `presentation`, `kind`, `trigger` |
| `stack_sorted` | `sort`, `item_count` |
| `stack_quick_look` | `file_type`, `trigger` |
| `stack_item_opened` | `file_type`, `is_folder`, `trigger` |
| `stack_drop` | `operation` (`copy`, `move`), `item_count`, `file_type`, `target`, `outcome` |
| `smart_grouping` | `source`, `result` (`generated`, `cached`, `failed`), `duration`, `candidate_count`, `failure` |

### Window Peek, portals, Watch

| Event | Properties |
| --- | --- |
| `peek_opened` | `trigger`, `card_count`, `total_window_count`, `layout`, `style`, `size` |
| `peek_window_chosen` | `trigger` |
| `peek_window_action` | `action`, `outcome`, `trigger` |
| `markup` | `action`, `has_marks` |
| `portal_pinned` | `source`, `outcome` |
| `watch_setup_opened` | `trigger` |
| `watch_started` | `uses_phrase`, `plays_sound`, `completion`, `uses_preset`, `has_region` |
| `watch_detected` | `detection` (`change`, `phrase`), `duration`, `check_count` |
| `watch_ended` | `reason`, `duration`, `check_count` |

### Launcher

| Event | Properties |
| --- | --- |
| `launcher_opened` | `source`, `file_count` |
| `launcher_searched` | `query_length`, `result_count`, `kind`. Never the text. |
| `launcher_result_activated` | `kind`, `reveal`, `trigger` |
| `launcher_suggestion_accepted` | `trigger` |
| `launcher_tool_opened` | `tool` |
| `launcher_file_action` | `action`, `input_count`, `source`, `file_type`, `status` |
| `launcher_assistant_asked` | `query_length`, `result_count`, `outcome` |

### Dock Modes

| Event | Properties |
| --- | --- |
| `mode_switched` | `source` (`menu_bar`, `picker`, `settings`, `launcher`, `prepare_workspace`, `focus_session`, `previous_mode`), `mode_count` |
| `dock_mode_activated` | none. Sent with every `mode_switched`. |
| `mode_edited` | `action` (`created`, `duplicated`, `deleted`), `mode_count` |
| `workspace_prepared` | `step_count`, `completed_step_count`, `outcome`, `duration` |
| `workspace_recipe_started`, `workspace_recipe_completed`, `workspace_recipe_canceled` | none |

### Dock extras and pins

| Event | Properties |
| --- | --- |
| `shelf` | `action`, `item_count`, `source`, `trigger` |
| `session_capsule` | `action`, `window_count`, `capsule_count`, `trigger` |
| `trash` | `action`, `item_count`, `outcome`, `trigger` |
| `drive` | `action`, `kind`, `trigger` |
| `drive_ejected` | `kind`, `outcome` (`ejected`, `blocked`, `failed`), `forced`, `blocker_count`, `trigger` |
| `pin_changed` | `action` (`pin`, `unpin`, `reorder`), `kind`, `count`, `source` (`menu`, `voice_over`, `keyboard`, `drag`, `launcher`, `other`). Never which app. |

### Tools and focus

| Event | Properties |
| --- | --- |
| `app_melt` | `action`, `pair_count`, `outcome` |
| `patch_bay` | `action`, `cable_count`, `outcome` |
| `clipboard_museum` | `action`, `kind`, `item_count` |
| `clipboard_capture_enabled` | none |
| `discovery_callout` | `callout`, `action` (`shown`, `opened`, `snoozed`, `dismissed`) |
| `tool_opened` | `tool`, `trigger` |
| `focus_dock_entered` | `trigger` |
| `focus_dock_command` | `command` |
| `focus_session` | `action` |

Atmosphere has no events of its own. Its settings are reported through `setting_changed` with
`area = atmosphere`.

## File types

Events that involve a file send its uniform type identifier as `file_type`.

- `public.*` and `com.apple.*` identifiers are sent as they are.
- Any other identifier is declared by a third-party app and would reveal that the app is
  installed. It is replaced by its nearest system ancestor, found by walking the type's
  supertypes. There is no table of known types.
- The type is derived from the file extension. The file is not read.
- A drop of mixed types sends no `file_type`.

## Apple Intelligence observability

Every request DOKK makes to the on-device model is also sent as a PostHog `$ai_generation`
event (`DeeDock/Analytics/Context/AIObservability.swift`). It carries a trace and session ID,
the span name, latency, and, because `capturesContent` is `true`, the full prompt (`$ai_input`)
and the full answer (`$ai_output_choices`).

This is the one place where prohibited content leaves the device. Depending on the feature the
prompt or answer contains:

| Span | Content sent |
| --- | --- |
| `launcher_robi_selection`, `launcher_robi_review` | the typed task and the names of installed apps |
| `clipboard_wall_label` | the copied text and the generated label |
| `session_capsule_compose` | window titles, recognized window text, the generated summary |
| `fusion_compose` | the instruction, window titles and text, the generated result |
| `semantic_stack_organize` | file and folder names, the generated group titles |
| `dock_rumour_compose`, `dock_rumour_revise` | pinned app names, the generated dialogue |
| `window_search_image_match` | the search phrase and the model's description of the window |
| `window_watch_explanation` | the model's description of what changed in the window |
| `atmosphere_mood_palette` | the typed mood and the generated colors |

These events pass the same consent gate as everything else. The Privacy card and the tour say
that Apple Intelligence requests and answers are shared in full. Setting `capturesContent` to
`false` keeps latency and span names and drops the text.

## Logs

`Analytics.log` sends a PostHog log line with typed attributes. It is used for the three
workspace-recipe lines ("workspace recipe started", "completed", "canceled") with
`recipe_step_count`. Existing `os.Logger` output is not forwarded.

## Not covered

- There is no schema test that compares this page with `AnalyticsEvent`. Keep them in step by hand.
