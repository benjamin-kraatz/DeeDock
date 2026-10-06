# Notification feed

Implemented on `feat/notification-panel` for [DEE-115](https://linear.app/d-zwei/issue/DEE-115/collect-incoming-notification-banners-in-a-dokk-notification-feed). The user-facing name is **Notification Feed** (German: **Mitteilungsverlauf**). [The user guide](GUIDE.md#notification-feed) describes how it behaves.

This page records why the feature was requested, what a prototype measured on 2026-10-06, and how the shipped feature is built. The measurements are facts about one Mac.

## The request

A customer who rarely opens the macOS Notification Center asked for a place in DOKK that collects incoming notifications. A banner stays on screen for about five seconds. After that, the only record is in the Notification Center sidebar, which this customer does not open. A notification that arrives while they look at another display or another window is lost to them.

One customer asked. No usage data supports or contradicts the request, which is why DEE-115 has low priority.

## What the prototype measured

The prototype is a pair of macOS apps outside this repository. AXonNC observes the NotificationCenter process through the Accessibility API and lists what it reads. NotificationEmitter posts test notifications with `UNUserNotificationCenter`. The source is on Benn's machine at `/Volumes/BENNPortable/Projects/play/AXonNC` and is in no remote. The reader is `AXonNC/NotificationWatcher.swift`.

Test machine: macOS 27.0.1 build 26A434, Xcode 27.0, one 2560 × 1440 display, German system language.

### Where a banner lives

The process is `com.apple.notificationcenterui`. Desktop widgets are windows of the same process, with subrole `AXUnknown`. A banner window has subrole `AXSystemDialog` and covers the whole display.

| Level | Role | Identifying attribute |
| --- | --- | --- |
| 0 | `AXWindow` | `AXSubrole` = `AXSystemDialog` |
| 1 | `AXGroup` | `AXSubrole` = `AXHostingView` |
| 2 | `AXGroup` | none |
| 3 | `AXScrollArea` | none |
| 4 | `AXGroup` | `AXSubrole` = `AXNotificationCenterBanner`, `AXIdentifier` = a UUID |
| 5 | `AXStaticText` | `AXIdentifier` = `title`, `subtitle`, or `body`. The text is in `AXValue` |

A notification without a subtitle has no `subtitle` child. The window title stayed `Notification Center` on the German system, while the application title and the banner's action names were German. Match on roles, subroles, and identifiers, never on a title.

The banner has no `AXTitle`, and `AXImageData` returned nothing. The tree contains no bundle identifier and no icon. The only trace of the sending app is the banner's `AXDescription`, which reads `App, Title, Subtitle, Body`. A notification from `osascript` produced `Skripteditor, Third Title, Sub, Third body`. The app name is the localized display name.

The system prompt that asks whether an app may send notifications has subrole `AXNotificationCenterAlert`. Its description holds only the title and the body, with no app name in front.

### Which events fire

`AXObserverAddNotification` on the application element returned success for `kAXWindowCreatedNotification` and `kAXLayoutChangedNotification`.

- A banner that arrives with no other banner on screen creates a new window. `AXWindowCreated` fires, and the title and the body are readable inside that callback.
- A banner that arrives while another banner is on screen reuses the window. No `AXWindowCreated` fires. `AXLayoutChanged` fires for the new banner element, which has a new UUID. A reader that listens only for window creation misses this banner.
- `AXLayoutChanged` fires two to four times for each banner.

Measured lifetime, with times in seconds since the observer started:

| Event | Banner alone | Second banner 1.5 s after the first |
| --- | --- | --- |
| Banner appears | 4.568, `AXWindowCreated` | 2.726, `AXLayoutChanged` only |
| Exit animation starts | 9.568 | 7.718 |
| Elements destroyed | 10.074 | 8.233 |

A banner holds for 5.0 s and its elements are gone 0.5 s later. At creation the banner frame was at x = 2576 on a 2560-point display, because the banner slides in from outside the screen. Position does not tell you whether a banner is visible.

One run did not fit this pattern. A window was created, the prototype read its banner in the callback, and the window was destroyed 0.3 s later. The cause is unknown. Read the banner on the first event and do not expect the window to stay alive.

### The sidebar is a different tree

When the person opens the Notification Center sidebar, a window is created that contains a group with `AXIdentifier` = `AXNotificationListItems`. That group holds old notifications as `AXNotificationCenterBanner` and `AXNotificationCenterBannerStack` elements. The same window also holds the widgets. A notification kept the UUID it had as a banner. The prototype skips this group. Without that rule, opening the sidebar would add every old notification to the feed as new.

### End-to-end results

- Two `osascript` notifications 1.5 s apart: both captured.
- A burst of three from NotificationEmitter 1.5 s apart: all three captured, with app name, title, and body, and with the subtitle where one was set.
- A body that contains a comma, `348 files copied, 2.1 GB total.`: the app name was still extracted correctly.
- The notification permission prompt: captured, with no app name.

## What the prototype did not test

- Focus modes and Do Not Disturb.
- An app whose banner style is None, or whose previews are hidden.
- More than one display, full-screen apps, and Spaces.
- Sleep, display sleep, screen lock, and fast user switching.
- A relaunch of the NotificationCenter process. The prototype reattaches when the process ID changes, but no test exercised that path.
- Notifications with action buttons, attachments, or grouped stacks.
- A notification that arrives while the sidebar is open. The prototype ignores it.
- `AXPress` on a banner.
- Any macOS version other than 27.0.1, and any system language other than German.
- The Accessibility grant flow. The verification runs inherited the terminal's grant.
- CPU and energy cost over hours of use.

## Limits of this approach

These follow from reading the banner and are not bugs to fix later.

**The feed sees only what macOS presents as a banner.** A notification that Focus holds back, or that goes straight to the sidebar, never appears in the tree the reader observes. For the customer this is probably acceptable, because their complaint is about banners they missed. It must be stated in the UI and in the user guide, or the feed will look unreliable.

**The tree is undocumented.** The Accessibility API is public. The structure of NotificationCenter's windows is not, and a macOS update can change it without notice. `AXStatusLabel` in [Badge memory](BADGE_MEMORY.md) carries the same risk. The reader must fail closed: an unknown structure yields no entries, never wrong ones.

**The sending app is a guess.** DOKK receives a localized display name. Two apps can share a name, and an app can post under a name that matches no installed bundle. Resolve the name against the application catalog and show a generic icon when the match is missing or ambiguous. Per-app counts on dock tiles would depend on this guess, so they are out of the first slice.

**An entry cannot replay the notification.** Once the banner is gone, its element is gone. A feed entry can activate the sending app when the name resolves. It cannot open the exact message, and clearing an entry does not clear the notification in macOS.

No public API lists other apps' notifications. The notification database that macOS keeps on disk is private and was not evaluated.

## Design as built

Source lives in `DeeDock/Dock/NotificationFeed`: `Model` (entry, parser, store, app resolver), `Reading` (reader and lifecycle controller), `Panel` (popover coordinator and state), and `Views` (tile, glyph, popover, settings card).

### Reading

`NotificationFeedReader` follows `DockBadgeReader`.

- The observer's run-loop source sits on the main run loop. Its callback only posts `NotificationFeedReader.changedNotification`.
- Every `AXUIElementCopyAttributeValue` call runs on a private serial queue with a 0.2 s messaging timeout per element. AX handles never leave the queue; a pass returns `NotificationBannerReading` values.
- The observer is registered on NotificationCenter's application element for `kAXWindowCreatedNotification` and `kAXLayoutChangedNotification`. If either registration fails, the pass reports that it is not observing.
- A pass walks windows with subrole `AXSystemDialog` to depth five, stops at `AXNotificationListItems`, and collects `AXNotificationCenterBanner` and `AXNotificationCenterAlert` elements. An element that disappears mid-pass (`kAXErrorInvalidUIElement`) is skipped; any other AX error fails the whole pass, which yields no entries.
- `NotificationBannerParser` holds the app-name rule from the prototype, plus trimming. `DeeDockTests/NotificationFeedTests.swift` covers it.

### Lifecycle

`NotificationFeedController` owns one reader for every dock.

- It reads only while the setting is on, at least one dock exists, Accessibility is trusted, NotificationCenter runs, and the Mac is awake with this session active. Sleep, display sleep, and an inactive session pause it and keep the entries.
- Each change signal starts one pass after 100 ms of coalescing, and passes never overlap.
- A banner exposed before its texts is read again after 0.3 s, at most three times in a row.
- A failed pass, or one that could not register the observer, retries with backoff from 2 s to 30 s. Without that, no further change signal would arrive.
- `NSWorkspace` launch and termination notifications for `com.apple.notificationcenterui` restart the reader, so a relaunched NotificationCenter is picked up without polling. Whether macOS posts these notifications for that agent has not been confirmed on a Mac.
- No public notification reports an Accessibility grant. While the feature is on and access is missing, a 2 s timer checks `AXIsProcessTrusted()`, and `didBecomeActive` checks it too. The timer stops once access is granted or the feature is turned off, and starts again only if access is revoked while the feature is on. `NotificationFeedTests` covers these transitions with an injected trust check.
- Turning the feature off removes every observer and timer and forgets the entries.

### Storage

`NotificationFeedStore` keeps entries in memory, newest first, deduplicated by banner UUID. It holds 100 entries and remembers 512 UUIDs, dropping the oldest of each first. Removing or clearing an entry keeps its UUID remembered, so a banner still on screen is not added again. Nothing is written to disk.

### Interface

- **Tile.** A movable utility tile, `notification-feed`, joins the end of the saved utility order. Its artwork is a brass `bell.fill` glyph, plus a Lucide bell in the Line icon style. A red count badge shows entries that arrived since the feed was last opened. The tile reads that count from the store, so an arrival redraws one badge without rebuilding the docks. The bell rings once per arrival unless Reduce Motion is on. The context menu offers Open, Clear, and Settings. VoiceOver gets the tile name, the unread count, and a Clear action.
- **Popover.** Built on `DeeDock/Dock/Popover`, 380 × 480 points. Each row shows the app icon or a placeholder, the sender, relative arrival time, title, subtitle, and body. Rows unread at open carry an accent dot. Clicking a row opens the sending app through `ApplicationCatalog.open`, but only when the name matches exactly one running or installed app. Rows also offer Copy Text and Remove. Header **Clear All** empties the feed. The keyboard works once the panel has focus: arrows, Return, Delete, Command-C, Command-Delete, and Escape. Empty states explain listening, waiting, and missing access. Opening the popover marks everything read, and entries that arrive while it is open stay read.
- **Settings.** **Settings → Features → Notification Feed**, in the same group as App badges. The card has the switch (off by default), the Accessibility row with **Enable**, a status line, a transparency note on how notification text is handled, and **Clear Notifications**. Turning the switch on never prompts.
- **Discovery.** A launch-announced Discovery tip offers **Turn On**. See [Discovery](DISCOVERY.md).

### Privacy

This is the first DOKK feature that reads message text from other apps. Clipboard Museum reads clipboard contents, but only what the person copied. [Badge memory](BADGE_MEMORY.md) still captures no message text; the two features share no storage.

- Notification titles, subtitles, bodies, and app names never go to analytics. [Usage analytics](ANALYTICS.md) lists notification text under "What is never collected".
- Analytics get `notification_feed_opened` (entry count, unread count, trigger), `notification_feed_closed` (entry count, duration, whether Clear All was used), and the setting toggle through `setting_changed`. Nothing is sent when a notification arrives.
- The README's permissions table lists the feature under Accessibility.
- The settings card, popover footer, and Discovery tip say that the text stays on this Mac. The copy explains how DOKK handles the text. It does not warn people away from the feature.

## Decisions

1. Interface: a dock tile with a popover.
2. Entries do not survive a relaunch.
3. System alerts such as permission prompts are listed, under "System".
4. An entry opens the sending app only when its name resolves to exactly one app.
5. Name: Notification Feed.
6. The screen locking does not clear the feed. Clearing it would lose exactly the banners this feature exists to keep. While the screen is locked, macOS does not show banners anyway.

## Acceptance still required

- Enable the feature on a Mac where DOKK has no Accessibility grant. Confirm that DOKK asks only after the Enable click and starts reading without a relaunch.
- Send single notifications, an overlapping pair, and a burst. Confirm one entry for each, in order.
- Open and close the Notification Center sidebar. Confirm that no old notification enters the feed.
- Turn on a Focus mode and send a notification. Confirm that the feed stays empty and that the UI copy explains why.
- Repeat with hidden previews, a second display, a full-screen app, and after sleep and screen lock.
- Quit the NotificationCenter process and confirm that the reader reattaches.
- Check English and German copy, VoiceOver labels, keyboard access, and Reduce Transparency.
- Measure idle CPU with the feature on and no notifications arriving. Desktop widgets belong to the same process; check whether their layout changes wake the reader.
- Quit the NotificationCenter process and confirm that `NSWorkspace` reports it, so the reader reattaches without waiting for the 30 s retry.
- On the first launch of this version, confirm that the Discovery tip appears about a minute after launch, that **Turn On** enables the feed, and that it opens Settings on the feed page when access is missing. Confirm that an already-enabled feed suppresses the tip.
- Confirm that the tile's badge and bell ring on arrival, that the ring is skipped with Reduce Motion, and that an arrival does not reset the dock's idle fade.
- Check that the analytics events carry counts only: `notification_feed_opened`, `notification_feed_closed`, and `setting_changed` for `showNotificationFeed`, and nothing on arrival.
