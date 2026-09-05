import SwiftUI

/// The dock's native material, with an opaque alternative for Reduce Transparency.
struct DockBackgroundView: View, Animatable {
    let reduceTransparency: Bool
    /// Effective radius, capped by the caller to the current material bounds.
    var cornerRadius: CGFloat = 22
    /// Idle dimming is intentional. At full visibility, the glass has no opacity wrapper.
    var idleOpacity: Double = 1
    // Interpolate the scalar before choosing a branch so returning to native glass preserves
    // the configured duration instead of swapping whole views at the start of a transition.
    var animatableData: Double {
        get { idleOpacity }
        set { idleOpacity = newValue }
    }

    var body: some View {
        if idleOpacity >= 1 {
            material
        } else if idleOpacity > 0 {
            material
                .opacity(idleOpacity)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private var material: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius).fill(
                Color(nsColor: .windowBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(
                    .primary.opacity(0.14),
                    lineWidth: 0.5
                )
            )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.clear)
                .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

#if DEBUG
    #Preview("Glass and opaque material") {
        VStack(spacing: 20) {
            DockBackgroundView(reduceTransparency: false)
            DockBackgroundView(reduceTransparency: true, cornerRadius: 0)
        }
        .frame(width: 300, height: 180)
        .padding(20)
    }
#endif
