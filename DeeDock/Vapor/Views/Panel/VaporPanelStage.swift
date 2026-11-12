import SwiftUI

/// The panel window's root view: places ``VaporPanelView`` at the presentation's origin and
/// grows it out of the orb with a spring, or shrinks it back in. Under Reduce Motion the panel
/// only fades.
///
/// The window around it is transparent and larger than the panel (it covers the orb too), so
/// the scale anchor, which is the orb's centre, can sit outside the panel's own bounds.
struct VaporPanelStage: View {
    /// The named coordinate space rows use to find the orb.
    static let space = "VaporPanelStage"

    let controller: VaporController
    let presentation: VaporPanelPresentation

    @State private var size: CGSize = .zero

    var body: some View {
        let shown = presentation.isShown
        let reduceMotion = controller.reduceMotion
        let origin = presentation.panelOrigin
        let pull = presentation.pull
        VaporPanelView(controller: controller, pull: pull, pullTarget: pull == nil ? nil : presentation.orbPoint)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                size = newSize
                presentation.report(size: newSize)
            }
            .shadow(color: .black.opacity(0.3), radius: 30, y: 22)
            .scaleEffect(reduceMotion || shown ? 1 : 0.08, anchor: anchor(origin: origin))
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : (shown ? VaporMotion.panelOpen : VaporMotion.panelClose),
                       value: shown)
            .allowsHitTesting(shown && pull == nil)
            .padding(.leading, origin.x)
            .padding(.top, origin.y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(.named(Self.space))
    }

    /// The orb's centre as a unit point of the panel, usually outside 0…1.
    private func anchor(origin: CGPoint) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: (presentation.orbPoint.x - origin.x) / size.width,
                         y: (presentation.orbPoint.y - origin.y) / size.height)
    }
}
