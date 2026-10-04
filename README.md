# DOKK

A native replacement for the macOS Dock. It looks and behaves like the Dock you already know, and adds what Apple left out: a dock on every display, exact placement, auto-hide you can tune, and window tools behind every icon.

[![Latest release](https://img.shields.io/github/v/release/benjamin-kraatz/DeeDock?label=release)](https://github.com/benjamin-kraatz/DeeDock/releases/latest)
![macOS 27](https://img.shields.io/badge/macOS-27-black?logo=apple)

## Install

1. Download `DDock.zip` from the [latest release](https://github.com/benjamin-kraatz/DeeDock/releases/latest).
2. Unzip it and move `DOKK.app` to your Applications folder.
3. Open DOKK.

DOKK requires macOS 27. It runs from the menu bar, and a short tour opens on first launch. The tour shows you where to hide the macOS Dock in System Settings. DOKK never changes the system Dock's settings itself.

DOKK updates itself. Choose **Check for Updates…** from its menu, or turn on automatic updates in **Settings → General**.

## What it does

The dock itself matches the system Dock: Liquid Glass, magnification, running indicators, app-name labels, and launch animations. From there you can change almost everything.

- Run one dock per display, each with its own pins. Settings are shared by default, and any display can override any of them.
- Put a dock on any screen edge, then align and offset it to the point.
- Turn on auto-hide with its own activation zone, reveal and hide delays, and ten animation styles. Docks can also fade when idle.
- Open folder stacks in Grid, List, or Smart view. Downloads, Trash, and external drives sit at the end of the dock, and you eject a drive by dragging it off.
- Rest on a running app to open Window Peek. From there you can pick a window, drop files into it, pin a live preview, watch a region for changes, or mark up a screenshot.
- Switch between Dock Modes, which are named sets of pins for every display. A mode can carry a recipe that opens apps, files, links, and Shortcuts.
- Carry files across Spaces and displays on the Shelf.
- Save what you were working on as a Session Capsule, and start a Focus Session timer from any mode.
- Search apps, windows, Shelf files, and Dock Modes from the App Launcher. Run Shortcuts from Action Tiles, and see app badges with a history of what changed.
- Drive the whole dock from the keyboard with Focus Dock. VoiceOver gets labels and actions for every tile, and DOKK respects Reduce Motion and Reduce Transparency.

The [user guide](docs/GUIDE.md) covers every feature and setting in detail.

## Permissions and privacy

DOKK works without special permissions. A few features need one, and DOKK asks only when you click **Enable** or **Allow** for that feature.

| Permission | Used by |
| --- | --- |
| Accessibility | Window lists in app menus, Window Peek window selection, App Fusion, app badges, and resuming Session Capsules |
| Screen Recording | Window Peek thumbnails and features that capture window contents, such as Session Capsules, markup, and window search. Also secondary docks that show only the apps with windows on their display |
| Automation for Finder | Opening and emptying the Trash, and App Fusion folder navigation |

DOKK has no account. Settings, pins, and history stay on your Mac. Features that use Apple Intelligence run the on-device model. App suggestions and Peek history learn from your activity, and both stay off until you opt in. DOKK makes three kinds of network request. It checks GitHub Releases for updates. It sends anonymous usage data to PostHog, which you can turn off in **Settings → General → Privacy**; [docs/ANALYTICS.md](docs/ANALYTICS.md) lists what is sent, including the requests and answers of Apple Intelligence features. When you use **Ask Robi** in the App Launcher, it looks up short descriptions of your Mac App Store apps through Apple's public lookup service.

## Project status

DOKK is in active development, and versions are still 0.x. Not every behavior has been checked by hand yet. The [acceptance notes](docs/ACCEPTANCE.md) list what has been validated and what is still open. Report problems in [GitHub Issues](https://github.com/benjamin-kraatz/DeeDock/issues).

## Build from source

You need Xcode 27 on macOS 27.

```sh
git clone https://github.com/benjamin-kraatz/DeeDock.git
open DeeDock/DeeDock.xcodeproj
```

Select the `DeeDock` scheme and **My Mac**, then run. To sign with your own Apple ID, change the team under **Signing & Capabilities**.

- [Developing DOKK](docs/DEVELOPMENT.md) covers architecture, source layout, tests, and localization.
- [AGENTS.md](AGENTS.md) has the contributor rules for people and coding agents.
- [Release instructions](docs/UPDATES.md) cover signing, notarization, and publishing updates.

## License

The source is public, but DOKK is not open source. You may read the code for personal, non-commercial evaluation and open pull requests. All other rights are reserved. See [LICENSE](LICENSE).
