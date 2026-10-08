import SwiftUI

/// The optional Harbor tile. Clicking it opens Harbor, or closes it when it is open.
///
/// Hover never opens Harbor and nothing here takes focus by itself.
struct DockHarborButton: View {
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let accessibilityFocus: (Bool) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var accessibilityFocused: Bool

    private var artworkOpacity: Double {
        DockAppearanceOpacity(settings: interaction.idleFade.settings,
                              idleFraction: interaction.idleFade.fraction,
                              reduceTransparency: reduceTransparency).icons
    }

    var body: some View {
        Button { interaction.openHarbor?() } label: {
            DockIconPresentation(size: size, edge: interaction.layout.edge,
                                 available: true, running: false, launching: false,
                                 keyboardSelected: selected, artworkOpacity: artworkOpacity,
                                 artworkAnimation: interaction.idleFade.animation) {
                HarborGlyph(size: size)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.harborName))
        .accessibilityHint(Text(.harborTileHint))
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
    }
}

/// Harbor's mark: three windows moored above a line of water, on a dusk-blue tile.
struct HarborGlyph: View {
    let size: CGFloat

    var body: some View {
        let unit = size / 64
        ZStack {
            RoundedRectangle(cornerRadius: 13.5 * unit, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.30, green: 0.33, blue: 0.45), Color(red: 0.09, green: 0.10, blue: 0.15)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 58 * unit, height: 58 * unit)
            HarborGlyphMark()
                .stroke(.white, style: StrokeStyle(lineWidth: 2.6 * unit, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: size * 0.04, y: size * 0.025)
        .accessibilityHidden(true)
    }
}

/// The line drawing inside ``HarborGlyph``, laid out on a 64-point grid.
struct HarborGlyphMark: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 64
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit) }
        var path = Path()
        for frame in [CGRect(x: 13.5, y: 13.5, width: 17, height: 12.5), CGRect(x: 33.5, y: 13.5, width: 17, height: 12.5),
                      CGRect(x: 13.5, y: 29.5, width: 37, height: 12.5)] {
            path.addRoundedRect(in: CGRect(origin: point(frame.minX, frame.minY),
                                           size: CGSize(width: frame.width * unit, height: frame.height * unit)),
                                cornerSize: CGSize(width: 2.6 * unit, height: 2.6 * unit))
        }
        path.move(to: point(12.5, 50.5))
        for step in 0..<4 {
            let start = 12.5 + CGFloat(step) * 9.75
            path.addQuadCurve(to: point(start + 9.75, 50.5), control: point(start + 4.875, step.isMultiple(of: 2) ? 46.5 : 54.5))
        }
        return path
    }
}

#if DEBUG
#Preview("Harbor glyph") {
    HStack(spacing: 24) {
        HarborGlyph(size: 32)
        HarborGlyph(size: 56)
        HarborGlyph(size: 96)
    }
    .padding(30)
}
#endif
