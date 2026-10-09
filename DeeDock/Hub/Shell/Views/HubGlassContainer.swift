import SwiftUI

/// Draws the Hub's glass (with its pointer) around `content`, places it inside the window, and
/// applies the open and close transitions.
///
/// The glass is native Liquid Glass in the ``HubGlassShape`` outline, so the pointer is part of
/// the same material rather than a separate fill. Reduce Transparency swaps it for an opaque window
/// background. Content is clipped to the outline so scrolled rows never cross the rounded corners.
struct HubGlassContainer<Content: View>: View {
    let state: HubShellState
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let layout = state.layout
        let shape = HubGlassShape(layout: layout)
        content
            .padding(.top, layout.edge == .top ? layout.pointerDepth : 0)
            .padding(.bottom, layout.edge == .bottom ? layout.pointerDepth : 0)
            .padding(.leading, layout.edge == .left ? layout.pointerDepth : 0)
            .padding(.trailing, layout.edge == .right ? layout.pointerDepth : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(shape)
            .modifier(HubGlassMaterial(shape: shape, opaque: state.reduceTransparency))
            .overlay {
                shape.stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.12), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .modifier(HubPresentationTransform(phase: state.phase, layout: layout, detached: state.isDetached,
                                               reduceMotion: state.reduceMotion))
            .padding(layout.insets)
    }
}

/// Liquid Glass, or an opaque fill under Reduce Transparency.
private struct HubGlassMaterial: ViewModifier {
    let shape: HubGlassShape
    let opaque: Bool

    func body(content: Content) -> some View {
        if opaque {
            content.background(shape.fill(Color(nsColor: .windowBackgroundColor)))
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

/// The open and close poses.
///
/// Opening springs from 90 % scale, 14 points toward the dock, blurred and transparent, to rest,
/// scaling about the pointer tip so the Hub grows out of its tile. Closing eases to 94 % and
/// 10 points toward the dock while fading. A detached window scales about its bottom center.
/// Reduce Motion keeps only the fade.
private struct HubPresentationTransform: ViewModifier {
    let phase: HubPresentationPhase
    let layout: HubBodyLayout
    let detached: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let scale: CGFloat
        let distance: CGFloat
        let blur: CGFloat
        switch phase {
        case .entering: (scale, distance, blur) = (HubStyle.openStartScale, 14, 6)
        case .shown: (scale, distance, blur) = (1, 0, 0)
        case .leaving: (scale, distance, blur) = (0.94, 10, 0)
        }
        let animated = !reduceMotion
        let edge = detached ? DockEdge.bottom : layout.edge
        let offset = Self.offset(toward: edge, distance: animated ? distance : 0)
        let pointerOffset = layout.pointerOffset
        return content
            .visualEffect { [scale, animated, detached] view, proxy in
                view.scaleEffect(animated ? scale : 1,
                                 anchor: detached ? .bottom : Self.anchor(edge: edge, pointerOffset: pointerOffset,
                                                                          size: proxy.size))
            }
            .offset(offset)
            .blur(radius: animated ? blur : 0)
            .opacity(phase == .shown ? 1 : 0)
    }

    private static func offset(toward edge: DockEdge, distance: CGFloat) -> CGSize {
        switch edge {
        case .bottom: CGSize(width: 0, height: distance)
        case .top: CGSize(width: 0, height: -distance)
        case .left: CGSize(width: -distance, height: 0)
        case .right: CGSize(width: distance, height: 0)
        }
    }

    /// The pointer tip as a unit point of the glass rectangle (body plus pointer strip).
    private nonisolated static func anchor(edge: DockEdge, pointerOffset: CGFloat, size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .bottom }
        switch edge {
        case .bottom: return UnitPoint(x: pointerOffset / size.width, y: 1)
        case .top: return UnitPoint(x: pointerOffset / size.width, y: 0)
        case .left: return UnitPoint(x: 0, y: pointerOffset / size.height)
        case .right: return UnitPoint(x: 1, y: pointerOffset / size.height)
        }
    }
}
