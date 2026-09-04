import SwiftUI

/// One inheritable preset controls the whole app-name presentation.
struct DockTooltipSettingsPane: View {
    let source: SettingsValueSource
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        SettingsCard(title: .settingsAppNames, footnote: .settingsAppNamesHelp) {
            SettingsStackedRow {
                DockTooltipPreview(preset: source.value.tooltipPreset, edge: source.value.edge,
                                   reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
            }
            DockTooltipPicker(selection: source.binding(\.tooltipPreset), edge: source.value.edge,
                              reduceTransparency: reduceTransparency)
                .settingsOverride(source.context, field: .tooltipPreset)
        }
    }
}
