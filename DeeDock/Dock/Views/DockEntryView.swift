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
        case .window(let item):
            DockWindowButton(item: item, size: size, selected: selected, interaction: interaction,
                accessibilityFocus: { accessibilityFocus(DockEntryID.window(item.window.id).hitID, $0) })
        case .windowGroup(let group):
            DockWindowGroupButton(group: group, size: size, selected: selected, interaction: interaction,
                accessibilityFocus: { accessibilityFocus(DockEntryID.windowGroup(group.app.id).hitID, $0) })
        case .focus(let item):
            DockFocusButton(item: item, size: size, selected: selected, interaction: interaction,
                accessibilityFocus: { accessibilityFocus(DockEntryID.focus.hitID, $0) })
        case .action(let item):
            DockActionButton(item: item, size: size, selected: selected, interaction: interaction,
                accessibilityFocus: { accessibilityFocus(DockEntryID.action(item.tile.id).hitID, $0) })
        case .app(let item):
            DockAppButton(item: item, size: size, isLaunching: launching, isKeyboardSelected: selected,
                primaryAction: { primaryAppAction(item) }, open: { openApp(item) },
                togglePin: { togglePin(item) }, interaction: interaction,
                menuTracking: menuTracking, accessibilityFocus: { accessibilityFocus(DockEntryID.app(item.id).hitID, $0) })
                .opacity(interaction.dragSourceID == item.id ? 0.3 : 1)
        case .folder(let item):
            DockFolderButton(item: item, size: size, selected: selected, interaction: interaction,
                menuTracking: menuTracking,
                accessibilityFocus: { accessibilityFocus(DockEntryID.folder(item.reference.id).hitID, $0) })
                .opacity(interaction.dragSourceID == item.id ? 0.3 : 1)
        case .group(let control):
            DockGroupButton(control: control, size: size, selected: selected, interaction: interaction,
                            reduceTransparency: reduceTransparency)
        case .sessionCapsule(let item):
            DockSessionCapsuleButton(item: item, size: size, selected: selected, interaction: interaction,
                menuTracking: menuTracking,
                accessibilityFocus: { accessibilityFocus(DockEntryID.sessionCapsule(item.capsuleID).hitID, $0) })
        case .sessionCapsules(let item):
            DockCapsulesButton(item: item, size: size, selected: selected, interaction: interaction,
                accessibilityFocus: { accessibilityFocus(DockEntryID.sessionCapsules.hitID, $0) })
        case .shelf(let item):
            DockShelfButton(item: item, size: size, selected: selected, interaction: interaction,
                menuTracking: menuTracking,
                accessibilityFocus: { accessibilityFocus(DockEntryID.shelf.hitID, $0) })
        case .trash(let item):
            DockTrashButton(item: item, size: size, selected: selected, interaction: interaction,
                menuTracking: menuTracking,
                accessibilityFocus: { accessibilityFocus(DockEntryID.trash.hitID, $0) })
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
