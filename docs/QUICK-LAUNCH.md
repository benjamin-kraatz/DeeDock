# Quick Launch keys

Quick Launch keys open dock apps by position. Control-Option-1 through Control-Option-9 open the
first nine apps. Control-Option-0 opens the tenth. The shortcuts act on the dock under the pointer.
If the pointer is on a display without an enabled dock, they act on the primary enabled dock.
Windows users know this from the taskbar's Windows key plus number shortcuts. The macOS Dock has no
equivalent.

Turn it on in **Settings → Features → Quick Launch keys**. It is off by default because it claims
system-wide shortcuts. The setting applies to every display and has no per-display override.

## What a number means

- Numbers count application icons from the dock's leading end: left on top and bottom docks, top
  on side docks. Pinned apps come first, then running-only apps, in the order they are drawn.
- Folders, Downloads, the Launcher, Capsules, Shelf, Trash, Action tiles, and section controls are
  skipped. A collapsed section's apps are not on the dock, so they get no number.
- The mapping is recomputed from the current entries each time the dock changes and again when a
  shortcut is pressed. It is never saved.
- Each dock has its own numbering. With the pointer on a secondary display, Control-Option-2 opens
  the second app on that display's dock.

## What a shortcut does

A shortcut does what clicking the icon does, through the same code path:

- It launches an app that is not running and activates one that is.
- On the frontmost app, it hides all of that app's windows. Press again to show them.
- A cold launch plays the icon's launch animation. Soap bubbles follow their own setting.

An empty slot beeps. Both a hit and a miss show the numbers on the icons for about 1.6 seconds.
The app that was opened gets an accent-colored chip. A hidden dock stays hidden: the shortcut still
works but does not reveal the dock.

Shortcuts do nothing while a dock drag, a dock context menu, or the file picker is active, or while
the Launcher is open on the target dock. Those interactions own the pointer and keyboard.

## Focus Dock

With Quick Launch keys on, Focus Dock shows the numbers for the whole session. Plain number-row
digits open the numbered app and select it, like Return on a selected app. They do not apply the
hide toggle. Digits on the numeric keypad are not bound. Browse Local History also uses keyboard
focus, but it shows no numbers and digits keep their history behavior.

## Conflicts and permissions

Registration uses Carbon `RegisterEventHotKey`, the same mechanism as the Command-Shift-Space
window search shortcut. It needs no Accessibility or Input Monitoring permission, so turning the
feature on never prompts.

Registration is exclusive (`kEventHotKeyExclusive`). If another app already registered one of the
combinations, DDock leaves that combination alone. The settings card then lists the unavailable
shortcuts and offers **Try Again** for when the other app has quit. Shortcuts defined in System
Settings → Keyboard → Keyboard Shortcuts may take precedence without being reported as conflicts.

Key codes are physical positions, so the shortcuts stay on the number row under AZERTY, Dvorak, and
other layouts. The chip shows the digit printed on a US keyboard.

## Accessibility

- VoiceOver announces each numbered icon's shortcut as custom content, for example
  "Quick Launch keys: Control-Option-3". This does not depend on the chips being visible.
- Chips are decorative and hidden from VoiceOver. They never take clicks.
- Reduce Transparency draws chips on an opaque fill instead of glass.
- Reduce Motion replaces the chip's scale-in with a fade.

## Implementation map

| Responsibility | File |
| --- | --- |
| Entries to numbered slots, key codes, labels | `DeeDock/Dock/QuickLaunch/QuickLaunchSlots.swift` |
| Hot-key registration and conflict reporting | `DeeDock/Dock/QuickLaunch/QuickLaunchShortcuts.swift` |
| Per-panel hint visibility and flash deadline | `DeeDock/Dock/QuickLaunch/QuickLaunchHints.swift` |
| Icon chip | `DeeDock/Dock/QuickLaunch/Views/QuickLaunchNumberChip.swift` |
| Settings card | `DeeDock/Dock/QuickLaunch/Views/QuickLaunchSettingsCard.swift` |
| Dock targeting and lifecycle | `DockCoordinator.configureQuickLaunch()` and `performQuickLaunch(slot:)` |
| Slot resolution, click-equivalent action, Focus Dock digits | `DockPanelController.performQuickLaunch(slot:)` and `handleKey(_:)` |

The coordinator registers the hot keys only while the preference is on and at least one dock is
enabled. It unregisters them when either condition ends and when DDock stops. Each panel owns its
hints and cancels the flash deadline when the feature turns off or the panel stops.

## Validation status

Written and reviewed in a Linux container without Xcode. It has **not** been compiled, run, or
tested. `DeeDockTests/QuickLaunchTests.swift` covers numbering, key mapping, persistence, and hint
lifecycle, but it has not been run. See the [acceptance notes](ACCEPTANCE.md#quick-launch-keys).
