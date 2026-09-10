import SwiftUI

/// Edge-weighted lighting leaves the work area transparent and never flashes.
struct Mode69AmbientView: View {
    let reduceMotion: Bool
    let reduceTransparency: Bool

    var body: some View {
        Group {
            if reduceMotion || reduceTransparency {
                artwork(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    artwork(time: context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 120))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func artwork(time: Double) -> some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let breath = sin(time * .pi / 15)
            if !reduceTransparency {
                // The central wash is just 1.5%. Most color falls inside the outer 15%.
                context.fill(Path(bounds), with: .color(.red.opacity(0.015)))
                let depth = min(size.width, size.height) * 0.16
                let lights: [(CGPoint, CGPoint)] = [
                    (.zero, CGPoint(x: depth, y: 0)),
                    (CGPoint(x: size.width, y: 0), CGPoint(x: size.width - depth, y: 0)),
                    (.zero, CGPoint(x: 0, y: depth)),
                    (CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: size.height - depth))
                ]
                for (start, end) in lights {
                    context.fill(Path(bounds), with: .linearGradient(
                        Gradient(colors: [Color(red: 0.85, green: 0.015, blue: 0.12).opacity(0.17 + breath * 0.015), .clear]),
                        startPoint: start, endPoint: end))
                }
                for side in [0.0, 1.0] {
                    let center = CGPoint(x: size.width * side,
                                         y: size.height * (0.55 + sin(time * .pi / 30 + side * .pi) * 0.12))
                    context.fill(Path(bounds), with: .radialGradient(
                        Gradient(colors: [.pink.opacity(0.13), .red.opacity(0.04), .clear]),
                        center: center, startRadius: 0, endRadius: size.height * 0.45))
                }
            } else {
                // No translucent sheet over text when Reduce Transparency is requested.
                context.stroke(Path(bounds.insetBy(dx: 1, dy: 1)), with: .color(.red), lineWidth: 2)
            }
            // A small cluster in each bottom corner avoids the menu bar and central dock.
            for side in [0, 1] {
                for candle in 0..<3 {
                    let x = side == 0 ? CGFloat(18 + candle * 17) : size.width - CGFloat(18 + candle * 17)
                    let height = CGFloat([28, 42, 23][candle])
                    let base = size.height - 8
                    let phase = Double(candle + side * 3)
                    let flicker = sin(time * .pi + phase) * 0.7 + sin(time * .pi * 2 + phase) * 0.3
                    let tip = CGPoint(x: x + flicker, y: base - height - 17 - flicker)
                    if !reduceTransparency {
                        context.fill(Path(bounds), with: .radialGradient(
                            Gradient(colors: [.orange.opacity(0.13), .clear]),
                            center: CGPoint(x: x, y: base - height - 5), startRadius: 0, endRadius: 60))
                    }
                    let wax = CGRect(x: x - 5, y: base - height, width: 10, height: height)
                    context.fill(Path(roundedRect: wax, cornerRadius: 2), with: .linearGradient(
                        Gradient(colors: [Color(red: 0.85, green: 0.55, blue: 0.35), Color(red: 0.4, green: 0.11, blue: 0.10)]),
                        startPoint: CGPoint(x: wax.minX, y: 0), endPoint: CGPoint(x: wax.maxX, y: 0)))
                    var flame = Path()
                    flame.move(to: tip)
                    flame.addCurve(to: CGPoint(x: x, y: base - height - 1),
                                   control1: CGPoint(x: x + 9, y: tip.y + 10),
                                   control2: CGPoint(x: x + 5, y: base - height - 1))
                    flame.addCurve(to: tip, control1: CGPoint(x: x - 7, y: base - height - 1),
                                   control2: CGPoint(x: x - 5, y: tip.y + 9))
                    context.fill(flame, with: .linearGradient(Gradient(colors: [.orange, .yellow]),
                                                            startPoint: tip, endPoint: CGPoint(x: x, y: base - height)))
                }
            }
        }
    }
}

#if DEBUG
#Preview("Mode 69+ still") {
    Mode69AmbientView(reduceMotion: true, reduceTransparency: false)
        .frame(width: 900, height: 560)
}
#endif
