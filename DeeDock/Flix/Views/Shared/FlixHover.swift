import SwiftUI

/// Gives a button style's body its hover state.
///
/// A `ButtonStyle` is not a view, so it cannot reliably own `@State`; this small view owns the
/// flag instead and eases the highlight in and out. Hover only highlights: nothing opens or takes
/// focus because the pointer is over it.
struct FlixHover<Content: View>: View {
    @ViewBuilder var content: (_ hovered: Bool) -> Content
    @State private var hovered = false

    var body: some View {
        content(hovered)
            .onHover { hovered = $0 }
            .animation(FlixMotion.hover, value: hovered)
    }
}
