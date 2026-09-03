import SwiftUI

/// Requested size and hover scale, previewed above the controls that change them.
struct AppearanceSettingsPane: View {
    var edge: DockEdge = .bottom
    @Binding var iconSize: Double
    @Binding var magnification: Double
    @Binding var itemSpacing: Double

    var overrideContext: SettingsOverrideContext? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(title: .settingsPreview, footnote: .settingsPreviewDisclaimer) {
                DockAppearancePreview(edge: edge, iconSize: iconSize, magnification: magnification, itemSpacing: itemSpacing)
            }
            SettingsCard(title: .settingsCardIcons, footnote: .settingsAppearanceHelp) {
                SettingsSliderRow(title: .settingsIconSize, unit: .settingsPoints,
                                  value: $iconSize, range: 32...96, step: 1,
                                  minimumSymbol: "square", maximumSymbol: "square.fill")
                    .settingsOverride(overrideContext, field: .iconSize)
                SettingsSliderRow(title: .settingsMagnification, unit: .settingsMultiplier,
                                  value: $magnification, range: 1...2, step: 0.05,
                                  minimumSymbol: "magnifyingglass", maximumSymbol: "plus.magnifyingglass")
                    .settingsOverride(overrideContext, field: .magnification)
                SettingsSliderRow(title: .settingsItemSpacing, unit: .settingsPoints,
                                  value: $itemSpacing, range: 0...24, step: 1,
                                  minimumSymbol: "arrow.left.and.right", maximumSymbol: "arrow.left.and.right")
                    .settingsOverride(overrideContext, field: .itemSpacing)
            }
        }
    }
}

#if DEBUG
#Preview("Appearance pane") {
    @Previewable @State var iconSize: Double = 48
    @Previewable @State var magnification: Double = 1.4
    @Previewable @State var itemSpacing: Double = 4
    ScrollView {
        AppearanceSettingsPane(iconSize: $iconSize, magnification: $magnification, itemSpacing: $itemSpacing)
            .padding(24)
    }
    .tint(SettingsCategory.appearance.tint)
    .frame(width: 560, height: 520)
}
#endif
