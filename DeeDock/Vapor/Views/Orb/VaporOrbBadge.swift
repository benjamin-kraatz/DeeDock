import SwiftUI

/// The folder count on the orb's outer top corner. It pops when the count changes and shrinks
/// away when the orb empties.
struct VaporOrbBadge: View {
    let count: Int
    let corner: VaporBadgeCorner
    let palette: VaporOrbPalette
    let reduceMotion: Bool

    var body: some View {
        let diameter = VaporGeometry.orbDiameter
        Text(count, format: .number)
            .font(.system(size: 11.5, weight: .bold).monospacedDigit())
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(palette.badgeFill, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
            .keyframeAnimator(initialValue: 1.0, trigger: count) { content, scale in
                content.scaleEffect(reduceMotion ? 1 : scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.35, duration: 0.01)
                    SpringKeyframe(1, duration: 0.38, spring: .init(response: 0.38, dampingRatio: 0.5))
                }
            }
            .opacity(count > 0 ? 1 : 0)
            .scaleEffect(count > 0 ? 1 : 0.4)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.55), value: count > 0)
            // The badge's outer edge overhangs the orb's square by 4 pt, as in the mockup.
            .offset(x: corner == .topTrailing ? 4 : -4)
            .frame(width: diameter, height: diameter, alignment: corner == .topTrailing ? .topTrailing : .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The faint "drop here" glyph of an empty orb: an arrow into a tray.
struct VaporOrbEmptyGlyph: View {
    var body: some View {
        VaporDropGlyphShape()
            .stroke(VaporStyle.faint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            .opacity(0.75)
            .frame(width: VaporGeometry.orbDiameter * 0.34, height: VaporGeometry.orbDiameter * 0.34)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The mockup's arrow-into-tray glyph, drawn on a 24-unit grid and scaled to the frame.
private struct VaporDropGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit) }
        var path = Path()
        path.move(to: point(12, 4))
        path.addLine(to: point(12, 14))
        path.move(to: point(8, 10.5))
        path.addLine(to: point(12, 14.5))
        path.addLine(to: point(16, 10.5))
        path.move(to: point(5, 16.5))
        path.addLine(to: point(5, 17.7))
        path.addQuadCurve(to: point(6.8, 19.5), control: point(5, 19.5))
        path.addLine(to: point(17.2, 19.5))
        path.addQuadCurve(to: point(19, 17.7), control: point(19, 19.5))
        path.addLine(to: point(19, 16.5))
        return path
    }
}
