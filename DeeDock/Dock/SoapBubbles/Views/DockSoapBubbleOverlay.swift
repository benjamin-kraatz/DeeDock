import SwiftUI

/// Decorative soap-bubble bursts drawn over the dock canvas after a pin click or drop.
///
/// The overlay owns no timing: ``DockSoapBubbleController`` adds and removes bursts, and each
/// burst plays one finite SwiftUI animation that ends inside
/// ``DockSoapBubbleController/lifetime``. There is no timeline, no repeating animation, and no
/// per-frame state, so an idle dock never requests a frame.
///
/// Bursts are anchored to canvas-space icon frames — the same rects tooltips are placed in — so
/// the film stays on DDock chrome. A burst whose application no longer has a rendered frame is
/// skipped rather than given invented geometry.
///
/// Nothing here is interactive: the overlay takes no hits and is hidden from assistive
/// technologies. It draws nothing at all when the preference is off or Reduce Motion is on.
struct DockSoapBubbleOverlay: View {
    /// In-flight bursts, capped by ``DockSoapBubbleController/maximumConcurrentBursts``.
    let bursts: [DockSoapBubbleController.Burst]
    /// Canvas-space frames published once per layout turn, keyed by dock entry identity.
    let frames: [DockEntryID: CGRect]
    /// Saved preference. Reduce Motion suppresses playback independently.
    let enabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if enabled, !reduceMotion {
                ForEach(bursts) { burst in
                    if let frame = frames[.app(burst.itemID)] {
                        DockSoapBubbleBurstView(seed: DockSoapBubbleFilm.seed(for: burst.id),
                                                diameter: min(frame.width, frame.height))
                            // Identity is the burst, so a replayed pin starts a fresh film
                            // instead of retargeting the previous one mid-flight.
                            .id(burst.id)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One burst: a small cluster of translucent films that swell, drift outward, and pop.
///
/// The whole cluster is driven by a single `playing` flag flipped once on appear, so every
/// circle shares one implicit animation and the burst has no state left to settle when the
/// controller removes it.
private struct DockSoapBubbleBurstView: View {
    /// Deterministic layout seed derived from the burst identifier.
    let seed: UInt64
    /// Icon dimension in logical points; the film scales with the pin it came from.
    let diameter: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var playing = false

    private var films: [DockSoapBubbleFilm] { DockSoapBubbleFilm.cluster(seed: seed) }

    var body: some View {
        ZStack {
            ForEach(films) { film in
                DockSoapBubbleFilmView(film: film, diameter: diameter, playing: playing,
                                       reduceTransparency: reduceTransparency)
            }
        }
        .frame(width: diameter * 2.2, height: diameter * 2.2)
        .onAppear { playing = true }
    }
}

/// A single iridescent film. Kept separate so each one carries its own delay and easing
/// without the parent rebuilding a large `body`.
private struct DockSoapBubbleFilmView: View {
    let film: DockSoapBubbleFilm
    let diameter: CGFloat
    let playing: Bool
    let reduceTransparency: Bool

    /// Start and end poses. Interpolation between them is the entire animation: no keyframes
    /// are needed because a soap film only ever swells once and thins out.
    private var scale: CGFloat { playing ? film.endScale : film.startScale }
    private var opacity: Double { playing ? 0 : film.opacity }
    private var offset: CGSize {
        playing ? CGSize(width: film.drift.width * diameter, height: film.drift.height * diameter)
                : .zero
    }

    var body: some View {
        Circle()
            .strokeBorder(filmStyle, lineWidth: max(1, diameter * 0.05))
            .background {
                // The interior sheen is what reads as soap rather than a plain ring. It is the
                // only translucent layer, so Reduce Transparency simply drops it.
                if !reduceTransparency {
                    Circle().fill(.white.opacity(0.10)).blur(radius: diameter * 0.03)
                }
            }
            .frame(width: diameter * film.size, height: diameter * film.size)
            .scaleEffect(scale)
            .offset(offset)
            .opacity(opacity)
            .animation(.easeOut(duration: film.duration).delay(film.delay), value: playing)
    }

    private var filmStyle: AnyShapeStyle {
        guard !reduceTransparency else { return AnyShapeStyle(Color.white.opacity(0.7)) }
        return AnyShapeStyle(
            AngularGradient(colors: [.white.opacity(0.9), .cyan.opacity(0.75), .purple.opacity(0.7),
                                     .yellow.opacity(0.7), .white.opacity(0.9)],
                            center: .center, angle: .degrees(film.hueAngle))
        )
    }
}

/// Static description of one film in a burst cluster. Values are fractions of the icon
/// dimension so the same cluster works at every icon size.
private struct DockSoapBubbleFilm: Identifiable {
    let id: Int
    let size: CGFloat
    let startScale: CGFloat
    let endScale: CGFloat
    let drift: CGSize
    let opacity: Double
    let delay: Double
    let duration: Double
    let hueAngle: Double

    /// Six films: enough to read as a cluster, few enough to stay cheap at three concurrent bursts.
    private static let count = 6

    /// Builds a cluster whose spread is fixed but whose angles and sizes vary per burst, so two
    /// pins in a row do not produce visibly identical films.
    ///
    /// Every film finishes within ``DockSoapBubbleController/lifetime``: the latest delay plus
    /// its duration is held under that budget so the controller's removal never clips a film.
    static func cluster(seed: UInt64) -> [DockSoapBubbleFilm] {
        var generator = SplitMix64(seed: seed)
        let baseAngle = Double.random(in: 0..<(2 * .pi), using: &generator)
        return (0..<count).map { index in
            let spin = Double.random(in: -0.5...0.5, using: &generator)
            let angle = baseAngle + (Double(index) / Double(count)) * 2 * .pi + spin
            let reach = CGFloat.random(in: 0.28...0.55, using: &generator)
            let delay = Double.random(in: 0...0.10, using: &generator)
            // Reserve the delay out of the lifetime budget rather than adding to it.
            let duration = DockSoapBubbleController.lifetime - delay - 0.06
            return DockSoapBubbleFilm(
                id: index,
                size: CGFloat.random(in: 0.22...0.42, using: &generator),
                startScale: 0.35,
                endScale: CGFloat.random(in: 1.15...1.6, using: &generator),
                drift: CGSize(width: cos(angle) * reach, height: sin(angle) * reach),
                opacity: Double.random(in: 0.55...0.9, using: &generator),
                delay: delay,
                duration: max(0.2, duration),
                hueAngle: Double.random(in: 0..<360, using: &generator))
        }
    }

    /// Folds the burst UUID's bytes into a seed. `hashValue` is deliberately avoided: it is
    /// salted per process, which would make previews and screenshots non-reproducible.
    static func seed(for id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { bytes in
            bytes.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { hash, byte in
                (hash ^ UInt64(byte)) &* 0x100_0000_01b3
            }
        }
    }
}

/// Small deterministic generator so cluster geometry depends only on the burst identifier.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#if DEBUG
private enum DockSoapBubbleOverlayPreview {
    static let canvas = CGSize(width: 320, height: 120)

    static let frames: [DockEntryID: CGRect] = [
        .app("safari"): CGRect(x: 80, y: 60, width: 56, height: 56).offsetBy(dx: -28, dy: -28),
        .app("mail"): CGRect(x: 180, y: 60, width: 56, height: 56).offsetBy(dx: -28, dy: -28)
    ]

    static let bursts = [
        DockSoapBubbleController.Burst(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                                       itemID: "safari", startedAt: Date(timeIntervalSince1970: 1_700_000_000)),
        DockSoapBubbleController.Burst(id: UUID(uuidString: "66666666-7777-8888-9999-aaaaaaaaaaaa")!,
                                       itemID: "mail", startedAt: Date(timeIntervalSince1970: 1_700_000_000)),
        // No frame for this identity: the overlay must skip it.
        DockSoapBubbleController.Burst(id: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!,
                                       itemID: "missing", startedAt: Date(timeIntervalSince1970: 1_700_000_000))
    ]

    @ViewBuilder
    static func stage(enabled: Bool) -> some View {
        ZStack {
            ForEach(Array(frames.values), id: \.origin.x) { frame in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.indigo.gradient)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
            DockSoapBubbleOverlay(bursts: bursts, frames: frames, enabled: enabled)
        }
        .frame(width: canvas.width, height: canvas.height)
        .background(.black.opacity(0.85))
        .padding(24)
    }
}

#Preview("Bursts playing") {
    DockSoapBubbleOverlayPreview.stage(enabled: true)
}

#Preview("Disabled, empty") {
    DockSoapBubbleOverlayPreview.stage(enabled: false)
}

#Preview("Reduce Motion, empty") {
    DockSoapBubbleOverlayPreview.stage(enabled: true)
        .environment(\.accessibilityReduceMotion, true)
}

#Preview("Reduce Transparency") {
    DockSoapBubbleOverlayPreview.stage(enabled: true)
        .environment(\.accessibilityReduceTransparency, true)
}

#Preview("Light appearance") {
    DockSoapBubbleOverlayPreview.stage(enabled: true)
        .preferredColorScheme(.light)
}
#endif
