import SwiftUI

/// Bottom-edge placement, previewed on a stand-in display.
/// Physical left and right are independent of interface reading direction.
struct PositionSettingsPane: View {
    @Binding var reference: DockSettings.PositionReference
    @Binding var alignment: DockSettings.Alignment
    @Binding var horizontalOffset: Double
    @Binding var bottomDistance: Double

    var overrideContext: SettingsOverrideContext? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(title: .settingsPreview, footnote: .settingsPreviewDisclaimer) {
                DockPlacementPreview(reference: reference, alignment: alignment,
                                     horizontalOffset: horizontalOffset,
                                     bottomDistance: bottomDistance)
            }
            SettingsCard(title: .settingsCardAnchor, footnote: .settingsDockOverlapHelp) {
                SettingsPickerRow(title: .settingsPositionReference,
                                  options: DockSettings.PositionReference.settingsOptions,
                                  selection: $reference)
                    .settingsOverride(overrideContext, field: .positionReference)
                SettingsPickerRow(title: .settingsAlignment,
                                  options: DockSettings.Alignment.settingsOptions,
                                  selection: $alignment)
                    .settingsOverride(overrideContext, field: .alignment)
            }
            SettingsCard(title: .settingsCardFineTuning, footnote: .settingsPositionHelp) {
                SettingsSliderRow(title: .settingsHorizontalOffset, unit: .settingsPoints,
                                  value: $horizontalOffset, range: -1000...1000, step: 1,
                                  minimumSymbol: "arrow.left", maximumSymbol: "arrow.right")
                    .settingsOverride(overrideContext, field: .horizontalOffset)
                SettingsSliderRow(title: .settingsBottomDistance, unit: .settingsPoints,
                                  value: $bottomDistance, range: 0...300, step: 1,
                                  minimumSymbol: "arrow.down.to.line", maximumSymbol: "arrow.up")
                    .settingsOverride(overrideContext, field: .bottomDistance)
            }
        }
    }
}

#if DEBUG
#Preview("Position pane") {
    @Previewable @State var reference: DockSettings.PositionReference = .usableDesktop
    @Previewable @State var alignment: DockSettings.Alignment = .center
    @Previewable @State var offset: Double = 0
    @Previewable @State var bottom: Double = 8
    ScrollView {
        PositionSettingsPane(reference: $reference, alignment: $alignment,
                             horizontalOffset: $offset, bottomDistance: $bottom)
            .padding(24)
    }
    .tint(SettingsCategory.position.tint)
    .frame(width: 560, height: 640)
}
#endif
