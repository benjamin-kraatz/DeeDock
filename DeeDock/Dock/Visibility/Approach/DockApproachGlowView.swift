import Observation
import SwiftUI

/// Live state of one display's approach glow. The controller writes it; the view only reads it.
@MainActor @Observable final class DockApproachGlowModel {
    var intensity: Double = 0
    /// Exponential boost for the last points before the zone (see ``DockApproachSample/surge``).
    var surge: Double = 0
    /// Canonical position along the edge (see ``DockApproachGeometry/zoneSpan``).
    var focus: CGFloat = 0
    var tone: DockApproachTone = .light
    var metrics = DockApproachGlowMetrics(edge: .bottom, length: 0, depth: 0, zoneSpan: 0...0)
    var reduceMotion = false
    var reduceTransparency = false
}

/// Band dimensions the glow is drawn into, independent of the pointer.
struct DockApproachGlowMetrics: Equatable {
    let edge: DockEdge
    let length: CGFloat
    let depth: CGFloat
    let zoneSpan: ClosedRange<CGFloat>

    init(edge: DockEdge, length: CGFloat, depth: CGFloat, zoneSpan: ClosedRange<CGFloat>) {
        self.edge = edge; self.length = length; self.depth = depth; self.zoneSpan = zoneSpan
    }

    init(_ geometry: DockApproachGeometry) {
        self.init(edge: geometry.edge, length: geometry.length, depth: geometry.depth, zoneSpan: geometry.zoneSpan)
    }
}

/// Hosts the glow inside the click-through panel.
struct DockApproachGlowView: View {
    let model: DockApproachGlowModel

    var body: some View {
        DockApproachGlow(intensity: model.intensity, surge: model.surge, focus: model.focus, tone: model.tone, metrics: model.metrics,
                         reduceMotion: model.reduceMotion, reduceTransparency: model.reduceTransparency)
            .accessibilityHidden(true)
    }
}

/// Light (or shadow) rising from the screen edge where a hidden dock will appear.
///
/// Drawn in canonical bottom-edge space, then mapped onto the real edge, so every edge shares one
/// look. `intensity`, `surge`, and `focus` are animatable: the controller retargets them on each
/// pointer move and SwiftUI interpolates between samples, which keeps the glow smooth at any event rate.
///
/// The surge multiplies the base glow on the final approach: brighter, taller, and wider, with a
/// hot core under the pointer. Nothing may exceed the band, whose size accounts for full surge.
struct DockApproachGlow: View, Animatable {
    var intensity: Double
    var surge: Double = 0
    var focus: CGFloat
    let tone: DockApproachTone
    let metrics: DockApproachGlowMetrics
    let reduceMotion: Bool
    let reduceTransparency: Bool

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, CGFloat> {
        get { AnimatablePair(AnimatablePair(intensity, surge), focus) }
        set { intensity = newValue.first.first; surge = newValue.first.second; focus = newValue.second }
    }

    var body: some View {
        Canvas { context, _ in
            let strength = min(1, max(0, intensity))
            guard strength > 0.001, metrics.length > 0, metrics.depth > 0 else { return }
            let boost = min(1, max(0, surge))
            context.concatenate(canonicalTransform)
            if reduceTransparency { drawSolidBar(in: &context, strength: strength, boost: boost) }
            else {
                drawWash(in: &context, strength: strength, boost: boost)
                drawCore(in: &context, boost: boost)
                drawEdgeLine(in: &context, strength: strength, boost: boost)
            }
        }
        .mask { endFade }
    }

    /// Fades the band's two ends. The band normally holds the whole glow, but near a screen corner
    /// it is clipped to the display, and the glow must still taper instead of stopping in a line.
    private var endFade: some View {
        let fade = min(0.5, 64 / max(metrics.length, 1))
        return LinearGradient(stops: [
            .init(color: .clear, location: 0), .init(color: .black, location: fade),
            .init(color: .black, location: 1 - fade), .init(color: .clear, location: 1)
        ], startPoint: metrics.edge.isVertical ? .top : .leading, endPoint: metrics.edge.isVertical ? .bottom : .trailing)
    }

