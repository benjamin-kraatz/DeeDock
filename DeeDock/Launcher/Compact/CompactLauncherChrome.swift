import SwiftUI

/// Liquid Glass in the popover outline, with large continuous corners and a soft pointer.
///
/// Content is clipped to the outline before the glass is applied, so scrolled tiles never cross
/// the rounded corners while the glass keeps its edge highlights. Reduce Transparency swaps the
/// glass for an opaque window background.
private struct CompactLauncherChrome: ViewModifier {
    let chrome: DockPopoverChrome
    let opaque: Bool

    static let cornerRadius: CGFloat = 26

    func body(content: Content) -> some View {
        let shape = DockPopoverShape(chrome: chrome, cornerRadius: Self.cornerRadius, softPointer: true)
        let depth = DockPopoverGeometry.pointerDepth
        let framed = content
            .padding(.top, chrome.edge == .top ? depth : 0)
            .padding(.bottom, chrome.edge == .bottom ? depth : 0)
            .padding(.leading, chrome.edge == .left ? depth : 0)
            .padding(.trailing, chrome.edge == .right ? depth : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(shape)
        if opaque {
            framed.background(shape.fill(Color(nsColor: .windowBackgroundColor)))
        } else {
            framed.glassEffect(.regular, in: shape)
        }
    }
}

extension View {
    /// The compact Launcher's glass panel and pointer.
    func compactLauncherChrome(_ chrome: DockPopoverChrome, opaque: Bool) -> some View {
        modifier(CompactLauncherChrome(chrome: chrome, opaque: opaque))
    }
}
