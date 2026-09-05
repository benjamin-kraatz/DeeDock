# Numeric setting resets

DEE-5 covers every numeric control currently exposed in Settings. The 17 slider rows also support direct number entry. Each row supplies its factory value through `SettingsSliderRow.defaultValue`; the Focus Session duration stepper uses the same reset button.

| Settings area | Numeric settings | Factory value source |
| --- | --- | --- |
| Appearance | Corner radius, icon size, magnification, item spacing | Corresponding properties of `DockSettings.defaults` |
| Position | Along-edge offset, edge distance | Corresponding properties of `DockSettings.defaults` |
| Fading | Idle opacity, idle delay, fade-out duration, restore duration | Corresponding properties of `DockSettings.defaults` |
| Behavior | Custom activation length, zone depth, zone offset, reveal delay, hide delay, animation duration | Corresponding properties of `DockSettings.defaults.behavior` |
| Features, Window Peek | Hover delay | `DockSettings.defaults.windowPeekHoverDelay` |
| Features, Focus Sessions | Default duration in minutes | `FocusSessionsDocument().minutes` |

Reset appears beside the value only when the stored effective value differs from the factory value. It assigns the exact model value through the existing binding or controller. Slider snapping does not alter the reset value. The existing model normalization and persistence remain authoritative.

For a display inheriting a nonfactory shared value, factory reset creates an explicit override. For an existing override, it replaces only that override's value. **Use Shared Setting** removes the override and follows the shared value, even when the shared value differs from the factory value. An override equal to the factory value therefore has no factory-reset button but still offers **Use Shared Setting**.

Changes continue through `DockSettingsStore.update`, `DisplayProfilesStore.update`, or `FocusSessionController.configure`. Dock update callbacks and preview bindings use those same stores. Resetting the Focus Session default duration affects the next session and preserves the active session.

## Deliberate exclusions

- `backgroundOpacity` remains persisted for compatibility but has no numeric Settings control. This issue adds no control for it.
- The running Focus Session's remaining time and five-minute extension are session state and actions, not factory-default preferences.
- Display dimensions, preview geometry, counters, identifiers, and persistence versions are derived or internal values, not editable settings.
- Size presets, layout choices, booleans, and other categorical settings are not numeric input controls.

Existing availability rules still apply. Fading controls are disabled when idle fading is off or Reduce Transparency is enabled. Custom activation length is shown only in Custom mode. Storage-recovery gates continue to disable persistent edits.

## Validation

The focused unsigned Debug app build succeeded with Xcode 27. Packaged English and German `Localizable.strings` contain all five reset and inheritance labels/help strings, including the setting-name placeholder.

Static review covers all `SettingsSliderRow` call sites and the sole `Stepper`, model normalization, override creation/removal, save callbacks, and English/German reset strings. Tests, preview rendering, app launch, and native UI checks were not run because they require explicit authorization.

Hands-on acceptance remains pending:

1. Change each slider and direct numeric field, reset it, and confirm the exact default and disappearance of Reset.
2. Set a shared value away from its factory default. Reset an inheriting display and confirm it becomes customized. Change the shared value again and confirm the display keeps its factory override.
3. Choose Use Shared Setting and confirm the display follows later shared edits. Restart and verify both overridden and inherited settings.
4. Confirm the dock and relevant Settings previews update, including zone geometry, fading, and animation timing.
5. Change and reset Focus Session duration during an active session. Confirm the current timer remains unchanged and the next session uses the default.
6. Exercise Reset and Use Shared Setting by keyboard and VoiceOver in English and German, including an invalid numeric draft and controls disabled by availability rules.
