import SwiftUI

/// A rounded panel with a pointer aimed back at the dock tile that opened it.
///
/// The defaults are the shared popover look. A feature can ask for larger corners and a soft pointer
/// whose sides flare into the body and whose tip is rounded, the way Liquid Glass popovers draw it.
struct DockPopoverShape: Shape {
    let chrome: DockPopoverChrome
    var cornerRadius: CGFloat = 18
    var softPointer = false

    func path(in rect: CGRect) -> Path {
        let depth = DockPopoverGeometry.pointerDepth
        var body = rect
        switch chrome.edge {
        case .bottom: body.size.height -= depth
        case .top: body.origin.y += depth; body.size.height -= depth
        case .left: body.origin.x += depth; body.size.width -= depth
        case .right: body.size.width -= depth
        }
        var path = Path(roundedRect: body, cornerRadius: cornerRadius, style: softPointer ? .continuous : .circular)
        path.addPath(softPointer ? softPointerPath(body: body, rect: rect) : pointerPath(body: body, rect: rect))
        return path
    }

    /// Maps a point given as (offset along the attached side, distance outward from the body) into
    /// the shape's coordinates, so one pointer outline serves all four dock edges.
    ///
    /// The pointer must wind the same way as the rounded body, or the strip where they overlap
    /// cancels out under the nonzero fill rule and shows as a hairline seam. Bottom and left map
    /// with a rotation, top and right with a reflection, so the former trace `along` reversed.
    private func point(along: CGFloat, outward: CGFloat, body: CGRect) -> CGPoint {
        let along = chrome.edge == .bottom || chrome.edge == .left ? -along : along
        return switch chrome.edge {
        case .bottom: CGPoint(x: chrome.attachment + along, y: body.maxY + outward)
        case .top: CGPoint(x: chrome.attachment + along, y: body.minY - outward)
        case .left: CGPoint(x: body.minX - outward, y: chrome.attachment + along)
        case .right: CGPoint(x: body.maxX + outward, y: chrome.attachment + along)
        }
    }

    private func pointerPath(body: CGRect, rect: CGRect) -> Path {
        let depth = DockPopoverGeometry.pointerDepth
        let halfWidth: CGFloat = 10
        var pointer = Path()
        // Starts one point inside the body so the pointer and body fill as one shape.
        pointer.move(to: point(along: -halfWidth, outward: -1, body: body))
        pointer.addLine(to: point(along: 0, outward: depth, body: body))
        pointer.addLine(to: point(along: halfWidth, outward: -1, body: body))
        pointer.closeSubpath()
        return pointer
    }

    private func softPointerPath(body: CGRect, rect: CGRect) -> Path {
        let depth = DockPopoverGeometry.pointerDepth
        let halfWidth: CGFloat = 16
        var pointer = Path()
        pointer.move(to: point(along: -halfWidth, outward: -1, body: body))
        pointer.addCurve(to: point(along: -2.2, outward: depth - 0.8, body: body),
                         control1: point(along: -halfWidth * 0.5, outward: 0, body: body),
                         control2: point(along: -halfWidth * 0.32, outward: depth * 0.72, body: body))
        pointer.addQuadCurve(to: point(along: 2.2, outward: depth - 0.8, body: body),
                             control: point(along: 0, outward: depth + 0.4, body: body))
        pointer.addCurve(to: point(along: halfWidth, outward: -1, body: body),
                         control1: point(along: halfWidth * 0.32, outward: depth * 0.72, body: body),
                         control2: point(along: halfWidth * 0.5, outward: 0, body: body))
        pointer.closeSubpath()
        return pointer
    }
}

extension View {
    /// Applies the pointer inset, material, and clipping every dock popover shares.
    func dockPopoverChrome(_ chrome: DockPopoverChrome, opaque: Bool) -> some View {
        let shape = DockPopoverShape(chrome: chrome)
        return self
            .padding(.top, chrome.edge == .top ? DockPopoverGeometry.pointerDepth : 0)
            .padding(.bottom, chrome.edge == .bottom ? DockPopoverGeometry.pointerDepth : 0)
            .padding(.leading, chrome.edge == .left ? DockPopoverGeometry.pointerDepth : 0)
            .padding(.trailing, chrome.edge == .right ? DockPopoverGeometry.pointerDepth : 0)
            // Top alignment: a popover whose content is shorter than the panel must not float
            // in the middle of it. Content that fills the panel is unaffected.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                if opaque {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .clipShape(shape)
    }
}
