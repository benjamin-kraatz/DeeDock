import SwiftUI

/// Decorative light stays inside the visible dock, so scrolling never carries the candles away.
/// The caller removes the animation clock while hidden, faded out, or reducing motion.
struct Mode69Overlay: View {
    let vertical: Bool
    let reduceTransparency: Bool
    let animated: Bool
    var cornerRadius: CGFloat = 22

    var body: some View {
        Group {
            if animated {
                TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                    artwork(time: context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 60))
                }
            } else {
                artwork(time: 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func artwork(time: Double) -> some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let radius = min(cornerRadius, min(size.width, size.height) / 2)
            let outline = Path(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: radius)
            // Leave the icon centers clear. Reduced transparency uses a solid rim instead of light.
            if !reduceTransparency {
                let ends = vertical
                    ? [CGPoint(x: size.width / 2, y: 0), CGPoint(x: size.width / 2, y: size.height)]
                    : [CGPoint(x: 0, y: size.height / 2), CGPoint(x: size.width, y: size.height / 2)]
                for center in ends {
                    context.fill(outline, with: .radialGradient(
                        Gradient(colors: [.red.opacity(0.48), .pink.opacity(0.12), .clear]),
                        center: center, startRadius: 0, endRadius: min(100, max(size.width, size.height) / 2)))
                }
            }
            context.stroke(outline, with: .color(reduceTransparency ? .red : .red.opacity(0.65)), lineWidth: 1.5)
            // Candles stay upright on side docks. Their small footprint fits inside the end caps.
            let centers = vertical
                ? [CGPoint(x: size.width / 2, y: 12), CGPoint(x: size.width / 2, y: size.height - 12)]
                : [CGPoint(x: 8, y: size.height / 2), CGPoint(x: size.width - 8, y: size.height / 2)]
            for (index, center) in centers.enumerated() {
                let flicker = sin(time * .pi * 2 + Double(index) * 2) * 0.7
                    + sin(time * .pi * 3 + Double(index)) * 0.3
                let wax = CGRect(x: center.x - 3, y: center.y, width: 6, height: 9)
                context.fill(Path(roundedRect: wax, cornerRadius: 1.5), with: .color(Color(red: 1, green: 0.84, blue: 0.65)))
                let flame = CGRect(x: center.x - 2.5 + flicker * 0.4,
                                   y: center.y - 8 - flicker, width: 5, height: 8 + flicker)
                context.fill(Path(ellipseIn: flame), with: .color(.orange))
                context.fill(Path(ellipseIn: flame.insetBy(dx: 1.4, dy: 2)), with: .color(.yellow))
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

#if DEBUG
#Preview("Mode 69, still and opaque") {
    HStack(spacing: 24) {
        ZStack {
            DockBackgroundView(reduceTransparency: false)
            Mode69Overlay(vertical: false, reduceTransparency: false, animated: false)
        }.frame(width: 280, height: 64)
        ZStack {
            DockBackgroundView(reduceTransparency: true)
            Mode69Overlay(vertical: true, reduceTransparency: true, animated: false)
        }.frame(width: 64, height: 220)
    }.padding(24)
}
#endif
