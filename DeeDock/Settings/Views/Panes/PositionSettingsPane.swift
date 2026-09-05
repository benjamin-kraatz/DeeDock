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

    // Reading the effective value never writes to the inherited or overridden preference.
    private var referenceSelection: Binding<DockSettings.PositionReference> {
        Binding(get: { reference.resolved(for: edge) }, set: { value in
            guard edge != .top else { return }
            reference = value
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            SettingsCard(title: .settingsPreview, footnote: .settingsPreviewDisclaimer) {
                SettingsStackedRow {
                    DockPlacementPreview(edge: edge, reference: reference, alignment: alignment,
                                         alongEdgeOffset: alongEdgeOffset, edgeDistance: edgeDistance)
                }
            }
            SettingsCard(title: .settingsCardAnchor, footnote: edge == .top ? nil : .settingsDockOverlapHelp) {
                SettingsPickerRow(title: .settingsEdge, options: DockEdge.settingsOptions, selection: $edge)
                    .settingsOverride(overrideContext, field: .edge)
                VStack(alignment: .leading, spacing: 0) {
                    SettingsPickerRow(title: .settingsPositionReference,
                                      options: DockSettings.PositionReference.settingsOptions,
                                      selection: referenceSelection)
                        .settingsOverride(edge == .top ? nil : overrideContext, field: .positionReference)
                        .disabled(edge == .top)
                    if edge == .top {
                        Text(.settingsTopReferenceHelp)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, SettingsMetrics.rowInset).padding(.bottom, 10)
                    }
                }
                SettingsPickerRow(title: .settingsAlignment,
                                  options: DockSettings.Alignment.settingsOptions(edge: edge),
                                  selection: $alignment)
                    .settingsOverride(overrideContext, field: .alignment)
            }
            SettingsCard(title: .settingsCardFineTuning, footnote: .settingsPositionHelp) {
                SettingsSliderRow(title: .settingsAlongEdgeOffset, unit: .settingsPoints,
                                  value: $alongEdgeOffset, range: -1000...1000, step: 1,
                                  minimumSymbol: edge.isVertical ? "arrow.up" : "arrow.left",
                                  maximumSymbol: edge.isVertical ? "arrow.down" : "arrow.right",
                                  defaultValue: DockSettings.defaults.alongEdgeOffset)
                    .settingsOverride(overrideContext, field: .alongEdgeOffset)
                SettingsSliderRow(title: .settingsEdgeDistance, unit: .settingsPoints,
                                  value: $edgeDistance, range: 0...300, step: 1,
                                  minimumSymbol: edge.outwardSymbol,
                                  maximumSymbol: edge.inwardSymbol,
                                  defaultValue: DockSettings.defaults.edgeDistance)
                    .settingsOverride(overrideContext, field: .edgeDistance)
            }
        }
    }
}

#if DEBUG
#Preview("Top placement preserves a saved screen-edge request") {
    @Previewable @State var edge: DockEdge = .top
    @Previewable @State var reference: DockSettings.PositionReference = .screenEdge
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
