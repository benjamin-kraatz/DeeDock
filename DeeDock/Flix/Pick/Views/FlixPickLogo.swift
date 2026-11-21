import SwiftUI

/// Flix Files' mark in small: the blue-to-indigo gradient square with a white document, drawn as
/// in the mockup so it stays crisp at 20 points.
struct FlixPickLogo: View {
    var size: CGFloat = FlixPickStyle.logoSize

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            // The mockup's 150° gradient: mostly downward, a little to the right.
            .fill(LinearGradient(stops: [.init(color: Color(red: 0.353, green: 0.784, blue: 0.98), location: 0),
                                         .init(color: Color(red: 0.039, green: 0.518, blue: 1), location: 0.55),
                                         .init(color: Color(red: 0.369, green: 0.361, blue: 0.902), location: 1)],
                                 startPoint: UnitPoint(x: 0.16, y: -0.09), endPoint: UnitPoint(x: 0.84, y: 1.09)))
            .overlay {
                FlixPickLogoGlyph()
                    .stroke(.white, style: StrokeStyle(lineWidth: size * 0.054, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.65, height: size * 0.65)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}

/// The document outline with a cut corner and two lines of text, on the mockup's 24-unit grid.
private struct FlixPickLogoGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + (x - 12) * unit, y: rect.midY + (y - 12) * unit)
        }
        var path = Path()
        path.move(to: point(6, 4))
        path.addLine(to: point(15, 4))
        path.addLine(to: point(18, 7))
        path.addLine(to: point(18, 20))
        path.addLine(to: point(6, 20))
        path.closeSubpath()
        path.move(to: point(9, 12))
        path.addLine(to: point(15, 12))
        path.move(to: point(9, 16))
        path.addLine(to: point(13, 16))
        return path
    }
}

#if DEBUG
#Preview("Flix Pick logo") {
    HStack(spacing: 16) {
        FlixPickLogo()
        FlixPickLogo(size: 48)
    }
    .padding(24)
}
#endif
