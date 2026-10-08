import SwiftUI

/// A monochrome outline of the resting dock that materializes inside the approach glow.
///
/// It follows the glow's surge, so it stays invisible until the last few dozen points before the
/// zone, then strengthens with each step closer. The ghost is lit from the point on the edge under
/// the pointer: a soft radial mask starts near that point and widens until it covers the whole dock
/// at the zone. It also rises a few points into its resting place. Reduce Motion drops the rise and
/// the widening and changes only opacity; Reduce Transparency draws crisp outlines without imprints.
///
/// The ghost is white over a light glow or the accent glow and graphite over a shadow, regardless of
/// the dock's icon style. `amount` and `focus` animate with the glow's surge and focus.
struct DockApproachGhostLayer: View, Animatable {
    /// The glow's surge in 0...1.
    var amount: Double
    /// Canonical position along the edge (see ``DockApproachGeometry/zoneSpan``).
    var focus: CGFloat
    /// The ghost in this view's top-left coordinates.
    let ghost: DockApproachGhost
    let edge: DockEdge
    /// True over a shadow tone, where a white ghost would vanish on the light wallpaper.
    let graphite: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool

    /// How far the ghost rises into place as it appears.
    static let lift: CGFloat = 10

    var animatableData: AnimatablePair<Double, CGFloat> {
        get { AnimatablePair(amount, focus) }
        set { amount = newValue.first; focus = newValue.second }
    }

    private var tint: Color { graphite ? Color(white: 0.12) : .white }

    var body: some View {
        Canvas { context, size in
            // A gentle power curve keeps the ghost readable a little earlier than the raw surge.
            let visibility = pow(min(1, max(0, amount)), 0.85)
            guard visibility > 0.004, !ghost.tiles.isEmpty || ghost.glass != nil else { return }
            var layer = context
            layer.opacity = visibility * (graphite ? 0.6 : 0.75)
            // Additive white brightens the glow beneath like light; graphite composites normally.
            if !graphite { layer.blendMode = .plusLighter }
            if !reduceMotion && !reduceTransparency { clipToLight(&layer, size: size) }
            layer.drawLayer { ghostLayer in
                if !reduceMotion {
                    // Rises from the screen edge into the resting position. Canonical +y is outward.
                    let rise = edge.offset(CGSize(width: 0, height: Self.lift * (1 - visibility)))
                    ghostLayer.translateBy(x: rise.width, y: rise.height)
                }
                if reduceTransparency { drawOutlines(in: &ghostLayer) } else { drawImprints(in: &ghostLayer) }
            }
        }
        .allowsHitTesting(false)
    }

    /// The point on the screen edge under the pointer, in view coordinates.
    private func lightSource(in size: CGSize) -> CGPoint {
        switch edge {
        case .bottom: CGPoint(x: focus, y: size.height)
        case .top: CGPoint(x: focus, y: 0)
        case .left: CGPoint(x: 0, y: focus)
        case .right: CGPoint(x: size.width, y: focus)
        }
    }

