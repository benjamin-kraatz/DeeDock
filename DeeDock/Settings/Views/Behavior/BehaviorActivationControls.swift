import SwiftUI

/// Trigger dimensions remain editable when auto-hide is off, including inherited per-display values.
struct BehaviorActivationControls: View {
    let source: SettingsValueSource

    var body: some View {
        VStack(spacing: 0) {
            SettingsPickerRow(title: .behaviorLocation, options: [
                SettingsOption(value: DockBehaviorSettings.ActivationLocation.dockPosition,
                               title: .behaviorDockPosition, symbol: "dock.rectangle"),
                SettingsOption(value: .screenEdge, title: .behaviorScreenEdge, symbol: source.value.edge.edgeSymbol)
            ], selection: source.binding(\.behavior.activationLocation))
                .settingsOverride(source.context, field: .activationLocation)
            Divider().padding(.leading, SettingsMetrics.rowInset)
            SettingsPickerRow(title: .behaviorLengthMode, options: [
                SettingsOption(value: DockBehaviorSettings.LengthMode.dockLength, title: .behaviorDockLength,
                               symbol: source.value.edge.isVertical ? "arrow.up.and.down" : "arrow.left.and.right"),
                SettingsOption(value: .custom, title: .behaviorCustomLength, symbol: "ruler")
            ], selection: source.binding(\.behavior.lengthMode))
                .settingsOverride(source.context, field: .lengthMode)
            if source.value.behavior.lengthMode == .custom {
                Divider().padding(.leading, SettingsMetrics.rowInset)
                SettingsSliderRow(title: .behaviorCustomLength, unit: .settingsPoints,
                                  value: source.binding(\.behavior.customLength), range: 32...8192, step: 1,
                                  defaultValue: DockSettings.defaults.behavior.customLength)
                    .settingsOverride(source.context, field: .customLength)
            }
            Divider().padding(.leading, SettingsMetrics.rowInset)
            SettingsSliderRow(title: .behaviorZoneDepth, unit: .settingsPoints,
                              value: source.binding(\.behavior.zoneDepth), range: 1...90, step: 1,
                              defaultValue: DockSettings.defaults.behavior.zoneDepth)
                .settingsOverride(source.context, field: .zoneDepth)
            Divider().padding(.leading, SettingsMetrics.rowInset)
            SettingsSliderRow(title: .behaviorZoneOffset, unit: .settingsPoints,
                              value: source.binding(\.behavior.zoneOffset), range: -4096...4096, step: 1,
                              defaultValue: DockSettings.defaults.behavior.zoneOffset)
                .settingsOverride(source.context, field: .zoneOffset)
        }
    }
}
