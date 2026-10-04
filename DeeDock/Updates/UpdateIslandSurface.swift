#if DIRECT_DISTRIBUTION
import SwiftUI

/// Indigo-to-coral lens that carries the island's glyph. It is the bead's only content.
struct UpdateIslandMark: View {
    static let diameter: CGFloat = 44

    let symbol: String
    /// False until the bead lands; the glyph then settles into the lens.
    let lit: Bool

    var body: some View {
        Circle()
            .fill(UpdateAwarenessMark.fill)
            .overlay {
                // Top-weighted highlight so the lens reads as lit from the screen edge above.
                Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(lit ? 1 : 0.4)
                    .opacity(lit ? 1 : 0)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .accessibilityHidden(true)
    }
}

/// Puts the island's content on Liquid Glass with the update gradient along its rim.
///
/// The glass is applied to the content itself, which is what keeps the content in front of
/// it. The content is clipped to the same shape first, so anything laid out for the island's
/// final size is uncovered by the glass as it grows instead of spilling past its edge.
/// `glow` drives the rim: full while the bead lands, then relaxed to a quiet signature edge.
struct UpdateIslandGlass: ViewModifier {
    let reduceTransparency: Bool
    let glow: Double

    /// Concentric with the mark at the island's single-line height; a bead clamps it to a circle.
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 36, style: .continuous) }

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content
                    .clipShape(shape)
                    .background {
                        shape.fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
                    }
            } else {
                content
                    .clipShape(shape)
                    .glassEffect(.regular, in: shape)
            }
        }
        .overlay {
            shape
                .strokeBorder(LinearGradient(colors: [UpdateAwarenessMark.indigo, UpdateAwarenessMark.coral],
                                             startPoint: .leading, endPoint: .trailing),
                              lineWidth: 1.5)
                // The rim cools slowly after the island opens. Scoping the animation to the
                // opacity keeps the rim's geometry on the glass's morph spring; a plain
                // `.animation(_:value:)` here would retime its size and detach it from the glass.
                .animation(.easeOut(duration: glow < 1 ? 1.3 : 0.25)) { $0.opacity(glow) }
                .allowsHitTesting(false)
        }
    }
}
#endif
