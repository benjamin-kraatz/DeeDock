import SwiftUI

/// The capsule beside the cursor: what a release does, and on copy targets that offer it, that
/// Shift moves instead. Switching modes swaps the symbol, text, and tint in place.
struct DockDropHintView: View {
    let model: DockDropHintModel
    private let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    var body: some View {
        HStack(spacing: 0) {
            if model.trailing { Spacer(minLength: 0) }
            if model.visible {
                capsule
                    .transition(.scale(scale: 0.85, anchor: model.trailing ? .trailing : .leading).combined(with: .opacity))
            }
            if !model.trailing { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private var capsule: some View {
        HStack(spacing: 7) {
            Image(systemName: model.moving ? "arrow.right.doc.on.clipboard" : "plus.square.on.square")
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
            Text(model.moving ? .dropHintMove(destination: model.destination) : .dropHintCopy(destination: model.destination))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.interpolate)
            if model.offersMove, !model.moving {
                Text(.dropHintShiftToMove)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.18), in: .rect(cornerRadius: 5))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background {
            Capsule().fill(tint.gradient)
                .opacity(reduceTransparency ? 1 : 0.92)
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .fixedSize()
    }

    /// Copy uses the system accent; move switches to orange, the color macOS uses for caution,
    /// so the change in meaning is visible at a glance and not only in the text.
    private var tint: Color { model.moving ? .orange : .accentColor }
}

#if DEBUG
@MainActor
private func dropHintPreview(moving: Bool, offersMove: Bool = true, destination: String = "BILLEX DIST") -> some View {
    let model = DockDropHintModel()
    model.destination = destination
    model.moving = moving
    model.offersMove = offersMove
    model.visible = true
    return DockDropHintView(model: model).frame(width: 340, height: 44).padding()
}

#Preview("Copy, Shift offered") { dropHintPreview(moving: false) }
#Preview("Move") { dropHintPreview(moving: true) }
#Preview("Copy, long name") {
    dropHintPreview(moving: false, destination: "Fotos 2026 – Sicherung mit sehr langem Namen")
}
#Preview("Copy, dark") { dropHintPreview(moving: false).preferredColorScheme(.dark) }
#endif
