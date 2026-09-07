import SwiftUI

/// A sidebar entry: the section's glyph tile beside its name.
struct SettingsSectionRow: View {
    let section: SettingsSection
    let isSelected: Bool

    var body: some View {
        Label {
            Text(section.title ?? .settingsGeneral)
        } icon: {
            SettingsIconTile(glyph: section.glyph, colors: section.tileColors)
        }
    }
}
