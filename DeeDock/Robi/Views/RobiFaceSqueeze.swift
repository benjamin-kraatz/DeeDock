import SwiftUI

extension EnvironmentValues {
    /// True while the pointer holds Robi's face down, dragging the tab included, so the face
    /// squeezes instead of dimming like a button. Set by `RobiFaceHandle`.
    @Entry var robiFacePressed = false
}

/// A squeezed-shut eye: a chevron pointing at the nose, `>` on the left and `<` on the right.
struct RobiSquintShape: Shape {
    /// True for the right eye, whose chevron points left.
    var mirrored = false

    func path(in rect: CGRect) -> Path {
        let tip = mirrored ? rect.minX : rect.maxX
        let back = mirrored ? rect.maxX : rect.minX
        var path = Path()
        path.move(to: CGPoint(x: back, y: rect.minY))
        path.addLine(to: CGPoint(x: tip, y: rect.midY))
        path.addLine(to: CGPoint(x: back, y: rect.maxY))
        return path
    }
}

/// The wobbly mouth of a face being squeezed.
struct RobiGrimaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        let bumps = 3
        let step = rect.width / CGFloat(bumps * 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        for index in 1...(bumps * 2) {
            path.addLine(to: CGPoint(x: rect.minX + step * CGFloat(index), y: index.isMultiple(of: 2) ? rect.midY : rect.maxY))
        }
        return path
    }
}

/// A single drop of sweat, round at the bottom and pointed at the top.
struct RobiSweatDropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        let centre = CGPoint(x: rect.midX, y: rect.maxY - radius)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: centre.y), control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.45))
        path.addArc(center: centre, radius: radius, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.45))
        path.closeSubpath()
        return path
    }
}

/// The shudder after a squeeze: Robi shakes it off, wobbling side to side as it springs back
/// into shape.
struct RobiWobble {
    var angle: Angle = .zero
    var stretch: CGFloat = 1

    @KeyframesBuilder<RobiWobble>
    static func keyframes() -> some Keyframes<RobiWobble> {
        KeyframeTrack(\.angle) {
            LinearKeyframe(.degrees(-9), duration: 0.06)
            LinearKeyframe(.degrees(8), duration: 0.08)
            LinearKeyframe(.degrees(-6), duration: 0.08)
            LinearKeyframe(.degrees(4), duration: 0.08)
            LinearKeyframe(.degrees(-2), duration: 0.08)
            SpringKeyframe(.zero, duration: 0.2, spring: .snappy)
        }
        KeyframeTrack(\.stretch) {
            SpringKeyframe(1.12, duration: 0.12, spring: .snappy)
            SpringKeyframe(1, duration: 0.45, spring: .bouncy)
        }
    }
}
