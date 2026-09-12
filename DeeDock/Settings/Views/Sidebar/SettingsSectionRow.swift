import SwiftUI

/// A sidebar entry: the section's glyph tile beside its name.
struct SettingsSectionRow: View {
    let section: SettingsSection
    let isSelected: Bool
    #if DIRECT_DISTRIBUTION
    @Environment(\.appUpdater) private var updater
    #endif

    var body: some View {
        Label {
            Text(section.title ?? .settingsGeneral)
        } icon: {
            SettingsIconTile(glyph: section.glyph, colors: section.tileColors)
                .overlay(alignment: .topTrailing) {
                    #if DIRECT_DISTRIBUTION
                    if section == .general, updater?.awareness.showsIndicators == true {
                        UpdateAwarenessBadge(diameter: 7)
                            .offset(x: 2, y: -2)
                    }
                    #endif
                }
        }
    }
}
