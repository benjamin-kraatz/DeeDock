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

    /// This display's pins, or the main display's for the shared defaults, which new displays copy.
    private var launcherAnchorPins: [DockPin] {
        let profiles = context.profiles
        let id = override?.id ?? profiles.displays.first(where: \.isPrimary)?.id
        return id.flatMap { profiles.pinLists[$0] } ?? []
    }

    private var allPinNames: [String: String] {
        Dictionary(context.profiles.pinLists.values.joined().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// The main display's edge, which decides the macOS Dock's side; it does not depend on the
    /// display being edited, because the macOS Dock has one position for the whole Mac.
    private var mainDisplayEdge: DockEdge {
        let profiles = context.profiles
        guard let id = profiles.displays.first(where: \.isPrimary)?.id else { return context.store.value.edge }
        return profiles.effectiveSettings(for: id).edge
    }

    var body: some View {
        // Outside the locked group: restoring the macOS Dock must work even when dock
        // settings are unreadable.
        if page == .behavior, let tuck = context.coordinator?.systemDockTuck {
            SystemDockTuckSettingsCard(controller: tuck, dokkEdge: mainDisplayEdge)
        }
        Group {
            switch page {
            case .appearance:
                AppearanceSettingsPane(edge: source.value.edge,
                                       iconSize: binding(\.iconSize),
                                       magnification: binding(\.magnification),
                                       itemSpacing: binding(\.itemSpacing),
                                       cornerRadius: binding(\.cornerRadius),
                                       runningIndicatorStyle: binding(\.runningIndicatorStyle),
                                       iconStyle: binding(\.iconStyle),
                                       launcherLineIcons: binding(\.launcherLineIcons),
                                       launcherStyle: binding(\.launcherStyle),
                                       animateIndicators: binding(\.animateIndicators),
                                       launchAnimation: binding(\.launchAnimation),
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
                LauncherPositionSettingsCard(edge: source.value.edge, pins: launcherAnchorPins,
                                             otherPinNames: allPinNames,
                                             position: binding(\.launcherPosition), overrideContext: override)
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
