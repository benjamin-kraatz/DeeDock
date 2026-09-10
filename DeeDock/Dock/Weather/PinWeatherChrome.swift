import Foundation
import SwiftUI

/// Artwork-only rust. Indicators, badges, and the hit region stay clean.
///
/// Intensity is sampled on an hourly timeline so rust can appear after N unused days without a
/// polling loop in the coordinator. A pin with weather switched off skips the timeline entirely,
/// so a disabled feature costs nothing per tile.
struct PinWeatherChrome: ViewModifier {
    var sample: PinWeatherSample?

    func body(content: Content) -> some View {
        if let sample, sample.enabled {
            TimelineView(.periodic(from: .now, by: PinWeatherLimits.secondsPerDay / 24)) { context in
                content.modifier(PinWeatherLook(intensity: sample.intensity(at: context.date)))
            }
        } else {
            content
        }
    }
}

/// Visual rust: a desaturated, slightly darkened icon under a warm oxide wash and soft speckles.
///
/// SwiftUI and Core Animation only — no Metal shaders, so the look ships without a shader
/// toolchain. Intensity `0` renders the artwork untouched, `0.32` is the first visible blush, and
/// `1` reads as clearly unused while still reading as the app's icon.
///
/// Reduce Motion keeps the shorter cross-fade rust needs to appear and disappear but adds no loop
/// or shimmer. Reduce Transparency thickens the oxide so the weathering survives a solid backdrop.
struct PinWeatherLook: ViewModifier {
    /// Rust amount, clamped to `0...1`.
    var intensity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let amount = min(1, max(0, intensity))
        content
            .saturation(1 - 0.44 * amount)
            .brightness(-0.05 * amount)
            .contrast(1 - 0.08 * amount)
            .overlay {
                if amount > 0 {
                    // The oxide is masked by the artwork's own alpha. A multiply wash drawn across
                    // the tile would otherwise paint a brown square over the transparent margin
                    // every macOS icon carries, and would square off vector artwork like the
                    // Session Capsule mark.
                    PinWeatherOxide(level: PinWeatherOxide.quantized(amount), solid: reduceTransparency)
                        .mask { content }
                        .opacity(amount)
                        .blendMode(.multiply)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // Bounds the multiply to the artwork so it cannot darken the dock surface behind it.
            .compositingGroup()
            .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.45), value: amount)
    }
}

/// The oxide layer: an uneven warm wash plus a field of soft pits, drawn in one `Canvas`.
///
/// Alphas here describe fully weathered artwork; ``PinWeatherLook`` fades the whole layer with
/// `opacity` so the transition is animatable without redrawing the canvas on every frame.
private struct PinWeatherOxide: View {
    /// Weathering step, `0...1`, driving how many pits appear and how wide they grow.
    let level: Double
    /// Reduce Transparency: a heavier, more opaque wash.
    let solid: Bool

    /// Coarse steps for the canvas so pit count and size change a handful of times across the
    /// whole ramp instead of on every intensity sample.
    static func quantized(_ amount: Double) -> Double {
        (amount * 6).rounded() / 6
    }

    private var oxide: Color { Color(red: 0.55, green: 0.32, blue: 0.17) }
    private var pit: Color { Color(red: 0.36, green: 0.18, blue: 0.08) }
    private var washOpacity: Double { solid ? 0.34 : 0.20 }
    private var rimOpacity: Double { solid ? 0.30 : 0.18 }
    private var pitOpacity: Double { solid ? 0.52 : 0.38 }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let unit = min(size.width, size.height)

            // Age settles downward, so the wash is lightest at the top edge.
            context.fill(Path(bounds), with: .linearGradient(
                Gradient(stops: [
                    .init(color: oxide.opacity(washOpacity * 0.35), location: 0),
                    .init(color: oxide.opacity(washOpacity * 0.75), location: 0.55),
                    .init(color: oxide.opacity(washOpacity), location: 1)
                ]),
                startPoint: CGPoint(x: size.width * 0.35, y: 0),
                endPoint: CGPoint(x: size.width * 0.65, y: size.height)))

