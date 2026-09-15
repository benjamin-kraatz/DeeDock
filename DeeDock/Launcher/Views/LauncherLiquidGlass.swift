import SwiftUI

/// Bridges the presentation's two content trees into one native AppKit glass container.
struct LauncherLiquidGlass: NSViewRepresentable {
    let state: LauncherState
    let dock: AnyView
    let dockCanvasSize: CGSize
    let dockCornerRadius: CGFloat
    let reduceMotion: Bool
    let reduceTransparency: Bool

    private var geometry: LauncherLiquidGeometry {
        LauncherLiquidGeometry(dock: state.dockRect, destination: state.contentRect,
                               dockRadius: dockCornerRadius)
    }

    private var launcher: AnyView {
        AnyView(LauncherView(state: state)
            .frame(width: state.contentRect.width, height: state.contentRect.height))
    }

    func makeNSView(context: Context) -> LauncherLiquidGlassView {
        LauncherLiquidGlassView(geometry: geometry, dock: dock, launcher: launcher)
    }

    func updateNSView(_ view: LauncherLiquidGlassView, context: Context) {
        view.onSettled = { expanded in state.transitionCompleted?(expanded) }
        view.update(geometry: geometry, dock: dock, launcher: launcher,
                    dockCanvas: CGRect(origin: CGPoint(x: state.dockContentOffset.width,
                                                       y: state.dockContentOffset.height), size: dockCanvasSize),
                    expanded: state.expanded, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
    }

    static func dismantleNSView(_ view: LauncherLiquidGlassView, coordinator: ()) {
        view.onSettled = nil
        view.stop()
    }
}
