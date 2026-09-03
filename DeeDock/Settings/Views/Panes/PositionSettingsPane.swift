import SwiftUI

/// Physical edge placement, previewed on a stand-in display.
/// Physical left and right are independent of interface reading direction.
struct PositionSettingsPane: View {
    @Binding var edge: DockEdge
    @Binding var reference: DockSettings.PositionReference
    @Binding var alignment: DockSettings.Alignment
    @Binding var alongEdgeOffset: Double
    @Binding var edgeDistance: Double

    var overrideContext: SettingsOverrideContext? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(title: .settingsPreview, footnote: .settingsPreviewDisclaimer) {
                DockPlacementPreview(edge: edge, reference: reference, alignment: alignment,
                                     alongEdgeOffset: alongEdgeOffset,
                                     edgeDistance: edgeDistance)
            }
            SettingsCard(title: .settingsCardAnchor, footnote: .settingsDockOverlapHelp) {
                SettingsPickerRow(title: .settingsEdge, options: DockEdge.settingsOptions, selection: $edge)
                    .settingsOverride(overrideContext, field: .edge)
                SettingsPickerRow(title: .settingsPositionReference,
                                  options: DockSettings.PositionReference.settingsOptions,
                                  selection: $reference)
                    .settingsOverride(overrideContext, field: .positionReference)
                SettingsPickerRow(title: .settingsAlignment,
                                  options: DockSettings.Alignment.settingsOptions(edge: edge),
                                  selection: $alignment)
                    .settingsOverride(overrideContext, field: .alignment)
            }
            SettingsCard(title: .settingsCardFineTuning, footnote: .settingsPositionHelp) {
                SettingsSliderRow(title: .settingsAlongEdgeOffset, unit: .settingsPoints,
                                  value: $alongEdgeOffset, range: -1000...1000, step: 1,
                                  minimumSymbol: edge.isVertical ? "arrow.up" : "arrow.left",
                                  maximumSymbol: edge.isVertical ? "arrow.down" : "arrow.right")
                    .settingsOverride(overrideContext, field: .alongEdgeOffset)
                SettingsSliderRow(title: .settingsEdgeDistance, unit: .settingsPoints,
                                  value: $edgeDistance, range: 0...300, step: 1,
                                  minimumSymbol: edge == .bottom ? "arrow.down.to.line" : (edge == .left ? "arrow.left.to.line" : "arrow.right.to.line"),
                                  maximumSymbol: edge == .bottom ? "arrow.up" : (edge == .left ? "arrow.right" : "arrow.left"))
                    .settingsOverride(overrideContext, field: .edgeDistance)
            }
        }
    }
}

#if DEBUG
#Preview("Position pane") {
    @Previewable @State var edge: DockEdge = .left
    @Previewable @State var reference: DockSettings.PositionReference = .usableDesktop
    @Previewable @State var alignment: DockSettings.Alignment = .center
    @Previewable @State var offset: Double = 0
    @Previewable @State var bottom: Double = 8
    ScrollView {
        PositionSettingsPane(edge: $edge, reference: $reference, alignment: $alignment,
                             alongEdgeOffset: $offset, edgeDistance: $bottom)
            .padding(24)
    }
    .tint(SettingsCategory.position.tint)
    .frame(width: 560, height: 640)
}
#endif
