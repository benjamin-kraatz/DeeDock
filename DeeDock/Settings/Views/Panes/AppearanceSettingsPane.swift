import SwiftUI

/// Requested size and hover scale, previewed above the controls that change them.
struct AppearanceSettingsPane: View {
    var edge: DockEdge = .bottom
    @Binding var iconSize: Double
    @Binding var magnification: Double
    @Binding var itemSpacing: Double
    @Binding var cornerRadius: Double
    @Binding var runningIndicatorStyle: DockSettings.RunningIndicatorStyle
    @Binding var animateIndicators: Bool

    var appearanceSettings = DockSettings.defaults
    var overrideContext: SettingsOverrideContext? = nil

    private var previewSettings: DockSettings {
        var settings = appearanceSettings
        settings.cornerRadius = cornerRadius
        return settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            SettingsCard(title: .settingsPreview, footnote: .settingsPreviewDisclaimer) {
                SettingsStackedRow {
                    DockAppearancePreview(edge: edge, iconSize: iconSize, magnification: magnification,
                                          itemSpacing: itemSpacing, runningIndicatorStyle: runningIndicatorStyle,
                                          appearanceSettings: previewSettings)
                }
            }
            SettingsCard(title: .settingsRunningIndicators, footnote: .settingsRunningIndicatorsHelp) {
                RunningIndicatorPicker(edge: edge, selection: $runningIndicatorStyle, animated: animateIndicators)
                    .settingsOverride(overrideContext, field: .runningIndicatorStyle)
                SettingsToggleRow(title: .settingsAnimateIndicators, isOn: $animateIndicators)
                    .disabled(!runningIndicatorStyle.animates)
                    .settingsOverride(overrideContext, field: .animateIndicators)
            }
            SettingsCard(title: .settingsCornerRadius, footnote: .settingsCornerRadiusHelp) {
                SettingsSliderRow(title: .settingsCornerRadius, unit: .settingsPoints,
                                  value: $cornerRadius, range: 0...100, step: 1,
                                  minimumSymbol: "square", maximumSymbol: "capsule",
                                  defaultValue: DockSettings.defaults.cornerRadius)
                    .settingsOverride(overrideContext, field: .cornerRadius)
            }
            SettingsCard(title: .settingsCardIcons, footnote: .settingsAppearanceHelp) {
                SettingsSliderRow(title: .settingsIconSize, unit: .settingsPoints,
                                  value: $iconSize, range: 32...96, step: 1,
                                  minimumSymbol: "square", maximumSymbol: "square.fill",
                                  defaultValue: DockSettings.defaults.iconSize)
                    .settingsOverride(overrideContext, field: .iconSize)
                SettingsSliderRow(title: .settingsMagnification, unit: .settingsMultiplier,
                                  value: $magnification, range: 1...2, step: 0.05,
                                  minimumSymbol: "magnifyingglass", maximumSymbol: "plus.magnifyingglass",
                                  defaultValue: DockSettings.defaults.magnification)
                    .settingsOverride(overrideContext, field: .magnification)
                SettingsSliderRow(title: .settingsItemSpacing, unit: .settingsPoints,
                                  value: $itemSpacing, range: 0...24, step: 1,
                                  minimumSymbol: "arrow.left.and.right", maximumSymbol: "arrow.left.and.right",
                                  defaultValue: DockSettings.defaults.itemSpacing)
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
    @Previewable @State var cornerRadius: Double = 22
    @Previewable @State var indicator: DockSettings.RunningIndicatorStyle = .plasma
    @Previewable @State var animate = true
    ScrollView {
        AppearanceSettingsPane(iconSize: $iconSize, magnification: $magnification, itemSpacing: $itemSpacing, cornerRadius: $cornerRadius,
                               runningIndicatorStyle: $indicator, animateIndicators: $animate)
            .padding(24)
    }
    .tint(SettingsCategory.appearance.tint)
    .frame(width: 560, height: 520)
}
#endif
