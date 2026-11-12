import SwiftUI

/// Liquid Glass in `shape`, or an opaque window-background fill when Reduce Transparency is on.
struct VaporGlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let reduceTransparency: Bool

    #if DEBUG
    @Environment(\.vaporGlassStandIn) private var glassStandIn
    #endif

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        } else {
            #if DEBUG
            if glassStandIn {
                content
                    .background { VaporGlassStandInFill().clipShape(shape) }
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            } else {
                content.glassEffect(.regular, in: shape)
            }
            #else
            content.glassEffect(.regular, in: shape)
            #endif
        }
    }
}

extension View {
    /// Vapor's glass surface, opaque under Reduce Transparency.
    func vaporGlass<S: InsettableShape>(in shape: S, reduceTransparency: Bool) -> some View {
        modifier(VaporGlassBackground(shape: shape, reduceTransparency: reduceTransparency))
    }
}

#if DEBUG
extension EnvironmentValues {
    /// Snapshot tests only: offscreen rendering can't draw Liquid Glass (it samples what's behind
    /// the window), and content inside it disappears. This draws the mockup's translucent panel
    /// tint instead, so snapshots show the content on something glass-like.
    @Entry var vaporGlassStandIn = false
}

/// The mockup's panel colour: a dark or light translucent tint, without the blur.
private struct VaporGlassStandInFill: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        colorScheme == .dark
            ? Color(red: 30 / 255, green: 31 / 255, blue: 40 / 255, opacity: 0.78)
            : Color(red: 250 / 255, green: 250 / 255, blue: 253 / 255, opacity: 0.8)
    }
}
#endif
