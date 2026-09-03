import SwiftUI

extension DockSettings.RunningIndicatorStyle {
    /// Styles drawn by the icon-sampling Metal shaders rather than by SwiftUI shapes.
    /// These are the only styles that read the artwork itself.
    var usesIconAura: Bool {
        switch self {
        case .plasma, .hologram, .solarFlare, .prism, .lavaChrome, .singularity, .glitch: true
        default: false
        }
    }

    /// Whether this style has any motion to switch off. Stardust twinkles without being a
    /// shader, so the preference covers more than `usesIconAura`.
    var animates: Bool { usesIconAura || self == .stardust }
}

/// Procedural Metal light around one icon, derived from that icon's own pixels.
///
/// This is a *layer* effect rather than a colour effect: the shader samples the artwork it
/// decorates, so the light follows the icon's real alpha silhouette and takes its colour
/// from the artwork nearest each lit pixel. The artwork is returned unmodified, which keeps
/// the icon itself crisp — only the transparent margin around it and a narrow rim just
/// inside its edge are painted.
///
/// The effect never changes layout or hit regions, and stays inside its own icon square so
/// zero item spacing cannot let one icon's light touch its neighbour.
struct DockIconAura: ViewModifier {
    let style: DockSettings.RunningIndicatorStyle
    /// The icon's current dimension in logical points, including magnification.
    let size: CGFloat
    /// Reduce Transparency: solid bands instead of layered light.
    let opaque: Bool
    let variant: DockIndicatorVariant
    /// Whether motion is permitted right now. Callers clear it for hidden and idle-faded
    /// docks so a dock nobody is looking at schedules no frames.
    let animated: Bool

    /// Seconds in one full animation cycle.
    ///
    /// Elapsed time is wrapped to this period before it reaches the shader, because a
    /// 32-bit float cannot hold an absolute timestamp at animation precision. Every
    /// time-dependent term in the shaders is an integer harmonic of the period, so the
    /// wrap is exactly seamless rather than a jump once a minute.
    private static let period: Double = 60
    /// Frames per second while animating. The light is diffuse and slow; a display-linked
    /// rate would cost several times as much for no visible gain.
    private static let frameRate: Double = 30

    /// How far the shaders sample for artwork, in points. Passed to every style so the
    /// silhouette band scales with the icon rather than with the display.
    private var reach: CGFloat { max(3, size * 0.16) }
    /// An upper bound on every offset any style takes, which is larger than `reach`: Glitch
    /// adds a row slip and a channel split on top of it. SwiftUI clips samples beyond this.
    private var bounds: CGSize { CGSize(width: size * 0.24, height: size * 0.24) }

    func body(content: Content) -> some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / Self.frameRate, paused: false)) { context in
                lit(content, at: context.date)
            }
        } else {
            lit(content, at: nil)
        }
    }

    private func lit(_ content: Content, at date: Date?) -> some View {
        content
            .layerEffect(shader(turn: turn(at: date)), maxSampleOffset: bounds)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    /// The cycle position in radians; zero whenever the aura is still.
    private func turn(at date: Date?) -> Double {
        guard let date else { return 0 }
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period)
        return elapsed / Self.period * 2 * .pi
    }

    private func shader(turn: Double) -> Shader {
        let arguments: [Shader.Argument] = [
            .float(size), .float(reach), .float(turn), .float(variant.seed),
            .float(opaque ? 1 : 0),
            .color(variant.accent ?? .black), .float(variant.accent == nil ? 0 : 1),
        ]
        let function: ShaderFunction = switch style {
        case .hologram: ShaderLibrary.deeDockHologram
        case .solarFlare: ShaderLibrary.deeDockSolarFlare
        case .prism: ShaderLibrary.deeDockPrism
        case .lavaChrome: ShaderLibrary.deeDockLavaChrome
        case .singularity: ShaderLibrary.deeDockSingularity
        case .glitch: ShaderLibrary.deeDockGlitch
        default: ShaderLibrary.deeDockPlasma
        }
        return Shader(function: function, arguments: arguments)
    }
}

#if DEBUG
/// Distinct artwork, so the previews show what the shaders actually read.
private struct AuraSample: View {
    let symbol: String
    let tint: Color
    let size: CGFloat
    let style: DockSettings.RunningIndicatorStyle
    var animated = true
    var opaque = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2)
            .fill(tint.gradient)
            .overlay { Image(systemName: symbol).font(.system(size: size * 0.4)).foregroundStyle(.white) }
            // Application icons carry their own transparent margin; samples need one drawn.
            .padding(size * 0.1)
            .frame(width: size, height: size)
            .modifier(DockIconAura(style: style, size: size, opaque: opaque,
                                   variant: DockIndicatorVariant(identity: symbol, accent: tint),
                                   animated: animated))
    }
}

private let auraApps: [(String, Color)] = [
    ("safari", .blue), ("message.fill", .green), ("flame.fill", .orange),
    ("gearshape.fill", .gray), ("bolt.fill", .purple), ("leaf.fill", .mint),
]

#Preview("Every style, six apps") {
    VStack(alignment: .leading, spacing: 18) {
        ForEach([DockSettings.RunningIndicatorStyle.plasma, .hologram, .solarFlare, .prism,
                 .lavaChrome, .singularity, .glitch], id: \.self) { style in
            HStack(spacing: 10) {
                ForEach(auraApps, id: \.0) { symbol, tint in
                    AuraSample(symbol: symbol, tint: tint, size: 64, style: style)
                }
            }
        }
    }
    .padding(24).background(.black)
}

#Preview("Sizes, still, and Reduce Transparency") {
    VStack(spacing: 18) {
        ForEach([CGFloat(32), 48, 96], id: \.self) { size in
            HStack(spacing: 14) {
                ForEach([DockSettings.RunningIndicatorStyle.plasma, .hologram, .solarFlare, .prism,
                         .lavaChrome, .singularity, .glitch], id: \.self) { style in
                    AuraSample(symbol: "safari", tint: .blue, size: size, style: style, animated: false)
                    AuraSample(symbol: "safari", tint: .blue, size: size, style: style, animated: false, opaque: true)
                }
            }
        }
    }
    .padding(24).background(.black)
}
#endif
