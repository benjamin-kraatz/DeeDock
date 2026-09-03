import SwiftUI

/// Renders one projected slot. Group controls and gaps never acquire application actions.
struct DockEntryView: View {
    let slot: DockRenderSlot
    let size: CGFloat
    let launching: Bool
    let selected: Bool
    let interaction: DockInteraction
    let reduceTransparency: Bool
    let primaryAppAction: (DockItem) -> Void
    let openApp: (DockItem) -> Void
    let togglePin: (DockItem) -> Void
    let menuTracking: (Bool) -> Void
    let accessibilityFocus: (String, Bool) -> Void

    var body: some View {
        switch slot {
        case .app(let item):
            DockAppButton(item: item, size: size, isLaunching: launching, isKeyboardSelected: selected,
                primaryAction: { primaryAppAction(item) }, open: { openApp(item) },
                togglePin: { togglePin(item) }, interaction: interaction,
                menuTracking: menuTracking, accessibilityFocus: { accessibilityFocus(DockEntryID.app(item.id).hitID, $0) })
                .opacity(interaction.dragSourceID == item.id ? 0.3 : 1)
        case .group(let control):
            DockGroupButton(control: control, size: size, selected: selected, interaction: interaction,
                            reduceTransparency: reduceTransparency)
        case .gap:
            RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.tint, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .frame(width: size, height: size).accessibilityHidden(true).allowsHitTesting(false)
        }
    }
}

/// Both spaces come from the same rendered frame, including transient magnification and insertion motion.
nonisolated struct DockEntryFrames: Equatable, Sendable {
    let root: CGRect
    let canvas: CGRect
}