    /// Maps canonical bottom-edge coordinates (x along the zone, y = depth at the screen edge) to the view.
    private var canonicalTransform: CGAffineTransform {
        let d = metrics.depth
        return switch metrics.edge {
        case .bottom: .identity
        case .top: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: d)
        case .left: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: d, ty: 0)
        case .right: CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        }
    }

    private var zoneLength: CGFloat { metrics.zoneSpan.upperBound - metrics.zoneSpan.lowerBound }

    /// Growth factor for size at the current surge. Reduce Motion keeps the size fixed.
    private func growth(_ boost: Double) -> CGFloat {
        reduceMotion ? 1 : 1 + DockApproachGeometry.surgeGrowth * boost
    }

    /// A soft ellipse anchored on the edge under the pointer. It rises with intensity and swells with
    /// the surge unless Reduce Motion is on, where only its opacity changes.
    private func drawWash(in context: inout GraphicsContext, strength: Double, boost: Double) {
        let peak = (tone.isShadow ? 0.42 : 0.55) * strength * (1 + 0.8 * boost)
        let base = min(DockApproachGeometry.washDepth, metrics.depth)
        let height = base * (reduceMotion ? 1 : 0.45 + 0.55 * strength) * growth(boost)
        let width = DockApproachGeometry.washHalfWidth(zoneLength: zoneLength) * growth(boost)
        // An eased falloff keeps the ellipse from showing a rim where a linear ramp would end.
        let gradient = Gradient(stops: [(0, 1), (0.25, 0.7), (0.45, 0.4), (0.7, 0.13), (0.88, 0.03), (1, 0)].map {
            Gradient.Stop(color: tone.color.opacity(min(1, peak * $0.1)), location: $0.0)
        })
        var layer = context
        layer.translateBy(x: focus, y: metrics.depth)
        layer.scaleBy(x: width / height, y: 1)
        layer.fill(Path(ellipseIn: CGRect(x: -height, y: -height, width: height * 2, height: height * 2)),
                   with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: height))
    }

    /// A tight, bright spot on the edge under the pointer that exists only during the surge.
    private func drawCore(in context: inout GraphicsContext, boost: Double) {
        guard boost > 0.001 else { return }
        let peak = (tone.isShadow ? 0.5 : 0.75) * boost
        let radius: CGFloat = reduceMotion ? 50 : 30 + 34 * boost
        let gradient = Gradient(stops: [(0, 1), (0.35, 0.5), (0.7, 0.12), (1, 0)].map {
            Gradient.Stop(color: tone.color.opacity(peak * $0.1), location: $0.0)
        })
        var layer = context
        layer.translateBy(x: focus, y: metrics.depth)
        layer.scaleBy(x: 2.2, y: 1)
        layer.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                   with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: radius))
    }

    /// A hairline along the zone that brightens faster than the wash, marking the exact trigger span.
    private func drawEdgeLine(in context: inout GraphicsContext, strength: Double, boost: Double) {
        let peak = min(1, (tone.isShadow ? 0.55 : 0.9) * strength * strength * (1 + 0.4 * boost))
        let thickness = 1.5 + 1.5 * strength + 1.5 * boost
        let rect = CGRect(x: metrics.zoneSpan.lowerBound, y: metrics.depth - thickness, width: zoneLength, height: thickness)
        guard rect.width > 0 else { return }
        let gradient = Gradient(stops: [
            .init(color: tone.color.opacity(0), location: 0),
            .init(color: tone.color.opacity(peak), location: 0.18),
            .init(color: tone.color.opacity(peak), location: 0.82),
            .init(color: tone.color.opacity(0), location: 1)
        ])
        context.fill(Path(rect), with: .linearGradient(gradient, startPoint: CGPoint(x: rect.minX, y: rect.midY),
                                                       endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
    }

    /// Reduce Transparency replaces the translucent wash with an opaque bar that thickens on approach.
    private func drawSolidBar(in context: inout GraphicsContext, strength: Double, boost: Double) {
        let thickness = 2 + 4 * strength + 2 * boost
        let rect = CGRect(x: metrics.zoneSpan.lowerBound, y: metrics.depth - thickness, width: zoneLength, height: thickness)
        guard rect.width > 0 else { return }
        context.fill(Path(roundedRect: rect, cornerRadius: thickness / 2),
                     with: .color(tone.color.opacity(0.35 + 0.65 * strength)))
    }
}

#if DEBUG
private struct DockApproachGlowPreview: View {
    let edge: DockEdge
    let intensity: Double
    var surge: Double = 0
    var tone: DockApproachTone = .light
    var reduceMotion = false
    var reduceTransparency = false
    var background: Color = .indigo

    var body: some View {
        let depth = DockApproachGeometry.washDepth * (1 + DockApproachGeometry.surgeGrowth)
        let metrics = DockApproachGlowMetrics(edge: edge, length: 640, depth: depth, zoneSpan: 220...420)
        let size = edge.size(length: metrics.length, depth: metrics.depth)
        DockApproachGlow(intensity: intensity, surge: surge, focus: 360, tone: tone, metrics: metrics,
                         reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
            .frame(width: size.width, height: size.height)
            .background(background)
    }
}

#Preview("Approach glow — bottom, rising") {
    VStack(spacing: 12) {
        ForEach([0.25, 0.6, 1.0], id: \.self) { DockApproachGlowPreview(edge: .bottom, intensity: $0) }
    }.padding()
}
#Preview("Approach glow — surge on the last points") {
    VStack(spacing: 12) {
        ForEach([0.14, 0.37, 1.0], id: \.self) { DockApproachGlowPreview(edge: .bottom, intensity: 1, surge: $0) }
    }.padding()
}
#Preview("Approach glow — shadow on light wallpaper") {
    DockApproachGlowPreview(edge: .bottom, intensity: 0.8, tone: .shadow, background: Color(white: 0.9)).padding()
}
#Preview("Approach glow — side and top edges, accent") {
    HStack(spacing: 12) {
        DockApproachGlowPreview(edge: .left, intensity: 0.8, tone: .accent)
        DockApproachGlowPreview(edge: .right, intensity: 0.8, tone: .accent)
        DockApproachGlowPreview(edge: .top, intensity: 0.8, tone: .accent)
    }.padding()
}
#Preview("Approach glow — reduced motion and transparency stubs") {
    VStack(spacing: 12) {
        DockApproachGlowPreview(edge: .bottom, intensity: 0.4, reduceMotion: true)
        DockApproachGlowPreview(edge: .bottom, intensity: 0.7, reduceTransparency: true)
    }.padding()
}
#endif
