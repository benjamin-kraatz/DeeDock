import SwiftUI
import UniformTypeIdentifiers

/// Liquid Glass in `shape`, or an opaque window-background fill when Reduce Transparency is on.
struct VaporGlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

extension View {
    /// Vapor's glass surface, opaque under Reduce Transparency.
    func vaporGlass<S: InsettableShape>(in shape: S, reduceTransparency: Bool) -> some View {
        modifier(VaporGlassBackground(shape: shape, reduceTransparency: reduceTransparency))
    }
}

/// The macOS folder icon for one folder. Uses the generic folder icon so previews and rows
/// never read live workspace state for a custom icon.
struct VaporFolderIcon: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(for: .folder))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
