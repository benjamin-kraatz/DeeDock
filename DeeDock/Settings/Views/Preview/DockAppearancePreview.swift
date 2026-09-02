import SwiftUI

/// Non-interactive illustration of the requested icon size and hover scale.
///
/// Sizes use the dock's quadratic falloff so the shape of the magnification curve matches what
/// the real surface does, drawn at a fixed scale inside a fixed-height envelope: changing a
/// value animates the icons without resizing the card.
struct DockAppearancePreview: View {
    let iconSize: Double
    let magnification: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Preview points per configured point; keeps the largest supported icon inside the envelope.
    private static let scale = 0.5
    private static let symbols = ["safari", "envelope.fill", "music.note", "camera.fill",
                                  "terminal.fill", "gearshape.fill"]
    private static let tints: [Color] = [.blue, .cyan, .pink, .orange, .gray, .indigo]
    /// Index the illustrated pointer rests on.
    private static let focus = 2

    private func size(at index: Int) -> Double {
        // Mirrors DockGeometry.Layout.sizes: quadratic falloff across 2.5 slots.
        let influence = max(0, 1 - abs(Double(index - Self.focus)) / 2.5)
        return iconSize * Self.scale * (1 + (magnification - 1) * influence * influence)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Self.symbols.indices, id: \.self) { index in
                tile(index: index, size: size(at: index))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        .frame(height: 104, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.78), value: iconSize)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.78), value: magnification)
        .accessibilityHidden(true)
    }

    private func tile(index: Int, size: Double) -> some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(Self.tints[index % Self.tints.count].gradient)
            .overlay {
                Image(systemName: Self.symbols[index])
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.22), radius: size * 0.06, y: size * 0.03)
    }
}

#if DEBUG
#Preview("Appearance preview") {
    VStack(spacing: 12) {
        DockAppearancePreview(iconSize: 32, magnification: 1)
        DockAppearancePreview(iconSize: 48, magnification: 1.4)
        DockAppearancePreview(iconSize: 96, magnification: 2)
    }
    .padding()
    .frame(width: 460)
}
#endif
