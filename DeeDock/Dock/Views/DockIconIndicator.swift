import SwiftUI

/// Running-state artwork inside the icon square. It never changes layout or hit regions.
/// Apply before keyboard focus and launch overlays so those interaction states stay on top.
///
/// These styles are decoration laid over any icon. `variant` and `animated` are used only
/// by Stardust; every other style ignores them.
struct DockIconIndicator: ViewModifier {
    let style: DockSettings.RunningIndicatorStyle
    let running: Bool
    let size: CGFloat
    var variant: DockIndicatorVariant = .neutral
    var animated: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if running {
                    DockIndicatorForeground(style: style, size: size, variant: variant,
                                            animated: animated && !reduceMotion)
                        .accessibilityHidden(true).allowsHitTesting(false)
                }
            }
    }
}

/// Frames and corner ornaments leave the center of each app icon recognizable.
private struct DockIndicatorForeground: View {
    let style: DockSettings.RunningIndicatorStyle
    let size: CGFloat
    /// Used only by Stardust, which scatters its sparkles from the variant's seed.
    var variant: DockIndicatorVariant = .neutral
    var animated = false

    var body: some View {
        ZStack {
            switch style {
            case .targetLock:
                DockTargetBrackets()
                    .stroke(.black, style: StrokeStyle(lineWidth: max(4, size * 0.08), lineCap: .square))
                    .padding(size * 0.075)
                DockTargetBrackets()
                    .stroke(.green, style: StrokeStyle(lineWidth: max(2, size * 0.04), lineCap: .square))
                    .padding(size * 0.075)
            case .orbit:
                Circle().trim(from: 0.06, to: 0.88)
                    .stroke(AngularGradient(colors: [.cyan, .indigo, .purple, .cyan], center: .center),
                            style: StrokeStyle(lineWidth: max(2, size * 0.035), lineCap: .round))
                    .padding(size * 0.045)
                Circle().fill(.cyan)
                    .overlay { Circle().strokeBorder(.black, lineWidth: 1) }
                    .frame(width: size * 0.14, height: size * 0.14)
                    .position(x: size * 0.85, y: size * 0.20)
                Circle().fill(.purple)
                    .frame(width: size * 0.09, height: size * 0.09)
                    .position(x: size * 0.16, y: size * 0.80)
            case .stardust:
                DockStardust(size: size, variant: variant, animated: animated)
            case .powerBadge:
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.19, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .background(.yellow, in: Circle())
                    .overlay { Circle().strokeBorder(.black, lineWidth: max(1, size * 0.025)) }
                    .position(x: size * 0.79, y: size * 0.20)
            default:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
    }
}

/// Four disconnected corners, with no crosshair over the application's artwork.
private struct DockTargetBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm = rect.width * 0.22
        for x in [rect.minX, rect.maxX] {
            for y in [rect.minY, rect.maxY] {
                let dx: CGFloat = x == rect.minX ? arm : -arm
                let dy: CGFloat = y == rect.minY ? arm : -arm
                path.move(to: CGPoint(x: x + dx, y: y))
                path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y + dy))
            }
        }
        return path
    }
}
