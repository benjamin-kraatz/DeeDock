import SwiftUI

/// Harbor's settings: the global shortcuts, the optional dock tile, and app names in the strip.
///
/// One switch controls both shortcuts, because they do the same thing. Each registers on its own,
/// so the status row names the one another app holds and the one that still works.
/// Neither switch prompts for permission; the permission card below it does that on request.
struct HarborSettingsCard: View {
    @Binding var shortcut: Bool
    @Binding var tile: Bool
    @Binding var appNames: Bool
    /// Combinations another app owns while the shortcuts are on. Empty when both work.
    let unavailableShortcuts: Set<HarborShortcut.Combination>
    let locked: Bool

    var body: some View {
        SettingsCard(title: .harborName, footnote: .harborSettingsHelp) {
            SettingsToggleRow(title: .harborShortcutToggle, subtitle: .harborShortcutToggleHelp, isOn: $shortcut)
            if shortcut, let conflict {
                SettingsStatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange, message: Text(conflict)) {
                    EmptyView()
                }
            }
            SettingsToggleRow(title: .harborShowTile, subtitle: .harborShowTileHelp, isOn: $tile)
            SettingsToggleRow(title: .harborShowAppNames, subtitle: .harborShowAppNamesHelp, isOn: $appNames)
        }
        .disabled(locked)
    }

    private var conflict: LocalizedStringResource? {
        switch (unavailableShortcuts.contains(.primary), unavailableShortcuts.contains(.alternate)) {
        case (true, true): .harborShortcutConflict
        case (true, false): .harborShortcutConflictPrimary
        case (false, true): .harborShortcutConflictAlternate
        case (false, false): nil
        }
    }
}

#if DEBUG
#Preview("Harbor settings") {
    HarborSettingsCard(shortcut: .constant(true), tile: .constant(true), appNames: .constant(false),
                       unavailableShortcuts: [], locked: false)
        .padding().frame(width: 620)
}

#Preview("Harbor settings, Shift-Command-Space taken") {
    HarborSettingsCard(shortcut: .constant(true), tile: .constant(true), appNames: .constant(false),
                       unavailableShortcuts: [.alternate], locked: false)
        .padding().frame(width: 620)
}

#Preview("Harbor settings, both shortcuts taken, German") {
    HarborSettingsCard(shortcut: .constant(true), tile: .constant(true), appNames: .constant(true),
                       unavailableShortcuts: [.primary, .alternate], locked: false)
        .environment(\.locale, Locale(identifier: "de"))
        .padding().frame(width: 620)
}
#endif