            // Rim bloom: clear at the middle so the icon's subject stays legible, oxide at the
            // edges where a real finish gives out first. Transparent stops leave the multiply
            // blend as a no-op, so the center is genuinely untouched.
            context.fill(Path(bounds), with: .radialGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: oxide.opacity(rimOpacity * 0.3), location: 0.7),
                    .init(color: oxide.opacity(rimOpacity), location: 1)
                ]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.46),
                startRadius: unit * 0.16,
                endRadius: unit * 0.72))

            let visible = Int((Double(PinWeatherSpeckle.field.count) * level).rounded())
            guard visible > 0 else { return }
            context.drawLayer { layer in
                // One blur for the whole field: pits read as corrosion rather than as dots, and
                // the filter is installed once instead of per pit.
                layer.addFilter(.blur(radius: unit * 0.014))
                for speckle in PinWeatherSpeckle.field.prefix(visible) {
                    let diameter = speckle.radius * unit * (0.6 + 0.4 * level)
                    let rect = CGRect(x: speckle.position.x * size.width - diameter / 2,
                                      y: speckle.position.y * size.height - diameter / 2,
                                      width: diameter, height: diameter)
                    layer.fill(Path(ellipseIn: rect),
                               with: .color(pit.opacity(pitOpacity * speckle.weight)))
                }
            }
        }
    }
}

/// One pit in the oxide field, in unit artwork space so the look scales with dock icon size.
private struct PinWeatherSpeckle {
    /// Center, `0...1` on each axis of the artwork box.
    let position: CGPoint
    /// Diameter as a fraction of the artwork's shorter edge.
    let radius: Double
    /// Per-pit opacity multiplier, so the field is not uniformly dark.
    let weight: Double

    /// A fixed field, generated once from a constant seed.
    ///
    /// Every redraw and every pin at the same level must produce identical pits; drawing fresh
    /// random positions would make icons crawl on each canvas invalidation.
    static let field: [PinWeatherSpeckle] = {
        var state: UInt64 = 0x5DEE_D0C_C0FF_EE01
        func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state >> 11) * 0x1p-53
        }
        return (0..<26).map { _ in
            let x = next()
            let y = next()
            return PinWeatherSpeckle(
                // Bias downward: weathering pools along the lower half of a surface.
                position: CGPoint(x: 0.06 + 0.88 * x, y: 0.10 + 0.86 * pow(y, 0.6)),
                radius: 0.05 + 0.11 * next(),
                weight: 0.45 + 0.55 * next())
        }
    }()
}

#if DEBUG
#Preview("Clean, light rust, heavy rust") {
    HStack(spacing: 24) {
        PinWeatherPreviewIcon().modifier(PinWeatherLook(intensity: 0))
        PinWeatherPreviewIcon().modifier(PinWeatherLook(intensity: 0.32))
        PinWeatherPreviewIcon().modifier(PinWeatherLook(intensity: 1))
    }
    .padding(24)
}

#Preview("Heavy rust, dark") {
    HStack(spacing: 24) {
        PinWeatherPreviewIcon().modifier(PinWeatherLook(intensity: 0.6))
        PinWeatherPreviewIcon().modifier(PinWeatherLook(intensity: 1))
    }
    .padding(24)
    .preferredColorScheme(.dark)
}

#Preview("Reduce Motion") {
    PinWeatherPreviewIcon().modifier(PinWeatherLook(intensity: 0.8))
        .padding(24)
        .environment(\.accessibilityReduceMotion, true)
}

#Preview("Reduce Transparency") {
    PinWeatherPreviewIcon().modifier(PinWeatherLook(intensity: 0.8))
        .padding(24)
        .environment(\.accessibilityReduceTransparency, true)
}

/// Stand-in artwork for previews: no workspace lookup, no launching, no preferences.
struct PinWeatherPreviewIcon: View {
    var size: CGFloat = 64

    var body: some View {
        Rectangle()
            .fill(Color.blue.gradient)
            .overlay {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
    }
}
#endif
