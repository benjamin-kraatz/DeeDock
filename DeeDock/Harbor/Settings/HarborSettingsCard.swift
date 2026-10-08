import SwiftUI

/// Harbor's settings: the global shortcut and the optional dock tile.
///
/// Neither switch prompts for permission; the permission card below it does that on request.
struct HarborSettingsCard: View {
    @Binding var shortcut: Bool
    @Binding var tile: Bool
    /// False when the shortcut is on but another app owns the combination.
    let shortcutAvailable: Bool
    let locked: Bool

    var body: some View {
        SettingsCard(title: .harborName, footnote: .harborSettingsHelp) {
            SettingsToggleRow(title: .harborShortcutToggle, subtitle: .harborShortcutToggleHelp, isOn: $shortcut)
            if shortcut && !shortcutAvailable {
                SettingsStatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange,
                                  message: Text(.harborShortcutConflict)) {
                    EmptyView()
                }
            }
            SettingsToggleRow(title: .harborShowTile, subtitle: .harborShowTileHelp, isOn: $tile)
        }
        .disabled(locked)
    }
}

#if DEBUG
#Preview("Harbor settings") {
    HarborSettingsCard(shortcut: .constant(true), tile: .constant(false), shortcutAvailable: true, locked: false)
        .padding().frame(width: 620)
}

#Preview("Harbor settings, shortcut taken") {
    HarborSettingsCard(shortcut: .constant(true), tile: .constant(true), shortcutAvailable: false, locked: false)
        .padding().frame(width: 620)
}
#endif
