import SwiftUI

/// Trigger dimensions remain editable when auto-hide is off, including inherited per-display values.
struct BehaviorActivationControls: View {
    let source: SettingsValueSource
    var body: some View {
        SettingsPickerRow(title: .behaviorLocation, options: [
            SettingsOption(value: DockBehaviorSettings.ActivationLocation.dockPosition, title: .behaviorDockPosition, symbol: "dock.rectangle"),
            SettingsOption(value: .screenEdge, title: .behaviorScreenEdge, symbol: "rectangle.bottomthird.inset.filled")
        ], selection: source.binding(\.behavior.activationLocation))
            .settingsOverride(source.context, field: .activationLocation)
        SettingsPickerRow(title: .behaviorWidthMode, options: [
            SettingsOption(value: DockBehaviorSettings.WidthMode.dockWidth, title: .behaviorDockWidth, symbol: "arrow.left.and.right"),
            SettingsOption(value: .custom, title: .behaviorCustomWidth, symbol: "ruler")
        ], selection: source.binding(\.behavior.widthMode))
            .settingsOverride(source.context, field: .widthMode)
        if source.value.behavior.widthMode == .custom {
            SettingsSliderRow(title: .behaviorCustomWidth, unit: .settingsPoints, value: source.binding(\.behavior.customWidth), range: 32...8192, step: 1)
                .settingsOverride(source.context, field: .customWidth)
        }
        SettingsSliderRow(title: .behaviorZoneHeight, unit: .settingsPoints, value: source.binding(\.behavior.zoneHeight), range: 1...64, step: 1)
            .settingsOverride(source.context, field: .zoneHeight)
        SettingsSliderRow(title: .behaviorZoneOffset, unit: .settingsPoints, value: source.binding(\.behavior.zoneOffset), range: -4096...4096, step: 1)
            .settingsOverride(source.context, field: .zoneOffset)
    }
}
