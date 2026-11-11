import SwiftUI

/// The orb: a glass sphere lit from its display's lamp, with the folders inside, a count badge
/// and a drop glow. Fills its window (the orb plus ``VaporGeometry/orbCanvasInset`` on each side).
///
/// Purely visual: the window's AppKit view handles clicks, dragging and drops, and the
/// accessibility element is declared here. Phase 2 replaces the pile with physics and adds
/// slosh, squash, shake and evaporate, reading ``VaporController/orbMotion``,
/// ``VaporController/addition``, ``VaporController/refusal`` and ``VaporController/deletion``.
struct VaporOrbView: View {
    let controller: VaporController

    private var diameter: CGFloat { VaporGeometry.orbDiameter }

    var body: some View {
        let totals = controller.totals
        let proximity = controller.reduceMotion ? VaporDropProximity.none : controller.dropHover.proximity
        ZStack {
            VaporOrbShadow(lighting: controller.lighting, diameter: diameter)
            VaporOrbSphere(lighting: controller.lighting, reduceTransparency: controller.reduceTransparency,
                           glow: controller.dropHover.proximity.value, refused: controller.refusal != nil)
                .frame(width: diameter, height: diameter)
            Group {
                if controller.folders.isEmpty {
                    VaporOrbEmptyGlyph()
                } else {
                    VaporOrbPile(folders: controller.folders, diameter: diameter)
                }
            }
            .frame(width: diameter, height: diameter)
            // The lean moves the contents; the clip stays on the sphere.
            .offset(proximity.lean)
            .clipShape(Circle())
            if totals.count > 0 {
                VaporOrbBadge(count: totals.count)
                    .offset(VaporOrbBadge.offset(corner: controller.badgeCorner, diameter: diameter))
            }
        }
        .frame(width: VaporGeometry.orbWindowSize.width, height: VaporGeometry.orbWindowSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.vaporTitle))
        .accessibilityValue(Text(verbatim: VaporCopy.accessibilityValue(totals)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { controller.togglePanel() }
        .accessibilityAction(named: Text(.vaporMenuOpen)) { controller.openPanel() }
        .accessibilityAction(named: Text(.vaporActionDeleteAll)) { controller.deleteAll() }
    }
}

/// The glass ball with a highlight turned toward the lamp and a glow that rises as a drag nears.
private struct VaporOrbSphere: View {
    let lighting: VaporLighting
    let reduceTransparency: Bool
    let glow: Double
    let refused: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.clear)
                .vaporGlass(in: Circle(), reduceTransparency: reduceTransparency)
            // The highlight is drawn at the top and rotated to face the lamp.
            Ellipse()
                .fill(.white.opacity(0.45 * lighting.intensity))
                .frame(width: 44, height: 18)
                .blur(radius: 5)
                .offset(y: -34)
                .rotationEffect(.radians(lighting.angle))
            Circle()
                .strokeBorder(Color.accentColor.opacity(0.7 * glow), lineWidth: 3)
            if refused {
                Circle().strokeBorder(Color.red.opacity(0.8), lineWidth: 3)
            }
        }
    }
}

/// The soft contact shadow under the orb, sliding away from the lamp.
private struct VaporOrbShadow: View {
    let lighting: VaporLighting
    let diameter: CGFloat

    var body: some View {
        Ellipse()
            .fill(.black.opacity(0.22))
            .frame(width: diameter * 0.7 * lighting.shadowStretch, height: 12)
            .blur(radius: 6)
            .offset(x: lighting.shadowOffset.width, y: diameter / 2 + 2)
            .accessibilityHidden(true)
    }
}

/// The faint "drop here" glyph of an empty orb.
private struct VaporOrbEmptyGlyph: View {
    var body: some View {
        Image(systemName: "arrow.down.to.line")
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(.secondary.opacity(0.6))
            .accessibilityHidden(true)
    }
}

/// The count badge on the orb's outer top corner.
private struct VaporOrbBadge: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(Color.accentColor, in: .capsule)
            .accessibilityHidden(true)
    }

    static func offset(corner: VaporBadgeCorner, diameter: CGFloat) -> CGSize {
        let reach = diameter * 0.36
        return CGSize(width: corner == .topTrailing ? reach : -reach, height: -reach)
    }
}

#if DEBUG
#Preview("Empty") {
    VaporOrbView(controller: VaporPreviewData.controller())
        .padding()
}

#Preview("Mixed") {
    VaporOrbView(controller: VaporPreviewData.controller(VaporPreviewData.mixed))
        .padding()
}

#Preview("Refused, opens left") {
    VaporOrbView(controller: VaporPreviewData.controller(VaporPreviewData.mixed, refusal: .notAFolder, opensLeft: true))
        .padding()
}

#Preview("Reduce Transparency") {
    VaporOrbView(controller: VaporPreviewData.controller(VaporPreviewData.calculating, reduceTransparency: true))
        .padding()
}
#endif