    /// Masks the ghost with a radial falloff around the light source. The radius grows with the
    /// surge from about a third of the way to the farthest ghost corner to past it, so the dock
    /// reveals itself outward from the pointer and is fully lit, though still tapered, at the zone.
    private func clipToLight(_ context: inout GraphicsContext, size: CGSize) {
        let light = lightSource(in: size)
        let bounds = ghost.bounds
        let farthest = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                        CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)]
            .map { hypot($0.x - light.x, $0.y - light.y) }.max() ?? 0
        let radius = max(40, farthest * (0.35 + 0.95 * min(1, max(0, amount))))
        let gradient = Gradient(stops: [
            .init(color: .black, location: 0), .init(color: .black.opacity(0.85), location: 0.55), .init(color: .clear, location: 1)
        ])
        context.clipToLayer { mask in
            mask.fill(Path(ellipseIn: CGRect(x: light.x - radius, y: light.y - radius, width: radius * 2, height: radius * 2)),
                      with: .radialGradient(gradient, center: light, startRadius: 0, endRadius: radius))
        }
    }

    /// Frosted glass, then each icon as a grayscale imprint washed toward the tint. The wash is
    /// clipped to the icon's own alpha, so transparent corners and non-square artwork stay clear.
    private func drawImprints(in context: inout GraphicsContext) {
        if let glass = ghost.glass {
            let shape = Path(roundedRect: glass, cornerRadius: ghost.cornerRadius, style: .continuous)
            context.fill(shape, with: .color(tint.opacity(0.1)))
            context.stroke(shape, with: .color(tint.opacity(0.55)), lineWidth: 1.2)
        }
        for tile in ghost.tiles {
            guard let icon = tile.icon else { drawSlot(tile.frame, in: &context, fill: 0.32); continue }
            let image = context.resolve(Image(nsImage: icon))
            var mono = context
            mono.addFilter(.grayscale(1))
            mono.opacity = 0.7
            mono.draw(image, in: tile.frame)
            var wash = context
            wash.clipToLayer { $0.draw(image, in: tile.frame) }
            wash.fill(Path(tile.frame), with: .color(tint.opacity(graphite ? 0.45 : 0.4)))
        }
    }

    /// Reduce Transparency: opaque hairlines for the glass and every slot, without translucent fills.
    private func drawOutlines(in context: inout GraphicsContext) {
        if let glass = ghost.glass {
            context.stroke(Path(roundedRect: glass, cornerRadius: ghost.cornerRadius, style: .continuous),
                           with: .color(tint), lineWidth: 1.5)
        }
        for tile in ghost.tiles { drawSlot(tile.frame, in: &context, fill: 0) }
    }

    /// A blank rounded slot for tiles without artwork, or every tile under Reduce Transparency.
    private func drawSlot(_ frame: CGRect, in context: inout GraphicsContext, fill: Double) {
        let shape = Path(roundedRect: frame, cornerRadius: frame.width * 0.225, style: .continuous)
        if fill > 0 { context.fill(shape, with: .color(tint.opacity(fill))) }
        context.stroke(shape, with: .color(tint.opacity(reduceTransparency ? 1 : 0.6)), lineWidth: 1)
    }
}

#if DEBUG
private struct DockApproachGhostPreview: View {
    let edge: DockEdge
    let amount: Double
    var graphite = false
    var reduceMotion = false
    var reduceTransparency = false

    var body: some View {
        let glass = edge.rect(CGRect(x: 120, y: 34, width: 400, height: 76), depth: 130)
        let tiles = (0..<6).map { index in
            DockApproachGhost.Tile(frame: edge.rect(CGRect(x: 132 + CGFloat(index) * 64, y: 44, width: 56, height: 56), depth: 130),
                                   icon: index.isMultiple(of: 2) ? NSImage(named: NSImage.folderName) : nil)
        }
        let size = edge.size(length: 640, depth: 130)
        DockApproachGhostLayer(amount: amount, focus: 320, ghost: DockApproachGhost(glass: glass, cornerRadius: 22, tiles: tiles),
                               edge: edge, graphite: graphite, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
            .frame(width: size.width, height: size.height)
            .background(graphite ? Color(white: 0.9) : .indigo)
    }
}

#Preview("Ghost dock — materializing toward the zone") {
    VStack(spacing: 12) {
        ForEach([0.15, 0.4, 1.0], id: \.self) { DockApproachGhostPreview(edge: .bottom, amount: $0) }
    }.padding()
}
#Preview("Ghost dock — graphite on a light wallpaper") {
    DockApproachGhostPreview(edge: .bottom, amount: 0.8, graphite: true).padding()
}
#Preview("Ghost dock — reduced motion and transparency stubs") {
    VStack(spacing: 12) {
        DockApproachGhostPreview(edge: .bottom, amount: 0.5, reduceMotion: true)
        DockApproachGhostPreview(edge: .top, amount: 0.8, reduceTransparency: true)
    }.padding()
}
#endif
