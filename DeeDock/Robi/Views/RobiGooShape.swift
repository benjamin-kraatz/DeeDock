import SwiftUI

/// Robi's tab pulled away from the window's edge like goo: the flares stay on the edge, a neck
/// thins as it stretches, and the bulb holding the face follows the pull and leans sideways.
///
/// Drawn in the same orientation as `RobiTabShape` (edge at the bottom) and flipped the same way
/// when `inverted`. With no pull and no lean it is exactly the tab's outline, so the goo starts
/// and ends without a jump. A negative pull squashes the bulb towards the edge instead, which is
/// how the snap-back overshoots. The lean may draw outside `rect`; the panel leaves room for it.
struct RobiGooShape: Shape {
    /// The bulb's sideways offset, in points.
    var lean: CGFloat
    /// How far the bulb is pulled from the edge, in points; negative squashes it.
    var pull: CGFloat
    var inverted = true
    /// False leaves the edge along the window open, for drawing only the rim.
    var closed = true
    var flare: CGFloat = RobiMetrics.flare
    var corner: CGFloat = RobiMetrics.corner

    func path(in rect: CGRect) -> Path {
        let width = rect.width, height = rect.height, r = flare
        guard width > 2 * r, height > r else { return Path() }
        // The bulb is a normal tab's height, or shorter while squashed; the rest is neck.
        let bulb = min(RobiMetrics.tabHeight, height)
        let neck = max(0, height - bulb)
        let c = min(corner, (width - 2 * r) / 2, bulb - r)
        // The neck thins to under half the tab's width at full pull.
        let pinch = (width / 2 - r) * 0.55 * min(1, neck / RobiGoo.pullLimit)
        let bulbBottom = bulb - r
        var path = Path()
        path.move(to: CGPoint(x: 0, y: height))
        path.addQuadCurve(to: CGPoint(x: r, y: height - r), control: CGPoint(x: r, y: height))
        path.addCurve(to: CGPoint(x: r + lean, y: bulbBottom),
                      control1: CGPoint(x: r + pinch, y: height - r - neck * 0.35),
                      control2: CGPoint(x: r + lean + pinch * 0.6, y: bulbBottom + neck * 0.35))
        path.addLine(to: CGPoint(x: r + lean, y: c))
        path.addQuadCurve(to: CGPoint(x: r + c + lean, y: 0), control: CGPoint(x: r + lean, y: 0))
        path.addLine(to: CGPoint(x: width - r - c + lean, y: 0))
        path.addQuadCurve(to: CGPoint(x: width - r + lean, y: c), control: CGPoint(x: width - r + lean, y: 0))
        path.addLine(to: CGPoint(x: width - r + lean, y: bulbBottom))
        path.addCurve(to: CGPoint(x: width - r, y: height - r),
                      control1: CGPoint(x: width - r + lean - pinch * 0.6, y: bulbBottom + neck * 0.35),
                      control2: CGPoint(x: width - r - pinch, y: height - r - neck * 0.35))
        path.addQuadCurve(to: CGPoint(x: width, y: height), control: CGPoint(x: width - r, y: height))
        if closed { path.closeSubpath() }
        guard inverted else { return path }
        return path.applying(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -height))
    }
}

/// The goo's tinted body and rim. Unlike `RobiTabSurface` its shadow is not masked to the
/// tab's frame, because the leaning bulb reaches past it.
struct RobiGooSurface: View {
    let tint: Color
    let rim: Color
    let goo: CGSize

    var body: some View {
        ZStack {
            RobiGooShape(lean: goo.width, pull: goo.height)
                .fill(tint)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
            RobiGooShape(lean: goo.width, pull: goo.height, closed: false)
                .stroke(rim, lineWidth: 1)
        }
    }
}

#Preview("Goo") {
    HStack(alignment: .top, spacing: 30) {
        let pulls = [CGSize(width: 0, height: 0), CGSize(width: 0, height: 50), CGSize(width: 30, height: 100),
                     CGSize(width: -20, height: -6)]
        ForEach(pulls.indices, id: \.self) { index in
            let goo = pulls[index]
            RobiGooSurface(tint: Color(red: 0.13, green: 0.16, blue: 0.24), rim: .white.opacity(0.14), goo: goo)
                .frame(width: RobiMetrics.tabWidth, height: RobiMetrics.tabHeight + goo.height)
        }
    }
    .padding(40)
    .frame(height: 240, alignment: .top)
    .background(Color(red: 0.85, green: 0.82, blue: 0.95))
}
