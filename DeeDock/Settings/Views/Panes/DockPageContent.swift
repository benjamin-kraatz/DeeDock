import SwiftUI

/// The cards behind every dock page, for the shared defaults or for one display.
///
/// `override` is what makes the same page serve both scopes: with it, each control writes only its
/// own field into that display's profile and shows whether the value is still inherited.
struct DockPageContent: View {
    let page: SettingsPage
    let context: SettingsContext
    var override: SettingsOverrideContext?
    /// Offered only where a live dock exists to flash the zone on.
    var showZone: (() -> Void)?

    private var source: SettingsValueSource { context.source(override) }
    private func binding<Value>(_ keyPath: WritableKeyPath<DockSettings, Value>) -> Binding<Value> {
        source.binding(keyPath)
    }

    var body: some View {
        Group {
            switch page {
            case .appearance:
                AppearanceSettingsPane(edge: source.value.edge,
                                       iconSize: binding(\.iconSize),
                                       magnification: binding(\.magnification),
                                       itemSpacing: binding(\.itemSpacing),
                                       cornerRadius: binding(\.cornerRadius),
                                       runningIndicatorStyle: binding(\.runningIndicatorStyle),
                                       animateIndicators: binding(\.animateIndicators),
                                       appearanceSettings: source.value,
                                       overrideContext: override)
            case .appNames:
                DockTooltipSettingsPane(source: source)
            case .background:
                DockFadingSettingsPane(source: source)
            case .position:
                PositionSettingsPane(edge: binding(\.edge), reference: binding(\.positionReference),
                                     alignment: binding(\.alignment),
                                     alongEdgeOffset: binding(\.alongEdgeOffset),
                                     edgeDistance: binding(\.edgeDistance), overrideContext: override)
                SettingsCard(title: .launcherTitle, footnote: .settingsLauncherPositionHelp) {
                    Picker(selection: binding(\.launcherAtStart)) {
                        Text(source.value.edge.isVertical ? .settingsLauncherTop : .settingsLauncherLeft).tag(true)
                        Text(source.value.edge.isVertical ? .settingsLauncherBottom : .settingsLauncherRight).tag(false)
                    } label: { Text(.settingsLauncherPosition) }
                    .pickerStyle(.segmented)
                    .settingsOverride(override, field: .launcherAtStart)
                }
            case .behavior:
                BehaviorSettingsPane(source: source, showZone: showZone)
            case .shownApps:
                AppVisibilitySettingsPane(source: source)
            default:
                EmptyView()
            }
        }
        .disabled(context.isLocked(override))
    }
}
