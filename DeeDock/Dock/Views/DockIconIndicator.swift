import SwiftUI

/// Static running-state artwork inside the icon square. It never changes layout or hit regions.
/// Apply before keyboard focus and launch overlays so those interaction states stay on top.
struct DockIconIndicator: ViewModifier {
    let style: DockSettings.RunningIndicatorStyle
    let running: Bool
    let size: CGFloat
    /// Inert preview override; live icons follow the system preference.
    var reduceTransparency: Bool? = nil
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if running {
                    DockIndicatorBackdrop(style: style, size: size,
                        opaque: reduceTransparency ?? systemReduceTransparency)
                        .accessibilityHidden(true).allowsHitTesting(false)
                }
            }
            .overlay {
                if running {
                    DockIndicatorForeground(style: style, size: size,
                        opaque: reduceTransparency ?? systemReduceTransparency)
                        .accessibilityHidden(true).allowsHitTesting(false)
                }
            }
    }
}

/// Backlighting and offset silhouettes stay behind the application artwork.
private struct DockIndicatorBackdrop: View {
    let style: DockSettings.RunningIndicatorStyle
    let size: CGFloat
    let opaque: Bool

    var body: some View {
        ZStack {
            switch style {
            case .neon:
                RoundedRectangle(cornerRadius: size * 0.22)
                    .strokeBorder(.cyan, lineWidth: size * 0.12)
                    .blur(radius: opaque ? 0 : size * 0.06)
            case .aura:
                RoundedRectangle(cornerRadius: size * 0.28)
                    .fill(AngularGradient(colors: [.pink, .orange, .yellow, .pink], center: .center))
                    .blur(radius: opaque ? 0 : size * 0.07)
            case .glitch:
                RoundedRectangle(cornerRadius: size * 0.18)
                    .fill(.cyan).padding(size * 0.08).offset(x: -size * 0.07, y: size * 0.025)
                RoundedRectangle(cornerRadius: size * 0.18)
                    .fill(.pink).padding(size * 0.08).offset(x: size * 0.07, y: -size * 0.025)
            default:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
        // Even blurred artwork must stay inside its own icon when item spacing is zero.
        .clipped()
    }
}

/// Frames and corner ornaments leave the center of each app icon recognizable.
private struct DockIndicatorForeground: View {
    let style: DockSettings.RunningIndicatorStyle
    let size: CGFloat
    let opaque: Bool

    var body: some View {
        ZStack {
            switch style {
            case .plasma, .hologram, .solarFlare, .prism:
                DockShaderIndicator(style: style, size: size, opaque: opaque)
            case .neon:
                RoundedRectangle(cornerRadius: size * 0.20)
                    .strokeBorder(LinearGradient(colors: [.cyan, .blue, .pink],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: max(2, size * 0.045))
                    .padding(size * 0.055)
            case .aura:
                RoundedRectangle(cornerRadius: size * 0.25)
                    .strokeBorder(.orange, lineWidth: max(1.5, size * 0.025))
                    .padding(size * 0.025)
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
                star(at: CGPoint(x: 0.18, y: 0.18), scale: 0.27, color: .yellow)
                star(at: CGPoint(x: 0.86, y: 0.48), scale: 0.20, color: .pink)
                star(at: CGPoint(x: 0.30, y: 0.87), scale: 0.16, color: .cyan)
            case .powerBadge:
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.19, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .background(.yellow, in: Circle())
                    .overlay { Circle().strokeBorder(.black, lineWidth: max(1, size * 0.025)) }
                    .position(x: size * 0.79, y: size * 0.20)
            case .glitch:
                Rectangle().fill(.cyan)
                    .frame(width: size * 0.40, height: max(2, size * 0.05))
                    .position(x: size * 0.28, y: size * 0.10)
                Rectangle().fill(.pink)
                    .frame(width: size * 0.34, height: max(2, size * 0.05))
                    .position(x: size * 0.74, y: size * 0.86)
                Rectangle().fill(.cyan)
                    .frame(width: size * 0.12, height: size * 0.16)
                    .position(x: size * 0.11, y: size * 0.64)
            default:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
    }

    private func star(at point: CGPoint, scale: CGFloat, color: Color) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * scale, weight: .bold))
            .foregroundStyle(color)
            .shadow(color: .black, radius: 0, y: 1)
            .position(x: size * point.x, y: size * point.y)
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
