import SwiftUI

/// A tab whose bottom corners flare outward into the window's edge, so it reads as growing out of
/// the title bar rather than sitting on it. Inverted, it hangs down from the edge like a notch.
struct RobiTabShape: Shape {
    var flare: CGFloat = RobiMetrics.flare
    var corner: CGFloat = RobiMetrics.corner
    var inverted = false
    /// False leaves the edge along the window open, for drawing only the rim.
    var closed = true

    func path(in rect: CGRect) -> Path {
        let width = rect.width, height = rect.height, r = flare
        guard width > 2 * r, height > r else { return Path() }
        let c = min(corner, (width - 2 * r) / 2, height - r)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: height))
        path.addQuadCurve(to: CGPoint(x: r, y: height - r), control: CGPoint(x: r, y: height))
        path.addLine(to: CGPoint(x: r, y: c))
        path.addQuadCurve(to: CGPoint(x: r + c, y: 0), control: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: width - r - c, y: 0))
        path.addQuadCurve(to: CGPoint(x: width - r, y: c), control: CGPoint(x: width - r, y: 0))
        path.addLine(to: CGPoint(x: width - r, y: height - r))
        path.addQuadCurve(to: CGPoint(x: width, y: height), control: CGPoint(x: width - r, y: height))
        if closed { path.closeSubpath() }
        guard inverted else { return path }
        return path.applying(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -height))
    }
}

#Preview("Above and inside") {
    VStack(spacing: 24) {
        RobiTabShape().fill(.white).frame(width: 108, height: 42)
        RobiTabShape(inverted: true).fill(Color(red: 0.13, green: 0.16, blue: 0.24)).frame(width: 108, height: 42)
    }
    .padding(30)
    .background(Color(red: 0.85, green: 0.82, blue: 0.95))
}
