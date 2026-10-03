import SwiftUI

/// The dock's native material, with an opaque alternative for Reduce Transparency.
///
/// `tint` colors one island. The glass stays the same regular material the launcher morphs
/// into; the hue is a tint plus a brighter lip on the outward edge, matching the colored
/// capsules in the island reference. Reduce Transparency ignores the tint and stays opaque.
struct DockBackgroundView: View, Animatable {
    let reduceTransparency: Bool
    /// Effective radius, capped by the caller to the current material bounds.
    var cornerRadius: CGFloat = 22
    /// Idle dimming is intentional. At full visibility, the glass has no opacity wrapper.
    var idleOpacity: Double = 1
    /// Hue borrowed from the icons in this island. Nil keeps the untinted dock material.
    var tint: Color? = nil
    /// Which side of the capsule faces the screen edge, so the colored lip sits outward.
    var edge: DockEdge = .bottom
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
        } else if let tint {
            let shape = RoundedRectangle(cornerRadius: cornerRadius)
            shape
                .fill(.clear)
                .glassEffect(.regular.tint(tint.opacity(0.28)), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [.clear, tint.opacity(0.04), tint.opacity(0.34)],
                            startPoint: inward,
                            endPoint: outward
                        )
                    )
                    .allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.72), tint.opacity(0.18), tint],
                            startPoint: inward,
                            endPoint: outward
                        ),
                        lineWidth: 1.15
                    )
                    .allowsHitTesting(false)
                }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.clear)
                // Matches the launcher's material. The dock's surface grows into the launcher's
                // rect, so a different material at either end would step in brightness mid-morph.
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }

    /// Inward face of a bottom, top, or side dock. The specular highlight stays on this side.
    private var inward: UnitPoint {
        switch edge {
        case .bottom: .top
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
    }

    /// Screen-edge face. The island's own color is strongest here.
    private var outward: UnitPoint {
        switch edge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
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
