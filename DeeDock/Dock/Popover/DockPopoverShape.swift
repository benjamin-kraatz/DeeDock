import SwiftUI

/// A rounded panel with a pointer aimed back at the dock tile that opened it.
struct DockPopoverShape: Shape {
    let chrome: DockPopoverChrome

    func path(in rect: CGRect) -> Path {
        let depth = DockPopoverGeometry.pointerDepth
        let halfWidth: CGFloat = 10
        var body = rect
        switch chrome.edge {
        case .bottom: body.size.height -= depth
        case .top: body.origin.y += depth; body.size.height -= depth
        case .left: body.origin.x += depth; body.size.width -= depth
        case .right: body.size.width -= depth
        }
        var path = Path(roundedRect: body, cornerRadius: 18)
        var pointer = Path()
        switch chrome.edge {
        case .bottom:
            pointer.move(to: CGPoint(x: chrome.attachment - halfWidth, y: body.maxY - 1))
            pointer.addLine(to: CGPoint(x: chrome.attachment, y: rect.maxY))
            pointer.addLine(to: CGPoint(x: chrome.attachment + halfWidth, y: body.maxY - 1))
        case .top:
            pointer.move(to: CGPoint(x: chrome.attachment - halfWidth, y: body.minY + 1))
            pointer.addLine(to: CGPoint(x: chrome.attachment, y: rect.minY))
            pointer.addLine(to: CGPoint(x: chrome.attachment + halfWidth, y: body.minY + 1))
        case .left:
            pointer.move(to: CGPoint(x: body.minX + 1, y: chrome.attachment - halfWidth))
            pointer.addLine(to: CGPoint(x: rect.minX, y: chrome.attachment))
            pointer.addLine(to: CGPoint(x: body.minX + 1, y: chrome.attachment + halfWidth))
        case .right:
            pointer.move(to: CGPoint(x: body.maxX - 1, y: chrome.attachment - halfWidth))
            pointer.addLine(to: CGPoint(x: rect.maxX, y: chrome.attachment))
            pointer.addLine(to: CGPoint(x: body.maxX - 1, y: chrome.attachment + halfWidth))
        }
        pointer.closeSubpath()
        path.addPath(pointer)
        return path
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
