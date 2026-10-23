# Running in Background

DOKK shows apps that macOS 27 reports as *Running in Background* the way the system Dock does: the tile stays, its indicator turns muted gray, the hover label gets a second line, and the context menu offers **Stop Running in Background**. [The user guide](GUIDE.md#use-the-dock) describes the behavior. This page records how macOS 27 produces the state, which private calls DOKK uses to read it, and the rules that keep reading and stopping safe.

The code is in `DeeDock/Dock/BackgroundApps/`.

## What macOS 27 does

Every app that Launch Services starts runs in its own resource coalition, a kernel group that also holds the helper processes the app starts. A helper registered through `SMAppService` is started by launchd in a coalition of its own and does not count toward the app. Before macOS 27, Launch Services dropped an app's record when its main process exited. On macOS 27 the record stays, marked `exited-with-subordinates`, as long as coalition members or non-foreground child applications are still alive. `lsappinfo list` shows these records.

The system Dock gives a tile only to records of the Foreground application type. Agents and menu bar apps that leave helpers behind get no tile there, and none in DOKK.

There is no public API for this state in the macOS 27 SDK. `NSWorkspace.runningApplications` drops the app the moment its main process exits, and `NSRunningApplication` has no property for it. Before this feature DOKK therefore removed such a tile, or showed a pinned one as not running, while the system Dock kept it.

## The private calls

`LaunchServicesBackgroundReader` looks up these symbols in CoreServices with `dlsym` and only reads:

- `_LSCopyMatchingApplications(session, options)` with `_kLSApplicationCopyMatchingApplicationsIncludeExitedApplicationsKey` set to true returns every application record in the login session (`kLSDefaultSessionID`, -2), exited ones included.
- `_LSCopyApplicationInformation(session, asn, keys)` copies the requested keys for one record. DOKK asks for:
  - `_kLSApplicationExitedButHasRemainingCoalitionPIDsOrNonForegroundChildrenApplicationsKey`, the background flag. Launch Services computes it on request, so it appears in the reply only when asked for by name.
  - `_kLSApplicationTypeKey`, compared against `_kLSApplicationForegroundTypeKey`.
  - `_kLSBundlePathKey`, `_kLSDisplayNameKey`, and `kCFBundleIdentifierKey`.
  - `_kLSApplicationCoalitionNonForegroundApplicationPIDsKey`, the coalition members that are not foreground apps.
  - `_kLSApplicationNonForegroundChildApplicationASNsArrayKey`, whose entries are read again for `_kLSPIDKey`.

The reader asks for the flag and the type first, because most records are ordinary running apps. Two exited records for one bundle, which happens when a relaunched app quits while the first instance's helpers still run, merge into one tile, and Stop ends both sets of processes.

## Fail-closed rules

The feature must never be visible when it cannot work. If anything below fails, DOKK behaves as it did before: no background tiles, no Stop item, no banner, no alert.

- The reader runs only on macOS 27. `dlsym` proves that a symbol exists, not that its signature is unchanged, and calling a changed signature could crash DOKK. A later release stays off until someone verifies it.
- A missing function or key switches the reader off with `missingInterface`.
- Every reply is type-checked before use, and any reply with a shape other than the verified one switches the reader off with `unexpectedResult`: a record list that is not an array, a record reply that is not a dictionary, or a value of another type. An explicit null counts as malformed, because Launch Services leaves absent values out. The background flag must be a `CFBoolean`, and a PID must be an integer that `pid_t` holds exactly; truncating 2³² + P would name process P. Every value in a reply is checked before any of them decides whether the record counts, so a malformed value cannot hide behind a filter that skips its record. It means the private interface changed, and the records that did parse could be wrong too, so DOKK shows none of them. A record that vanished before its reply is ordinary, because its app finished exiting, and is skipped. The parsing is separate from the private calls (`BackgroundRecordSource`), so tests feed it malformed replies.
- A read that fails while Stop runs counts the same as any other failed read.
- Once the reader reports a reason, `BackgroundApplicationMonitor` publishes nothing, removes its observers, and stays off for the rest of the session. DOKK logs the reason and sends the count-only `background_apps_unavailable` event once (see [Analytics](ANALYTICS.md)).
- An app is reported only if at least one of its remaining processes belongs to the current user and is alive. DOKK never shows a background state it could not end.

Reads are event-driven. Workspace launch, termination, wake, and session notifications start one, and a process-exit dispatch source on every remaining process starts one when that process exits. Reads run on a private serial queue, never on the main actor.

## Keeping the tile in place

Two details keep the dock from flickering or reordering.

When an app quits, the termination notification arrives before DOKK has read the new background record. `ApplicationCatalog` therefore waits up to 250 ms for a read that starts after the quit (`refreshAndWait(timeout:)`) and publishes both changes together. Other refreshes requested during that wait fold into it. Without the wait, an unpinned tile would vanish and come back a moment later.

`runningIDs` keeps meaning "regular processes", because the Launcher, the Hub, suggestions, and Window Peek depend on it. Unpinned tiles use a separate `dockOrderIDs` list that holds running and background apps together. An app keeps its entry while it moves between the two, so the tile does not jump to the end of the dock when the app quits or reopens.

## Stopping safely

`BackgroundApplicationMonitor.stopRunningInBackground(at:)` follows these rules:

- Each pass re-reads Launch Services and signals only the processes that belong to the app at that moment, so a helper started after the first pass is included.
- Only processes owned by the current user, other than launchd and DOKK itself.
- Only non-foreground coalition members and non-foreground child applications. A foreground app that shares the coalition has its own tile and is never touched.
- Each process is identified by its kernel audit token, which carries a per-instance version as well as the PID. Signals go through `proc_signal_with_audittoken`, and the kernel delivers them only while that exact instance is alive. The check happens in the kernel, at delivery, so no window remains between checking and signalling. The kernel reuses PIDs, so a PID alone could name an unrelated process by then.
- Each pass reads Launch Services twice and signals only identities that both reads list. A read captures an identity just after Launch Services lists the PID. If the PID was reused in between, the captured identity belongs to a process outside the app's coalition, which the second read does not list.
- Opening the app cancels a pending stop for good, even if the app quits again before the grace period ends, because the helpers it leaves then are not the ones the user asked to stop. While a regular instance runs, neither pass sends anything, because the new instance may use the same helpers.
- SIGTERM first. After 3 seconds, SIGKILL to whatever is still running.
- Failure is silent. The tile keeps its muted indicator until the processes actually exit. The menu action reports `failed` to analytics only when the app was no longer running in background.
- Tearing down the monitor cancels a pending SIGKILL pass.

The system Dock stops these apps with `_LSKillApplication(-2, asn, 4)`. The flag values are undocumented, and DOKK does not call it. Signalling identity-checked processes keeps DOKK on calls whose behavior it can check.

## Known limits

- DOKK mirrors Launch Services' attribution. Developers have reported on the Apple Developer Forums that the system Dock shows a helper under the wrong app ([thread 835214](https://developer.apple.com/forums/thread/835214), [thread 847300](https://developer.apple.com/forums/thread/847300)), and that the indicator can outlive every process ([thread 832557](https://developer.apple.com/forums/thread/832557)). DOKK only shows apps with a live process of the current user, so it does not inherit the last case. If Launch Services attributes a process to the wrong app, DOKK shows the same wrong tile, and Stop would end that process.
- The state is only as fresh as the last read. A read follows every relevant workspace event and every exit of a watched process. DOKK watches no event for a helper that a quit app starts later, so that helper appears with the next read, and Stop's fresh re-read includes it.
- Verified with a standalone harness on macOS 27.0.1, not in DOKK itself: a read takes about 3.4 ms; Launch Services already reports the background record when `didTerminateApplicationNotification` arrives; `refreshAndWait` resolves about 14 ms after the termination; Stop ends a helper that ignores SIGTERM through the SIGKILL pass within about 3.3 s; process-exit sources fire for processes that are not DOKK's children.
- The DOKK integration has not been exercised by hand. [Acceptance](ACCEPTANCE.md#running-in-background) lists the scenarios still to check.
