import SwiftUI

/// A sidebar entry: the section's glyph tile beside its name.
struct SettingsSectionRow: View {
    let section: SettingsSection
    let isSelected: Bool
    @Environment(\.appUpdater) private var updater

    var body: some View {
        Label {
            Text(section.title ?? .settingsGeneral)
        } icon: {
            SettingsIconTile(glyph: section.glyph, colors: section.tileColors, size: 20)
                .overlay(alignment: .topTrailing) {
                    if section == .general, updater?.awareness.showsIndicators == true {
                        UpdateAwarenessBadge(diameter: 7)
                            .offset(x: 2, y: -2)
                    }
                }
        }
    }
}
