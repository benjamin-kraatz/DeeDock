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

/// Visual rust: the icon loses chroma and picks up a rust hue, then oxide flakes and pits.
///
/// SwiftUI and Core Animation only — no Metal shaders, so the look ships without a shader
/// toolchain. Intensity `0` renders the artwork untouched. `0.32` is a clear first rust, and
/// `1` is heavily weathered while the icon still reads.
///
/// A color-blend wash is what makes rust visible on blue and teal artwork. Multiply alone
/// only darkened those icons. Reduce Motion shortens the cross-fade. Reduce Transparency
/// uses a heavier wash so the rust survives a solid backdrop.
struct PinWeatherLook: ViewModifier {
    /// Rust amount, clamped to `0...1`.
    var intensity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let amount = min(1, max(0, intensity))
        content
            .saturation(1 - 0.62 * amount)
            .hueRotation(.degrees(16 * amount))
            .brightness(-0.08 * amount)
            .contrast(1 - 0.05 * amount)
            .colorMultiply(PinWeatherOxide.tint(amount: amount))
            .overlay {
                if amount > 0 {
                    // Color blend shifts the artwork toward rust orange while keeping its
                    // luminance, so a blue pin turns rusty instead of merely dim.
                    PinWeatherOxide.rust
                        .opacity((reduceTransparency ? 0.42 : 0.30) + 0.38 * amount)
                        .blendMode(.color)
                        .mask { content }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    PinWeatherOxide(level: PinWeatherOxide.quantized(amount), solid: reduceTransparency)
                        .mask { content }
                        .opacity(0.55 + 0.45 * amount)
                        .blendMode(reduceTransparency ? .plusDarker : .multiply)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // Bounds the multiply to the artwork so it cannot darken the dock surface behind it.
            .compositingGroup()
            .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.45), value: amount)
    }
}

/// The oxide layer: an orange rust wash plus flakes and dark pits, drawn in one `Canvas`.
///
/// Alphas here describe fully weathered artwork; ``PinWeatherLook`` fades the whole layer with
/// `opacity` so the transition is animatable without redrawing the canvas on every frame.
private struct PinWeatherOxide: View {
    /// Weathering step, `0...1`, driving how many flakes appear and how wide they grow.
    let level: Double
    /// Reduce Transparency: a heavier, more opaque wash.
    let solid: Bool

    static let rust = Color(red: 0.72, green: 0.28, blue: 0.10)
    private static let flake = Color(red: 0.78, green: 0.38, blue: 0.12)
    private static let pit = Color(red: 0.32, green: 0.14, blue: 0.06)

    /// Coarse steps for the canvas so flake count and size change a handful of times across the
    /// whole ramp instead of on every intensity sample.
    static func quantized(_ amount: Double) -> Double {
        (amount * 6).rounded() / 6
    }

    /// Pulls RGB toward rust so even a light intensity reads as metal, not as a dimmer icon.
    static func tint(amount: Double) -> Color {
        Color(red: 1 - 0.08 * amount, green: 1 - 0.38 * amount, blue: 1 - 0.52 * amount)
    }

    private var washOpacity: Double { solid ? 0.46 : 0.32 }
    private var rimOpacity: Double { solid ? 0.40 : 0.28 }
    private var flakeOpacity: Double { solid ? 0.70 : 0.56 }
    private var pitOpacity: Double { solid ? 0.64 : 0.50 }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let unit = min(size.width, size.height)

            // Age settles downward, so the wash is lightest at the top edge.
            context.fill(Path(bounds), with: .linearGradient(
                Gradient(stops: [
                    .init(color: Self.rust.opacity(washOpacity * 0.25), location: 0),
                    .init(color: Self.rust.opacity(washOpacity * 0.70), location: 0.48),
                    .init(color: Self.rust.opacity(washOpacity), location: 1)
                ]),
                startPoint: CGPoint(x: size.width * 0.28, y: 0),
                endPoint: CGPoint(x: size.width * 0.72, y: size.height)))

            // Rim bloom: clearer in the middle so the glyph stays readable, rust at the
            // edges where a finish gives out first.
            context.fill(Path(bounds), with: .radialGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Self.rust.opacity(rimOpacity * 0.35), location: 0.62),
                    .init(color: Self.rust.opacity(rimOpacity), location: 1)
                ]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.44),
                startRadius: unit * 0.12,
                endRadius: unit * 0.74))

            let visible = Int((Double(PinWeatherSpeckle.field.count) * max(0.35, level)).rounded())
            guard visible > 0 else { return }
            context.drawLayer { layer in
                // A short blur keeps flakes as corrosion, not as hard dots, without wiping
                // their rust color into a brown fog.
                layer.addFilter(.blur(radius: unit * 0.010))
                for speckle in PinWeatherSpeckle.field.prefix(visible) {
                    let diameter = speckle.radius * unit * (0.7 + 0.5 * level)
                    let rect = CGRect(x: speckle.position.x * size.width - diameter / 2,
                                      y: speckle.position.y * size.height - diameter / 2,
                                      width: diameter * speckle.stretch,
                                      height: diameter)
                    let color = speckle.flake ? Self.flake : Self.pit
                    let alpha = (speckle.flake ? flakeOpacity : pitOpacity) * speckle.weight
                    layer.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                }
            }
        }
    }
}

/// One flake or pit in the oxide field, in unit artwork space so the look scales with icon size.
private struct PinWeatherSpeckle {
    /// Center, `0...1` on each axis of the artwork box.
    let position: CGPoint
    /// Diameter as a fraction of the artwork's shorter edge.
    let radius: Double
    /// Horizontal stretch; values above 1 read as a rust streak.
    let stretch: Double
    /// Per-mark opacity multiplier, so the field is not uniformly dark.
    let weight: Double
    /// Orange flake when true; darker pit when false.
    let flake: Bool

    /// A fixed field, generated once from a constant seed.
    ///
    /// Every redraw and every pin at the same level must produce identical marks; drawing fresh
    /// random positions would make icons crawl on each canvas invalidation.
    static let field: [PinWeatherSpeckle] = {
        var state: UInt64 = 0x5DEE_D0C_C0FF_EE01
        func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state >> 11) * 0x1p-53
        }
        return (0..<40).map { index in
            let x = next()
            let y = next()
            return PinWeatherSpeckle(
                // Bias downward: weathering pools along the lower half of a surface.
                position: CGPoint(x: 0.05 + 0.90 * x, y: 0.08 + 0.88 * pow(y, 0.55)),
                radius: 0.04 + 0.13 * next(),
                stretch: index.isMultiple(of: 3) ? 1.6 + 0.8 * next() : 1,
                weight: 0.50 + 0.50 * next(),
                flake: index.isMultiple(of: 2))
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
}

#Preview("Reduce Transparency") {
    PinWeatherPreviewIcon().modifier(PinWeatherLook(intensity: 0.8))
        .padding(24)
}

/// Stand-in artwork for previews: no workspace lookup, no launching, no preferences.
struct PinWeatherPreviewIcon: View {
    var size: CGFloat = 64

    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [
                Color(red: 0.22, green: 0.62, blue: 0.92),
                Color(red: 0.10, green: 0.36, blue: 0.78)
            ], startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
    }
}
#endif
