import SwiftUI

/// A CSS-style inset shadow on a circle: the area outside the circle, moved by `offset`, grown
/// inward by `spread` (negative spread pulls it back), blurred, and clipped to the circle.
/// This is how the mockup lights the glass from inside: a blue glow pooling at the bottom, a
/// soft white band under the top edge, and an even blue haze that rises as a drag nears.
struct VaporInsetGlow: View {
    let color: Color
    var offset: CGFloat = 0
    /// CSS blur radius; the Gaussian uses half of it, as browsers do.
    let blur: CGFloat
    var spread: CGFloat = 0

    var body: some View {
        VaporCircleOutside(offset: offset, spread: spread, margin: blur * 2 + abs(offset) + 4)
            .fill(color, style: FillStyle(eoFill: true))
            .blur(radius: blur / 2)
            .clipShape(Circle())
            .allowsHitTesting(false)
    }
}

/// Everything outside a circle (inscribed in the rect, then moved and resized), as an even-odd path.
private struct VaporCircleOutside: Shape {
    let offset: CGFloat
    let spread: CGFloat
    let margin: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect.insetBy(dx: -margin, dy: -margin))
        path.addEllipse(in: rect.insetBy(dx: spread, dy: spread).offsetBy(dx: 0, dy: offset))
        return path
    }
}

/// The glass's edge: a fine rim line and the inset glows, plus the outer drop glow.
///
/// `proximity` (0…1) brightens the inner haze and the outer glow as a drag nears; `isOver`
/// switches to the brighter "drop here" rim.
struct VaporOrbRim: View {
    let palette: VaporOrbPalette
    let proximity: Double
    let isOver: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(VaporOrbPalette.dropBlue.opacity(isOver ? 0.7 : proximity * 0.6))
                .blur(radius: isOver ? 17 : max(proximity * 15, 0.1))
                .mask(VaporCircleOutsideMask())
            VaporInsetGlow(color: VaporOrbPalette.iceBlue.opacity(isOver ? 0.6 : 0.45), offset: -14, blur: 24, spread: -8)
            VaporInsetGlow(color: .white.opacity(isOver ? 0.5 : 0.45), offset: 12, blur: 20, spread: -12)
            VaporInsetGlow(color: Color(red: 90 / 255, green: 150 / 255, blue: 1)
                .opacity(isOver ? 0.6 : 0.10 + proximity * 0.45), blur: isOver ? 30 : 26)
            Circle()
                .strokeBorder(isOver ? Color(red: 150 / 255, green: 210 / 255, blue: 1, opacity: 0.9) : palette.rimLine,
                              lineWidth: isOver ? 1.5 : 1)
        }
        .animation(.easeOut(duration: 0.2), value: isOver)
        .allowsHitTesting(false)
    }
}

/// The red rim of a refused drop. The orb keyframes its opacity on each refusal.
struct VaporOrbRefusalRim: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 1, green: 80 / 255, blue: 70 / 255, opacity: 0.5))
                .blur(radius: 13)
                .mask(VaporCircleOutsideMask())
            VaporInsetGlow(color: Color(red: 1, green: 80 / 255, blue: 70 / 255, opacity: 0.45), blur: 26)
            Circle().strokeBorder(VaporOrbPalette.refusalRed.opacity(0.9), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

/// Masks to the area outside the orb's circle, so an outer glow never tints the glass itself.
private struct VaporCircleOutsideMask: View {
    var body: some View {
        VaporCircleOutside(offset: 0, spread: 0, margin: 40)
            .fill(style: FillStyle(eoFill: true))
    }
}
