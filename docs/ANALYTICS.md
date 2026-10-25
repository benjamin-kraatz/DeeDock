# Usage analytics

DOKK sends anonymous usage data to PostHog (EU cloud) so we can see which features are used, in
which configuration, Dock Mode, and appearance. This page is the complete list of what is sent
and the rules for adding to it. It is linked from Settings › General › Privacy.

## What is never collected

These are prohibited in every product event, property, and person property. There are three
exceptions, all described below: [AI observability](#ai-observability),
which sends prompt and answer text; [surveys](#surveys), which send what a person chose or typed in
answer to a survey; and [Line icon coverage](#line-icon-coverage), which sends the bundle IDs of
public apps that have no Line glyph yet.

- App names and bundle IDs. This is the rule most likely to be broken by accident, because almost
  everything in a dock is named after an app. The only bundle IDs that leave the Mac are those of
  public apps without a Line glyph, in `line_icon_coverage`.
- Icons, file names, paths, and file contents.
- Window titles and URLs.
- Launcher and search query text.
- Names a person typed: Dock Modes, watches and watch presets, Shortcuts, drives, displays.
- Clipboard contents.
- Notification text: titles, subtitles, bodies, and the names of the apps that sent them. The
  notification feed reports counts only, and nothing when a notification arrives.
- Apple Intelligence prompts and output.
- Error message strings. Failures are reported as enum codes.
- Display names and serial numbers.

Settings that hold a path, such as the markup folder, are reported only as "set" or "not set".

## How the code enforces it

- `AnalyticsEvent` (`DeeDock/Analytics/Events/AnalyticsEvent.swift`) is the only way to send an
  event. Its cases take enums, Bools, numbers, and DOKK version numbers. No case takes a `String`.
- `AnalyticsValue` has no `String` initializer. Text becomes a value in five places only:
  an enum that conforms to `AnalyticsToken`, `AnalyticsFileType`, `AnalyticsVersion`, a list of
  `AnalyticsPublicAppIdentifier`, and the settings reflection in `AnalyticsValue.swift`, which
  emits property names and enum case names and reduces any text field to a Bool.
- Only `AnalyticsPublicApps` can create an `AnalyticsPublicAppIdentifier`, and only for a public
  app. See [Line icon coverage](#line-icon-coverage).
- `AnalyticsVersion` accepts only one to four dot-separated numbers, such as `0.13.5`. Update
  events use it for DOKK's own running and offered versions. Any other text, including a
  pre-release suffix, is dropped.
- Property keys written in source must be string literals (`StaticString`).
- `PostHogAnalyticsBackend.swift` is the only file that imports the SDK.

Three channels sit outside this guard and take free-form text: `Analytics.captureAI`,
`Analytics.captureSurvey`, and `Analytics.log`. All are described below. Do not add callers that
pass anything but literals to `Analytics.log`.

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
3. Leave `POSTHOG_HOST` as it is. `//` starts a comment in an xcconfig file, so
   the URL is written `https:/$()/clavicula.sebastian-kraatz.de`.
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
repository variable and falls back to `https://clavicula.sebastian-kraatz.de`. The archive step fails when
the built `Info.plist` lacks a `phc_` token or an `https` host, so a release can no longer ship
with analytics silently off.

## What the SDK sends by itself

DOKK does not modify SDK payloads and installs no sanitizer. IP handling and GDPR processing
happen in PostHog-side middleware.

- Default properties stay as the SDK sets them, including `$app_version`, `$app_build`,
  `$os_version`, `$device_model`, `$device_name` (the Mac model's marketing name), `$locale`,
  `$timezone`, and screen size.
- Lifecycle events from the SDK: `Application Installed`, `Application Opened`,
  `Application Backgrounded`. DOKK sends no events of its own for these, and none for
  "active today".
- `Application updated` is sent by DOKK on the first launch after the marketing version or
  the build changes. See [Updates](#updates). The SDK's own `Application Updated` compares
  the build number only and stores that build before it captures, so a capture that does
  not leave the device is never retried. Dashboards should use DOKK's event.
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
| `system_dock_tuck` | whether the [macOS Dock switch](GUIDE.md#tuck-away-the-macos-dock) is on |
| `system_dock_tucked_side` | `left` or `right` while DOKK's values are in place; absent otherwise, including after the quit-time restore |
| `login_item` | `not_registered`, `enabled`, `requires_approval`, `not_found`, `unknown` |
| `accessibility_access`, `screen_recording_access` | `enabled`, `not_enabled`, `unavailable` |
| `updates_check_automatically`, `updates_install_automatically`, `updates_install_when_idle` | Bool |
| `dock_edge`, `dock_alignment`, `dock_position_reference` | main dock |
| `dock_icon_size`, `dock_magnification` | exact |
| `dock_auto_hide`, `dock_activation_location`, `dock_animation_style` | |
| `dock_indicator_style`, `dock_tooltip_preset`, `dock_launch_animation` | |
| `dock_icon_style`, `dock_launcher_line_icons` | `native` or `line`; Bool, effective only with `line` |
| `dock_show_background`, `dock_fade_when_idle` | |
| `window_peek_enabled`, `window_peek_layout` | |
| `show_shelf`, `show_trash`, `show_session_capsules`, `show_notification_feed`, `show_volumes`, `soap_bubble_effects` | |
| `show_harbor_tile`, `harbor_shortcut_enabled`, `harbor_show_app_names` | |
| `hub_glass_tint` | whether the Hub tints its glass (Settings → Dock Extras → DOKK Hub → Tint the glass) |

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
| `setting_changed` | `key`, `old_value`, `new_value` (enum, Bool, or exact number), `area` (`shared_dock`, `display`, `atmosphere`, `menu_bar`, `updates`, `features`, `robi`), `display_role` |
| `settings_viewed` | `section` (`general`, `dock`, `atmosphere`, `modes`, `extras`, `windows_focus`, `suggestions_history`, `lookout`, `plugins`, `deprecated`, `display`), `page` (the `SettingsPage` case name, such as `windowPeek`; absent for a section's overview), `via` (`sidebar`, `overview`, `request`), `display_role` for a connected display |
| `usage_summary` | `period_seconds`, the counters below, and per-display `pinned_app_count`, `pinned_folder_count`, `running_app_count` |

`setting_changed` is generated by comparing two versions of a settings model, so new settings are
tracked without new analytics code. Edits to one setting within two seconds, such as a slider
drag, become one event. Configuration history is the sequence of these events.

Preferences kept outside those models are reported with `area = features` and a key from
`AnalyticsFeatureSetting`: `discovery_enabled`, `launcher_suggestions_enabled`,
`launcher_suggestions_paused`, `launcher_suggestion_prompts_enabled`, `clipboard_redact_secrets`,
`clipboard_curator_enabled`, `local_history_recording`, `local_history_replay`,
`peek_history_enabled`, `badge_memory_collect_focus`, `shelf_sort`, `shelf_presentation`,
`shelf_compost_days` (0 is off), `system_dock_tuck` (only for a click in Settings or the tour,
not for the restore at quit or the re-tuck at launch), and Lookout's `lookout_enabled`, `lookout_index_on_battery`
and `lookout_folder_count` (a count, after a folder was added or removed in Settings; never the folders). They are not part of the person profile, so a person who never
changed one is on its default.

`settings_viewed` with `via = request` means a menu item, a dock tile, or another feature opened
that destination. Settings opening at all is `tool_opened` with `tool = settings`.

`usage_summary` is sent about once a day and at quit. Counters are exact, kept on disk between
launches, and reset when sent:

| Counter | Counts |
| --- | --- |
| `tooltip_shown_hover`, `tooltip_shown_keyboard` | labels shown |
| `auto_hide_reveal_<zone>_<edge>` | auto-hide reveals by activation zone and dock edge |
| `spring_load_folder`, `spring_load_drive`, `spring_load_downloads` | spring-loaded opens |
| `peek_enlarge` | Window Peek enlarge-on-hover |
| `drag_to_eject_armed` | a dragged drive crossing the eject distance |
| `app_activated_<trigger>` | app tile activations, including the context menu's Open (`menu`) and Return in the focused dock (`keyboard`) |
| `soap_bubble_burst` | bursts played |
| `dock_group_expanded`, `dock_group_collapsed` | a collapsed app group opened or closed by click, keyboard, or VoiceOver |
| `badge_new` | an app badge became new: it appeared, or its count rose past the one last acknowledged. Line icon docks show this as the red ring; the count does not depend on icon style |
| `badge_acknowledged_dock_click`, `badge_acknowledged_activation`, `badge_acknowledged_frontmost` | a new badge was acknowledged by clicking its dock tile, by bringing its app to the front another way, or by arriving while its app was already frontmost |
| `badge_cleared_while_new` | the app removed a new badge before it was acknowledged in DOKK, for example after it was read on another device |
| `badge_detail_shown`, `badge_detail_shown_with_banner` | a Line dock label showed a badge count, without or with the newest notification banner under it |
| `lookout_search_with_results`, `lookout_search_without_results` | a Files search ended (the query was cleared, a result opened, or the Hub or the Files tab closed) while Lookout was on and its final results had arrived: with hits, or with the "nothing stands out" state. One per search, from the last query typed |
| `lookout_weak_matches_expanded` | the "Weaker matches" fold under Lookout's results was opened |

Magnification itself is not tracked. Its settings are.

Badge counters are plain counts. They never include the badge text, the app, or the banner.
Comparing `badge_acknowledged_dock_click` with the other acknowledgement routes across
`dock_icon_style` shows whether the Line ring sends people to the dock.

Lookout's counters and `lookout_result_opened` tune its strong/weak split (`LookoutRanking.strongRatio`, 0.5):
opens with `section = weak` against `section = strong`, and `lookout_weak_matches_expanded` against
`lookout_search_with_results`, show how often what people want sits inside the fold.

`lookout_image_search` shows how people search with pictures and how often the first picture waits for the
picture reader (`cold`); `lookout_result_opened` with `query = image` shows whether those searches end in an open.

Lookout's onboarding events show where setup stops: `lookout_setup_step_viewed` against `lookout_setup_abandoned`
by step, `lookout_access_result` for how often macOS's prompt is declined, and `lookout_model_download` for how long
the 865 MB download takes and why it fails. The first pass's file names, which onboarding shows, are never sent.

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
| `stack_path_copied` | `kind`, `relative`, `is_folder`, `trigger`. Copy Path or Copy Relative Path; the path is not sent. |
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
| `portal` | `action` (`paused`, `resumed`, `frozen`, `frame_saved`, `crop_opened`, `jumped`), `outcome` for `frame_saved` (`succeeded`, `failed`, `canceled`) and `jumped` |
| `portal_closed` | `duration`, `frame_count`, `frozen`, `cropped` |
| `file_handoff` | `action` (`shown`, `activated`, `copied`, `opened`), `file_count`, `exact_window`, `outcome`. `shown` fails when the dropped files cannot be routed. `opened` is `partial` when only some files opened. |

### Window Search and Fusion

| Event | Properties |
| --- | --- |
| `window_search_activated` | `evidence` (`metadata`, `text`, `capsule`, `historical_ocr`, `image`), `scope` (`live`, `captured`, `saved`), `query_length`, `result_count`, `outcome` |
| `window_search_closed` | `scope`, `query_length`, `result_count`, `activated`, `duration` |
| `fusion` | `step` (`capture`, `generate`, `save`), `outcome`, `failure` (`model_unavailable`, `context_limit`, `refused`, `invalid_output`, `timeout`, `capture_denied`, `capture_failed`, `save_failed`), `operation` (`compare`, `differences`, `checklist`) for `generate`, `duration` |

Cancelled Fusion work sends nothing. Opening Fusion from Window Peek or an App Melt pair is
`tool_opened` with `tool = fusion`, `trigger` `click` or `keyboard` from Peek and `automatic`
from App Melt.

### Launcher

| Event | Properties |
| --- | --- |
| `launcher_closed` | Sent when the Hub's Apps tab is hidden: another tab is selected or the Hub closes. `duration` (seconds since the tab appeared), `had_query` (search text present when it was hidden) |
| `launcher_searched` | `query_length`, `result_count`, `kind`. Never the text. |
| `launcher_result_activated` | `kind`, `reveal`, `trigger` |
| `launcher_suggestion_accepted` | `trigger` |
| `launcher_tool_opened` | `tool` |
| `launcher_file_action` | `action`, `input_count`, `source`, `file_type`, `status` |
| `launcher_assistant_asked` | `query_length`, `result_count`, `outcome` |
| `launcher_suggestions_shown` | `count`. Once per suggestion set, when it is first seen. |
| `launcher_suggestion_feedback` | `feedback` (`useful`, `not_now`). Never which app. |
| `launcher_suggestion_prompt_answered` | `answer` (`useful`, `not_useful`, `no_answer`) |

`launcher_tool_opened` now also fires for the System Settings clone. The Launcher now lives in the
DOKK Hub's Apps tab, so its events describe that tab. `launcher_opened` and the `dock_launcher_style`
context property were retired with the Compact and Full Launcher styles; `hub_opened` replaces
`launcher_opened`.

### DOKK Hub

| Event | Properties |
| --- | --- |
| `hub_opened` | `trigger` (`tile`, `focus_dock`, `file_drop`, `open_folder`, `lookout_setup` when Lookout's settings opened its onboarding over the Hub, `uninstall_relaunch` when DOKK relaunched for Full Disk Access and reopened an uninstall sheet), `tab` (`apps`, `windows`, `files`), `detached` (opened as a window rather than anchored to the dock) |
| `hub_tab_selected` | `tab`, `via` (`click`, `keyboard`) |
| `hub_detach_changed` | `detached` (`true` when the pin button made the Hub a window, `false` when it was attached again) |
| `hub_file_transfer` | `kind` (`copy`, `move`), `item_count`, `cross_volume`, `outcome` (`completed`, `cancelled`, `failed`). Never names or paths. |
| `hub_files_view_changed` | `view` (`list`, `icons`, `columns`) |
| `hub_files_sidebar_edited` | `action` (`add`, `remove`, `reorder`, `restore`, `undo`), `method` (`drag`, `drag_out`, `menu`, `shortcut`, `header_menu`, `settings`, `toast`, `popover`, `accessibility`), `item_count`. Never folder names or paths. |
| `hub_file_search_result_opened` | `scope` (`this_mac`, `folder`), `is_folder`. Never the query or the result. |
| `lookout_result_opened` | `section` (`names`, `strong`, `weak`), `rank` (1-based within its section; within its group for a search with a picture), `kind` (`screenshot`, `image`, `pdf`, `doc`, `folder`; absent for `names`), `match` (`meaning`, `words`, `both`; absent for `names`), `scope` (`this_mac`, `folder`), `is_lookup` (Lookout read the query as a code or number, so exact words counted double), `query` (`text` for typed words, `image` for a search with a picture or Find Similar). Sent for every Lookout result opened and, while Lookout is on, for every name result too, beside `hub_file_search_result_opened`. Never the query, the picture, a name, a path, or a score. |
| `lookout_image_search` | `source` (`drop` for a picture or indexed document dropped on the search field, `paste` for a picture pasted with ⌘V, `similar` for Find Similar on a search result from the preview column, the context menu, ⌘⇧L, or a result dragged onto the field, `browser` for Find Similar on a file in the Files browser, `hub_tile` for Find Similar in the Apps tab's file actions after a drop on the DOKK tile or the Apps tab), `cold` (the query service had to load its picture reader first; always `false` when a stored vector is used, which reads nothing). Sent when a search with a picture starts, once the stored vector is found or the picture reading starts. Never the picture, its name, or a path. |
| `lookout_setup_step_viewed` | `step` (`welcome`, `folders`, `access`, `download`, `first_pass`). Sent each time a step of Lookout's onboarding comes on screen, also when onboarding opens again at a step. |
| `lookout_setup_completed` | `folder_count` (folders chosen), `allowed_count` (macOS let Lookout read them), `skipped_count` (it didn't, or the folder was gone), `estimated_files` (the exact sum of the allowed folders' first-pass estimates), `index_on_battery`. Sent once, when the first pass starts and setup is applied. Never a folder or a path. |
| `lookout_setup_abandoned` | `last_step` (the step tokens above). Onboarding closed before setup: "Not now", Escape, or the Hub closing under it. |
| `lookout_model_download` | `outcome` (`completed`, `failed`, `cancelled`), `seconds` (whole seconds of the run), `error` (`network`, `server`, `host`, `checksum`, `incomplete`, `write`, `disk_space`; only when it failed). One per download run, a resumed run included. Never a URL or a path. |
| `lookout_access_result` | `outcome` (`allowed`, `denied`), `context` (`onboarding` for "Allow…", `settings` for "Add folder…"). One per request to read a folder; folders that need no prompt and quiet re-checks aren't reported. Never the folder. |
| `hub_window_activated` | `minimized` (the window was minimized before it was brought forward). Never titles or app names. |
| `hub_app_uninstall` | `outcome` (`completed`, `partial` when some selected items stayed, `dismissed` when the sheet closed before removal, `relaunched` when DOKK relaunched for Full Disk Access, `password_cancelled`, `still_open` when the app didn't quit, `failed` when macOS refused the app), `source` (`app_store`, `test_flight`, `installer`, `downloaded`, `unknown`), `data_count` (items found, not counting name-only matches), `selected_count`, `moved_count`, `protected_count` (items hidden without Full Disk Access), `related_selected` (name-only matches the user selected), `used_finder` (DOKK asked Finder to move something, usually with the password, even if the prompt was then cancelled), `unpinned`. Sent once per uninstall sheet. Never the app, a name, or a path. |

### Dock Modes

| Event | Properties |
| --- | --- |
| `mode_switched` | `source` (`menu_bar`, `picker`, `settings`, `launcher`, `prepare_workspace`, `focus_session`, `previous_mode`), `mode_count` |
| `dock_mode_activated` | none. Sent with every `mode_switched`. |
| `mode_edited` | `action` (`created`, `duplicated`, `deleted`, `renamed`, `reordered`, `recipe_updated`, `snapshot_saved`), `mode_count`, `step_count` for `recipe_updated` and `snapshot_saved` |
| `workspace_prepared` | `step_count`, `completed_step_count`, `outcome`, `duration` |
| `workspace_recipe_started`, `workspace_recipe_completed`, `workspace_recipe_canceled` | none |

### Dock extras and pins

| Event | Properties |
| --- | --- |
| `shelf` | `action` (`opened`, `added`, `removed`, `cleared`, `items_opened`, `dragged_out`, `pasted`, `previewed`, `revealed`, `copied`, `path_copied`, `relative_path_copied`), `item_count`, `source` (`clipboard` for `pasted`), `trigger` |
| `session_capsule` | `action`, `window_count`, `capsule_count`, `trigger` |
| `trash` | `action`, `item_count`, `outcome`, `trigger` |
| `drive` | `action` (`stack_opened`, `opened_in_hub`, `ejected`; `opened_in_finder` before the DOKK Hub), `kind`, `trigger` |
| `drive_ejected` | `kind`, `outcome` (`ejected`, `blocked`, `failed`), `forced`, `blocker_count`, `trigger` |
| `pin_changed` | `action` (`pin`, `unpin`, `reorder`), `kind`, `count`, `source` (`menu`, `voice_over`, `keyboard`, `drag`, `launcher`, `other`). Never which app. |
| `islands_edited` | `action` (`split`, `merge`, `rename`, `tint`, `reset`), `island_count` (pinned islands afterwards). Never an island's name or which apps it holds. Island look settings (`islands_*`) travel with the reflected settings events. |

### App tiles and Shortcuts

| Event | Properties |
| --- | --- |
| `app_menu_action` | `action` (`show_in_finder`, `hide`, `show`, `bring_all_to_front`, `quit`, `select_window`, `stop_running_in_background`), `outcome`, `trigger` (`menu`, `voice_over`). `stop_running_in_background` is `succeeded` when DOKK asked the app's leftover processes to end and `failed` when the app was no longer running in background; neither shows a message. |
| `background_apps_unavailable` | `reason` (`unsupported_system`, `missing_interface`, `unexpected_result`). DOKK could not read which apps macOS 27 runs in background and shows them as it did before. Sent at most once per launch. Never which app. |
| `documents_opened` | `source` (`drop`, `picker`), `file_count`, `file_type`, `outcome`. A cancelled Open Files… picker is `outcome = canceled` with `file_count = 0`. |
| `shortcut_run` | `source` (`tile`, `keyboard`, `drop`, `launcher`, `launcher_files`, `settings`), `file_count`, `outcome` (`succeeded`, `failed`, `canceled`), `duration` |
| `shortcut_tile` | `action` (`pinned`, `unpinned`, `moved`, `accepts_files_on`, `accepts_files_off`, `reset`), `tile_count`. Never which Shortcut. |

Workspace recipes and Watch run Shortcuts too. Those runs are part of `workspace_prepared` and
`watch_*`, not `shortcut_run`.

### Tools and focus

| Event | Properties |
| --- | --- |
| `app_melt` | `action`, `pair_count`, `outcome` |
| `patch_bay` | `action`, `cable_count`, `outcome` |
| `clipboard_museum` | `action`, `kind`, `item_count` |
| `clipboard_capture_enabled` | none |
| `discovery_callout` | `callout` (`clipboardMuseum`, `notificationFeed`, `islands`, `robi`), `action` (`shown`, `opened`, `snoozed`, `dismissed`) |
| `plugin_panel_opened` | `trigger`, `pinned_count` (plugin tiles in the dock) |
| `plugin_panel_closed` | `duration`, `stopped` (the plugin had stopped by then) |
| `plugin_stopped` | `panel_open`. A plugin process ended without DOKK asking, or never answered. |
| `plugin_restarted` | `surface` (`tile`, `panel`, `settings`) |
| `plugin_pin_changed` | `pinned`, `surface` (`tile`, `panel`, `settings`, `automatic` for a newly approved plugin) |
| `plugins_manage_opened` | `waiting_count` |
| `plugins_counted` | `enabled_count`, `waiting_count`, `disabled_count`, `pinned_count`. Sent when one of the counts changes, not on every check. |
| `line_icon_coverage` | `installed_app_count`, `installed_line_icon_count`, `installed_coverage` (0 to 1), `pinned_app_count`, `pinned_line_icon_count`, `pinned_coverage` (0 to 1), `missing_public_count`, `missing_unlisted_count`, `missing_bundle_ids` (array), `missing_pinned_bundle_ids` (array). See [Line icon coverage](#line-icon-coverage). |
| `notification_feed_opened` | `entry_count` (entries in the feed), `unread_count` (entries that arrived since it was last opened), `trigger` |
| `notification_feed_closed` | `entry_count` (entries left when it closed), `duration`, `cleared` (Clear All was used while it was open) |
| `harbor_opened` (Radar; Harbor is its internal name) | `trigger`, `window_count` (windows and chips across displays), `app_count`, `display_count`, `access` (`full`, `accessibility_only`, `screen_recording_only`, `none`) |
| `harbor_closed` | `outcome` (`window`, `app`, `restored`, `dismissed`, `interrupted`), `duration`, `searched`, `filtered` (the strip's app filter was used), `closed_windows` |
| `tool_opened` | `tool` (`window_search`, `local_history`, `fusion`, `badge_memory`, `system_settings_clone`, `settings`), `trigger` |
| `focus_dock_entered` | `trigger` |
| `focus_dock_command` | `command` |
| `focus_session` | `action` |
| `robi_opened` | `trigger` (`click` on Robi's face, `hotkey` for ⌥⇧⌘R), `context` (`selection`, `region`, `window`) |
| `robi_answered` | `model` (`on_device`, `claude`), `claude_model` (`haiku`, `sonnet`, `opus`; only when Claude answered), `intent` (`explain`, `translate`, `summarize`, `do_it`, `proofread`, `improve`, `shorten`, `formal`, `friendly`, `reply`, `action_items`; `suggested` for a question Apple Intelligence suggested; `custom` for a typed question), `outcome` (`answered`, `proposed`, `failed`, `stopped`, `unavailable`, `key_missing`), `duration` (for `stopped`, until the stop), `picture` (a region or window picture went to the model) |
| `robi_action` | `action` (`copy`, `replace`, `paste`, `run_command`, `point` for clicking a reference in the answer, which spotlights it on the window) |

Atmosphere has no events of its own. Its settings are reported through `setting_changed` with
`area = atmosphere`.

Turning the notification feed on or off is `setting_changed` with `key = showNotificationFeed`.

Robi's settings are reported through `setting_changed` with `area = robi`, by reflection over
`RobiSettings`: `isEnabled`, `answerModel`, `claudeModel`, `claudeEffort`, `suggestQuestions`, `attachWindowPicture`, `shortcutEnabled`, and the number of
excluded apps (never their bundle IDs). Where the tab was dragged (`tabPositions`, keyed by bundle
ID) is not reported at all, not even as a count. Whether an Anthropic API key is saved is not reported, and
the key itself never leaves the Keychain except in requests to Anthropic.

Robi's product events never include the app, the window, the selection, recognized text, the
question, the answer, or the proposed command. Its model calls go to LLM analytics in full, like
DOKK's other model calls; see [AI observability](#ai-observability).

Plugin events carry counts, durations, surfaces, and yes/no flags only. They never include which plugin, its bundle ID, its app, or anything the plugin shows.
The feed sends no event when a notification arrives, and none of its events carry text or app
names. `opened` for the `notificationFeed` callout means the person turned the feed on from it.

### App, permissions, and displays

| Event | Properties |
| --- | --- |
| `permission_requested` | `permission` (`accessibility`, `screen_recording`). DOKK asked macOS to prompt. |
| `permission_changed` | `permission`, `status` (`enabled`, `not_enabled`, `unavailable`). The status macOS reports differs from the one DOKK last read while running. A change made while DOKK was not running only shows in the registered context. |
| `login_item_changed` | `operation` (`register`, `unregister`, `cancel_request`), `outcome`, `status` (as `login_item`) |
| `system_dock_tuck` | `action` (`tuck_away`, `restore`, `reapply_on_launch`, `resume_restore`, `restore_on_quit`, `follow_edge`), `source` (`settings`, `onboarding`, `automatic`), `outcome` (`succeeded`, `failed`, `blocked`), `failure` (`managed`, `snapshot`, `write`, `restore`), `side` (`left`, `right`; absent once restored), `dock_restarted`, `kept_count` (settings a restore left alone because the person changed them) |
| `displays_changed` | `connected`, `disconnected`, `new_profile_count` (displays DOKK had never seen), `display_count`, `external_display_count`, `dock_count`. The arrangement at launch is not reported. |

`displays_changed` carries the new counts itself, because the registered context is refreshed a
second later.

`system_dock_tuck` is sent once per action of the macOS Dock switch. `reapply_on_launch` and
`follow_edge` are sent only when they rewrote the Dock's settings or failed, so an ordinary launch
with the switch on sends nothing. `restore_on_quit` is queued before analytics flushes at quit;
`dock_restarted` is false when the session was ending. The Dock's own values are never sent, only
the switch, the side, and the outcome.

### Updates

The update flow is reported from three places: Sparkle's delegate (`UpdateEngineDelegate`),
which sees every cycle including scheduled checks and silent downloads; the custom user driver,
which sees what a person is shown and chooses; and the update island's callouts.
`UpdateAnalytics` (`DeeDock/Updates/UpdateAnalytics.swift`) turns them into these events.
`Application updated` is separate: it carries only the properties in its row.

Every `update_*` event also carries:

| Property | Value |
| --- | --- |
| `current_version`, `current_build` | the running DOKK, for example `0.13.5` and `46` |
| `updates_check_automatically`, `updates_install_automatically`, `updates_install_when_idle` | Bool, the value at the moment of the event |
| `updates_automatic_install_allowed` | Bool, whether Sparkle permits automatic installs at all |
| `phase` | the update panel's phase: `idle`, `permission`, `checking`, `available`, `downloading`, `extracting`, `ready`, `installing`, `not_found`, `failed`, `installed`, `whats_new` |
| `offer_version`, `offer_build` | the offered update, once one is known |
| `offer_critical`, `offer_major`, `offer_informational` | Bool, from the appcast |
| `offer_staged` | Bool, DOKK holds an update Sparkle downloaded silently |
| `offer_staged_for` | seconds since that silent download became ready |

The `updates_*` settings repeat the registered context because the context is refreshed a second
after a change. An event sent in between would otherwise carry the old value.

| Event | Properties |
| --- | --- |
| `update_opened` | `source` (`menu_bar`, `app_menu`, `settings`, `dock_tile`, `callout`, `check_again`), `target` (`new_check`, `current_session`, `whats_new`, `unavailable`) |
| `update_permission_requested` | none. Sparkle asks whether it may check automatically. The answer is an `update_action`. |
| `update_check_started` | `check` (`user`, `background`, `information`), `source` for checks a person started |
| `update_found` | `check`, `user_initiated`, `duration` since the check started |
| `update_not_found` | `check`, `reason` (`on_latest`, `on_newer`, `system_too_old`, `system_too_new`, `hardware_unsupported`, `unknown`), `latest_version`, `latest_build`, `user_initiated`, `duration` |
| `update_offer_shown` | `stage` (`not_downloaded`, `downloaded`, `installing`), `user_initiated`, `presented` (false for a scheduled offer waiting behind the badge, tile, and callout) |
| `update_download_started` | `silent` (Sparkle's automatic driver, no UI) |
| `update_download_finished` | `outcome` (`succeeded`, `failed`, `canceled`), `silent`, `duration`, `expected_bytes` and `received_bytes` when the panel showed the download, error codes |
| `update_extracted` | `silent`, `duration` |
| `update_ready` | `silent`, `duration` since the download started. The update only needs an install and relaunch. |
| `update_action` | `action` (`allow_checks`, `decline_checks`, `install`, `skip`, `later`, `cancel`, `hide`, `retry_quit`, `done`, `learn_more`, `check_again`), `via` (`button`, `close`, `idle`) |
| `update_install_started` | `path` (`user`, `idle`, `on_quit`, `automatic`), `silent`, `waited` seconds since ready |
| `update_install_waiting_for_quit` | none. The installer waits for DOKK to quit and termination was refused. |
| `update_installed` | `path` (as above, or `manual` when DOKK did not start the install), `previous_version`, `previous_build`, `offer_version`, `offer_build`, `duration` from install start to this launch |
| `Application updated` | `previous_version`, `version`, `previous_build`, `build`. `update_source` (`automatic` for a scheduled check, `manual` for a check a person started) only when this launch's version and build equal the offered target stored with the install. `channel` (`direct` or `debug`), the same value as the registered context. Sent on the first launch whose version or build differs from the one stored last time. The first install sends nothing and only stores the version. With sharing off, the version is stored and the event is not sent. |
| `update_install_failed` | `path`, `offer_version`, `offer_build`, `duration`. DOKK started an install of a different build, the record was not cleared by an abort, and the next launch still runs the old build. |
| `update_failed` | `stage` (`startup`, `check`, `download`, `extract`, `install`), `check`, error codes |
| `update_release_notes_failed` | `reason` (`download`, `decode`, `render`, `whats_new`), error codes when there is an error |
| `update_cycle_finished` | `check`, `outcome` (`completed`, `no_update`, `canceled`, `failed`), `duration`, error codes |
| `update_callout` | `action` (`shown`, `opened`, `dismissed`), `kind` (`available`, `ready`, `installed`) |
| `update_whats_new_shown` | `source`, `previous_version` |

Error codes are `error_code` and `error_domain` (`sparkle`, `url`, `posix`, `cocoa`,
`os_status`, `other`), plus `underlying_error_code` and `underlying_error_domain` when the error
wraps another. Messages are never sent. Sparkle's codes are listed in `SUErrors.h`: for example
`2001` download, `3001` signature, `4005` installation, `4007` the person cancelled the
installer's authorization prompt, and `4012` no write permission.

Notes for dashboards:

- `update_failed` is the one event to count failures. `update_download_finished` with
  `outcome = failed` and `update_cycle_finished` with `outcome = failed` describe the same error
  from the download step and the end of the cycle. A cancelled installer prompt
  (`installationCanceled`, Sparkle `4007`) is not a failure: Sparkle delivers it through the
  same abort callback, and DOKK drops it. That abort also deletes the pending-install record,
  so a cancelled prompt is not reported later as `update_install_failed`.
- `Application updated` counts a successful version or build change. Pair it with
  `update_failed` for a success rate. It does not replace `update_installed`, which still
  carries the install path, the offer, and the duration.
- "No update" is `update_not_found` and ends the cycle with `outcome = no_update`.
- `update_installed` and `update_install_failed` are sent on the first launch after the install,
  so they carry the new build's `current_version`. A record written right before the install
  (`analytics.updates.pending-install.v1`) connects the two launches and is consumed once.
  `update_source` is attached only when the running version and build equal the offered
  target. A launch still on the old build, with a concrete different target, sends
  `update_install_failed`. Any other launch drops the record. A version change without
  that record is reported as `path = manual`.
- An update left for "Install on Quit", a resumed install that was not skipped, or a silent
  download DOKK still holds, is reported as
  `update_install_started` with `path = on_quit` when DOKK quits, because Sparkle installs it then
  without telling the app.
- A funnel over `update_check_started` → `update_found` → `update_download_started` →
  `update_ready` → `update_install_started` → `update_installed` covers both the interactive and
  the silent path. Split it by `silent` or `check`.
- The answer to Sparkle's permission prompt is `update_action` with `allow_checks` or
  `decline_checks`. Changes in Settings are `setting_changed` with `area = updates` and the keys
  `check_automatically`, `install_automatically`, and `install_when_idle`.

## File types

Events that involve a file send its uniform type identifier as `file_type`.

- `public.*` and `com.apple.*` identifiers are sent as they are.
- Any other identifier is declared by a third-party app and would reveal that the app is
  installed. It is replaced by its nearest system ancestor, found by walking the type's
  supertypes. There is no table of known types.
- The type is derived from the file extension. The file is not read.
- A drop of mixed types sends no `file_type`.

## AI observability

Every request DOKK makes to the on-device model, and every request Robi makes to Claude, is also
sent as a PostHog `$ai_generation` event (`DeeDock/Analytics/Context/AIObservability.swift`). It
carries a trace and session ID, the span name, the model and provider (`apple_foundation_models`
and `apple`, or `claude-haiku-5-5`, `claude-sonnet-5-5` or `claude-opus-5-5` and `anthropic`), latency, and, because `capturesContent` is
`true`, the full prompt (`$ai_input`, with the session's instructions as a system message where a
caller passes them) and the full answer (`$ai_output_choices`). Robi's answers also carry
`$ai_input_tokens` and `$ai_output_tokens` from the session's usage, and `$ai_is_error` with
`$ai_error` (the message the card shows) when a request fails. A stopped answer is reported with
what arrived before the stop. API keys are never part of an event: callers pass only text, and
anything in it shaped like an API key or access token (Anthropic, OpenAI, GitHub, AWS, Google,
Slack) is replaced with `[API key]` before sending, for every feature.
Pictures are not sent; a prompt that had one says `[Picture attached: …]`.

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
| `robi_answer` | Robi's instructions, the question, what the person picked (selected text, or the window's or region's text with landmark numbers and positions), the app's menu commands for Do It, and the answer, on this Mac or from Claude |
| `robi_suggest_questions` | Robi's instructions, what the person picked, and the suggested questions |

One Robi interaction, from the click to the card closing, is one trace: its suggested questions
and every answer asked in it share a `$ai_trace_id`.

These events pass the same consent gate as everything else. The Privacy card and the tour say
that requests and answers of AI features, Robi and Apple Intelligence ones, are shared in full, and
Robi's settings say so too. Setting `capturesContent` to
`false` keeps latency and span names and drops the text.

## Surveys

posthog-ios renders surveys on iOS only; on macOS the survey code is not compiled. DOKK therefore
uses PostHog surveys of type **API**: it fetches their definitions and draws them itself.

- Definitions come from `GET <POSTHOG_HOST>/api/surveys/?token=<project token>`
  (`PostHogSurveySource`), through the same proxy as ingestion. They are requested only while
  events are being collected, at most every six hours, or every 30 minutes after a failure
  (`AnalyticsSurveyCatalog`).
- A survey is offered only if DOKK can honor all of it. Surveys with a linked or targeting flag,
  link questions, or an "Other" choice with a text field are skipped. PostHog's own
  `internal_targeting_flag_key` is ignored, because DOKK records answered iterations locally
  (`launcher.suggestions.survey.seen.v1`).
- Branching follows PostHog's rules (`AnalyticsSurveyFlow`). Choice order is shuffled once per
  submission when the author asks.
- Events match what posthog-ios 3.89.0 sends: `survey shown`, `survey sent`, and
  `survey dismissed`, with `$survey_id`, `$survey_name`, `$survey_iteration`,
  `$survey_iteration_start_date`, `$survey_questions`, `$survey_response_<question id>`,
  `$survey_submission_id`, and `$survey_completed` or `$survey_partially_completed`. When the
  survey has partial responses enabled, each answer is sent as it is given, under one submission
  ID. No `$set` person properties are sent. `AnalyticsSurveyRecord` builds the payloads.
- The responses are text: the chosen option, and for open questions whatever the person typed,
  trimmed and cut to the author's maximum length. Typed answers can contain anything, including
  app names.
- Survey events pass the same consent gate as everything else. The Settings "recently sent" list
  shows them by name only.

| Survey | Where | Shown when |
| --- | --- | --- |
| App Recommendations Survey (`01a10ae5-3be4-0000-cb04-a670009cadbf`) | Below the Launcher's suggestions | Suggestions on, the feedback-question switch on, at least ten presentations over seven days, 30 days since the last feedback question, this iteration not yet answered or closed |

## Line icon coverage

`line_icon_coverage` tells us which Line glyphs to draw next. About 30 seconds after launch,
DOKK scans the Applications folders the way the Launcher does and checks every installed and
pinned app against the bundled Line catalog. It does this whatever icon style a dock uses, and
at most once every six hours, so most launches send nothing. A report goes out only while
sharing is on.

- **Installed** apps are those in `/Applications`, `~/Applications`, `/System/Applications`, and
  `/System/Library/CoreServices/Applications`, plus pinned apps stored elsewhere. Nested copies
  the Launcher hides are left out. **Pinned** apps are the application pins on every display,
  counted once each. An app without a glyph is counted in both groups when it is both.
- `missing_bundle_ids` lists apps without a glyph that are **public**: Apple ships the app inside
  macOS (a `com.apple.` ID under `/System/`), the bundled Homebrew or curated description catalog
  lists its bundle ID, or it carries a Mac App Store receipt. `missing_pinned_bundle_ids` is the
  pinned part of that list.
- Any other app without a glyph, such as an in-house build or a company's internal tool, is
  only counted in `missing_unlisted_count`. Its bundle ID, name, and path stay on the Mac.
- Nothing is looked up online to decide whether an app is public.

The event is the one place product analytics names apps. Keep it narrow: do not add app names,
paths, versions, or apps that have a glyph.

## Logs

`Analytics.log` sends a PostHog log line with typed attributes. It is used for the three
workspace-recipe lines ("workspace recipe started", "completed", "canceled") with
`recipe_step_count`. Existing `os.Logger` output is not forwarded.

## Not covered

- There is no schema test that compares this page with `AnalyticsEvent`. Keep them in step by hand.
