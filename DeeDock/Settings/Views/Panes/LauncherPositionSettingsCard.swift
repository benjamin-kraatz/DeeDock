import SwiftUI

/// Chooses where the DOKK tile sits: either end of the dock, or directly after a pin.
///
/// Pins are display-specific, so the caller passes the list that matches the scope it edits. A saved
/// anchor missing from that list keeps a labeled menu item, so the menu never shows a blank choice.
struct LauncherPositionSettingsCard: View {
    let edge: DockEdge
    /// The pins offered as anchors, in dock order.
    let pins: [DockPin]
    /// Names for anchors that are not in `pins`, such as a pin on another display.
    var otherPinNames: [String: String] = [:]
    @Binding var position: LauncherDockPosition
    var overrideContext: SettingsOverrideContext?

    private var missingAnchor: String? {
        guard let anchor = position.anchorPinID, !pins.contains(where: { $0.id == anchor }) else { return nil }
        return anchor
    }

    var body: some View {
        SettingsCard(title: .hubTitle, footnote: .settingsLauncherPositionHelp) {
            SettingsMenuRow(title: .settingsLauncherPosition, selection: $position) {
                Text(edge.isVertical ? .settingsLauncherFarTop : .settingsLauncherFarLeft)
                    .tag(LauncherDockPosition.start)
                if !pins.isEmpty || missingAnchor != nil {
                    Divider()
                }
                ForEach(pins) { pin in
                    Text(.settingsLauncherAfterPin(pin.name)).tag(LauncherDockPosition.afterPin(pin.id))
                }
                if let missingAnchor {
                    missingAnchorLabel(missingAnchor).tag(LauncherDockPosition.afterPin(missingAnchor))
                }
                Divider()
                Text(edge.isVertical ? .settingsLauncherFarBottom : .settingsLauncherFarRight)
                    .tag(LauncherDockPosition.end)
            }
            .settingsOverride(overrideContext, field: .launcherPosition)
        }
    }

    private func missingAnchorLabel(_ id: String) -> Text {
        if let name = otherPinNames[id] { return Text(.settingsLauncherAfterPinElsewhere(name)) }
        return Text(.settingsLauncherAfterRemovedPin)
    }
}

#if DEBUG
private let previewPins: [DockPin] = [("finder", "Finder"), ("safari", "Safari"), ("mail", "Mail")].map { id, name in
    .application(ApplicationReference(bundleIdentifier: "preview.\(id)",
                                      url: URL(fileURLWithPath: "/Preview/\(id).app"), name: name))
}

#Preview("Launcher after a pin") {
    @Previewable @State var position = LauncherDockPosition.afterPin("preview.safari")
    LauncherPositionSettingsCard(edge: .bottom, pins: previewPins, position: $position)
        .padding(24)
        .frame(width: 560)
}

#Preview("Vertical dock, anchor pinned on another display") {
    @Previewable @State var position = LauncherDockPosition.afterPin("preview.notes")
    LauncherPositionSettingsCard(edge: .left, pins: previewPins, otherPinNames: ["preview.notes": "Notes"],
                                 position: $position)
        .padding(24)
        .frame(width: 560)
}

#Preview("No pins") {
    @Previewable @State var position = LauncherDockPosition.start
    LauncherPositionSettingsCard(edge: .bottom, pins: [], position: $position)
        .padding(24)
        .frame(width: 560)
}
#endif
