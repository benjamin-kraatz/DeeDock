import SwiftUI

/// A sidebar entry: the pane's glyph tile beside its name.
struct SettingsCategoryRow: View {
    let category: SettingsCategory
    let isSelected: Bool

    var body: some View {
        Label {
            Text(category.title)
        } icon: {
            SettingsIconTile(glyph: category.glyph, colors: category.tileColors)
                .scaleEffect(isSelected ? 1.06 : 1)
        }
        .padding(.vertical, 3)
        .animation(.snappy(duration: 0.25), value: isSelected)
    }
}
