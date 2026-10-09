import SwiftUI

/// The Hub's outline: a continuous rounded body with the mockup's soft pointer on the side that
/// faces the dock.
///
/// The shape's rectangle includes the pointer strip (`pointerDepth` deep on `edge`); the body is
/// the rest. Depth, offset, and radius animate, so the pointer can shrink into the body while the
/// Hub detaches into a window.
struct HubGlassShape: Shape {
    var edge: DockEdge
    /// Pointer center along the side facing the dock, in the body's top-left space.
    var pointerOffset: CGFloat
    var pointerDepth: CGFloat
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(pointerOffset, pointerDepth), cornerRadius) }
        set {
            pointerOffset = newValue.first.first
            pointerDepth = newValue.first.second
            cornerRadius = newValue.second
        }
    }

    init(layout: HubBodyLayout) {
        edge = layout.edge
        pointerOffset = layout.pointerOffset
        pointerDepth = layout.pointerDepth
        cornerRadius = layout.cornerRadius
    }

    func path(in rect: CGRect) -> Path {
        let body = Self.body(in: rect, edge: edge, depth: pointerDepth)
        let radius = min(cornerRadius, body.width / 2, body.height / 2)
        let rounded = Path(roundedRect: body, cornerRadius: max(0, radius), style: .continuous)
        guard pointerDepth > 0.25 else { return rounded }
        // A union rather than two subpaths, so the overlap never cancels under the fill rule.
        return rounded.union(pointer(body: body))
    }

    /// The body rectangle inside a glass rectangle whose `edge` side carries a `depth` pointer strip.
    static func body(in rect: CGRect, edge: DockEdge, depth: CGFloat) -> CGRect {
        var body = rect
        switch edge {
        case .bottom: body.size.height -= depth
        case .top: body.origin.y += depth; body.size.height -= depth
        case .left: body.origin.x += depth; body.size.width -= depth
        case .right: body.size.width -= depth
        }
        return body
    }

    /// The mockup's pointer, `M0 0 H24 L14.3 9.4 Q12 11.4 9.7 9.4 Z`, centered on the offset and
    /// scaled to the current depth. It starts one point inside the body so the two fill as one.
    private func pointer(body: CGRect) -> Path {
        let half = HubStyle.pointerSize.width / 2
        let scale = pointerDepth / HubStyle.pointerSize.height
        func point(_ along: CGFloat, _ outward: CGFloat) -> CGPoint {
            let out = outward * scale
            return switch edge {
            case .bottom: CGPoint(x: body.minX + pointerOffset + along, y: body.maxY + out)
            case .top: CGPoint(x: body.minX + pointerOffset + along, y: body.minY - out)
            case .left: CGPoint(x: body.minX - out, y: body.minY + pointerOffset + along)
            case .right: CGPoint(x: body.maxX + out, y: body.minY + pointerOffset + along)
            }
        }
        var path = Path()
        path.move(to: point(-half, -1))
        path.addLine(to: point(half, -1))
        path.addLine(to: point(2.3, 9.4))
        path.addQuadCurve(to: point(-2.3, 9.4), control: point(0, 11.4))
        path.closeSubpath()
        return path
    }
}
