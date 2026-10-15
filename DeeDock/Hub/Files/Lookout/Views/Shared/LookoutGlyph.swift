import SwiftUI

/// Lookout's spyglass on its tripod, drawn from the mockup's 24-unit SVG (`SPY`) so it matches the approved design.
/// SF Symbols has binoculars but no spyglass. Stroked in the current foreground style.
struct LookoutGlyph: View {
    var size: CGFloat = 15

    var body: some View {
        LookoutGlyphShape()
            .stroke(style: StrokeStyle(lineWidth: max(1, size * 1.6 / 24), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The spyglass outline in a 24 × 24 design space, scaled to the rect.
private struct LookoutGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        // The tube.
        path.move(to: point(3.5, 14.5))
        path.addLine(to: point(15, 6))
        path.addLine(to: point(18, 10))
        path.addLine(to: point(6.5, 18.5))
        path.closeSubpath()
        // The eyepiece at the wide end.
        path.move(to: point(15, 6))
        path.addLine(to: point(16.6, 4.8))
        path.addLine(to: point(19.6, 8.8))
        path.addLine(to: point(18, 10))
        // The tripod.
        path.move(to: point(7.5, 16))
        path.addLine(to: point(9, 21))
        path.move(to: point(6, 21))
        path.addLine(to: point(12, 21))
        // The lens.
        path.addEllipse(in: CGRect(origin: point(4.4, 15.4), size: CGSize(width: 1.2 * scale, height: 1.2 * scale)))
        return path
    }
}

#Preview("Glyph") {
    HStack(spacing: 16) {
        LookoutGlyph(size: 15)
        LookoutGlyph(size: 22)
        LookoutGlyph(size: 34)
    }
    .foregroundStyle(LookoutTheme(.dark).accent)
    .padding(24)
    .preferredColorScheme(.dark)
}
