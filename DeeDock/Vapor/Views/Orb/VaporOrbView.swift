import SwiftUI

/// The orb: a glass sphere lit from its display's lamp, with the folders tumbling inside, a
/// count badge and a drop glow. Fills its window: the orb plus ``VaporGeometry/orbCanvasInset``
/// on each side, which leaves room for the lean, the squash, the badge and escaping steam.
///
/// Purely visual: the window's AppKit view handles clicks, dragging and drops, and the
/// accessibility element is declared here. Reactions come from the controller's event tokens
/// (``VaporController/addition``, ``VaporController/refusal``, ``VaporController/deletion``)
/// and presentation inputs (``VaporController/dropHover``, ``VaporController/orbMotion``,
/// ``VaporController/lighting``).
struct VaporOrbView: View {
    let controller: VaporController

    @State private var pile: VaporPileEngine
    @State private var openPulse = 0
    @Environment(\.colorScheme) private var colorScheme

    /// - Parameter pile: An engine to draw from instead of a fresh one; previews and snapshots
    ///   pass one that is already in sync with their folders.
    init(controller: VaporController, pile: VaporPileEngine? = nil) {
        self.controller = controller
        _pile = State(initialValue: pile ?? VaporPileEngine())
    }

    var body: some View {
        let diameter = VaporGeometry.orbDiameter
        let palette = VaporOrbPalette(colorScheme: colorScheme, reduceTransparency: controller.reduceTransparency)
        let reduceMotion = controller.reduceMotion
        let proximity = controller.dropHover.proximity
        let isDragging = controller.orbMotion.isDragging
        let totals = controller.totals
        ZStack {
            VaporOrbShadow(lighting: controller.lighting, palette: palette, isLifted: isDragging && !reduceMotion)
            ZStack {
                VaporOrbGlass(palette: palette)
                    .frame(width: diameter, height: diameter)
                VaporOrbPileCanvas(engine: pile, palette: palette)
                VaporOrbEmptyGlyph()
                    .opacity(totals.count == 0 ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: totals.count == 0)
                Group {
                    VaporOrbRim(palette: palette, proximity: proximity.value, isOver: proximity.isOverOrb)
                    VaporOrbLitLayers(lighting: controller.lighting, palette: palette)
                    VaporOrbEvaporateFlash(deletion: controller.deletion, reduceMotion: reduceMotion)
                    VaporOrbRefusalFlash(token: controller.refusal?.token)
                }
                .frame(width: diameter, height: diameter)
            }
            .vaporSquash(additionToken: controller.addition?.token, openPulse: openPulse, reduceMotion: reduceMotion)
            .vaporShake(token: controller.refusal?.token, reduceMotion: reduceMotion)
            VaporOrbBadge(count: totals.count, corner: controller.badgeCorner, palette: palette, reduceMotion: reduceMotion)
        }
        // A nearing drag pulls the whole orb toward the pointer and swells it; a drag lifts it.
        .scaleEffect(reduceMotion ? 1 : (isDragging ? 1.04 : 1 + proximity.value * 0.12))
        .offset(reduceMotion ? .zero : proximity.lean)
        .animation(.spring(response: 0.22, dampingFraction: 0.62), value: proximity)
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .frame(width: VaporGeometry.orbWindowSize.width, height: VaporGeometry.orbWindowSize.height)
        .onChange(of: VaporPileInputs(controller), initial: true) {
            pile.sync(folders: controller.folders, addition: controller.addition, deletion: controller.deletion,
                      isStaging: controller.isStaging, reduceMotion: controller.reduceMotion)
        }
        .onChange(of: controller.orbMotion) { _, motion in
            pile.setMotion(motion, reduceMotion: controller.reduceMotion)
        }
        .onChange(of: controller.isPanelOpen) { _, isOpen in
            if isOpen { openPulse &+= 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.vaporTitle))
        .accessibilityValue(Text(verbatim: VaporCopy.accessibilityValue(totals)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { controller.togglePanel() }
        .accessibilityAction(named: Text(.vaporMenuOpen)) { controller.openPanel() }
        .accessibilityAction(named: Text(.vaporActionDeleteAll)) { controller.deleteAll() }
    }
}

/// What the pile follows: the folders (with their sizes) and the events that move them.
private struct VaporPileInputs: Equatable {
    let folders: [VaporFolder]
    let addition: UUID?
    let deletion: UUID?
    let isStaging: Bool

    init(_ controller: VaporController) {
        folders = controller.folders
        addition = controller.addition?.token
        deletion = controller.deletion?.token
        isStaging = controller.isStaging
    }
}

/// The sphere's body: the see-through glass, then the tint. Under Reduce Transparency the tint
/// is opaque and there is no glass.
private struct VaporOrbGlass: View {
    let palette: VaporOrbPalette

    var body: some View {
        ZStack {
            if !palette.reduceTransparency {
                Circle()
                    .fill(.clear)
                    .glassEffect(.clear, in: Circle())
            }
            Circle().fill(palette.baseGradient)
        }
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Empty") {
    VaporOrbView(controller: VaporPreviewData.controller())
        .background(VaporPreviewBackdrop())
}

#Preview("Settled pile, dark") {
    let controller = VaporPreviewData.controller(VaporPreviewData.pile)
    VaporOrbView(controller: controller, pile: VaporPreviewData.settledPile(for: controller))
        .background(VaporPreviewBackdrop())
        .preferredColorScheme(.dark)
}

#Preview("Settled pile, light, lamp upper right") {
    let controller = VaporPreviewData.controller(VaporPreviewData.pile, lamp: .upperRight)
    VaporOrbView(controller: controller, pile: VaporPreviewData.settledPile(for: controller))
        .background(VaporPreviewBackdrop())
        .preferredColorScheme(.light)
}

#Preview("Drag nearby") {
    let controller = VaporPreviewData.controller(Array(VaporPreviewData.pile.prefix(3)))
    controller.dropHover = VaporPreviewData.nearbyDrag
    return VaporOrbView(controller: controller, pile: VaporPreviewData.settledPile(for: controller))
        .background(VaporPreviewBackdrop())
}

#Preview("Drag over the orb") {
    let controller = VaporPreviewData.controller(Array(VaporPreviewData.pile.prefix(3)))
    controller.dropHover = VaporPreviewData.overOrbDrag
    return VaporOrbView(controller: controller, pile: VaporPreviewData.settledPile(for: controller))
        .background(VaporPreviewBackdrop())
}

#Preview("Refused, badge top right") {
    VaporOrbView(controller: VaporPreviewData.controller(VaporPreviewData.mixed, refusal: .notAFolder, opensLeft: true))
        .background(VaporPreviewBackdrop())
}

#Preview("Reduce Transparency") {
    VaporOrbView(controller: VaporPreviewData.controller(VaporPreviewData.calculating, reduceTransparency: true))
        .background(VaporPreviewBackdrop())
}
#endif
