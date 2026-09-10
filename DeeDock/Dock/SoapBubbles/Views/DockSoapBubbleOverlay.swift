import SwiftUI

/// Decorative soap-bubble pops drawn over the dock canvas after an app click, pin, or drop.
///
/// The overlay owns no timing: ``DockSoapBubbleController`` adds and removes bursts, and each
/// burst plays one finite keyframe animation that ends inside
/// ``DockSoapBubbleController/lifetime``. There is no timeline, no repeating animation, and no
/// per-frame state, so an idle dock never requests a frame.
///
/// Each burst is a two-stage gesture rather than a fade: an iridescent film swells on the icon,
/// snaps open, and throws a handful of droplets outward. The stages are separate views so the
/// film's short life is not stretched to cover the droplets' travel.
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
                        DockSoapBubbleBurstView(seed: DockSoapBubblePop.seed(for: burst.id),
                                                diameter: min(frame.width, frame.height))
                            // Identity is the burst, so a replayed pin starts a fresh pop
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

/// One burst: a film that swells and bursts, plus the droplets it throws.
///
/// Both stages are triggered by a single `playing` flag flipped once on appear, so the burst
/// has no state left to settle when the controller removes it.
private struct DockSoapBubbleBurstView: View {
    /// Deterministic layout seed derived from the burst identifier.
    let seed: UInt64
    /// Icon dimension in logical points; the pop scales with the pin it came from.
    let diameter: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var playing = false

    var body: some View {
        let pop = DockSoapBubblePop(seed: seed)
        ZStack {
            DockSoapBubbleFilmView(hueAngle: pop.hueAngle, diameter: diameter, playing: playing,
                                   reduceTransparency: reduceTransparency)
            ForEach(pop.droplets) { droplet in
                DockSoapBubbleDropletView(droplet: droplet, diameter: diameter, playing: playing,
                                          hueAngle: pop.hueAngle, reduceTransparency: reduceTransparency)
            }
        }
        // The droplets reach roughly 0.6 of an icon from the centre; the box leaves room for
        // that without clipping, and takes no hits either way.
        .frame(width: diameter * 2.4, height: diameter * 2.4)
        .onAppear { playing = true }
    }
}

/// The film itself: swell, then burst.
///
/// A single keyframe pass drives both stages because the pop is the *shape* of the curve, not a
/// second animation: scale eases up to full size, then jumps past it while opacity is cut over a
/// couple of frames. An `easeOut` on scale and opacity together is what reads as a fade.
private struct DockSoapBubbleFilmView: View {
    let hueAngle: Double
    let diameter: CGFloat
    let playing: Bool
    let reduceTransparency: Bool

    var body: some View {
        KeyframeAnimator(initialValue: Pose(), trigger: playing) { pose in
            Circle()
                .strokeBorder(filmStyle, lineWidth: max(1, diameter * 0.05 * pose.rim))
                .background {
                    // The interior sheen is what reads as soap rather than a plain ring. It is
                    // the only translucent layer, so Reduce Transparency simply drops it.
                    if !reduceTransparency {
                        Circle().fill(.white.opacity(0.12)).blur(radius: diameter * 0.03)
                    }
                }
                .frame(width: diameter * 0.52, height: diameter * 0.52)
                .scaleEffect(pose.scale)
                .opacity(playing ? pose.opacity : 0)
        } keyframes: { _ in
            // 0…0.20s swell, 0.20…0.28s burst. The film is gone well before the controller's
            // 0.55s lifetime, leaving the tail to the droplets.
            KeyframeTrack(\.scale) {
                SpringKeyframe(1, duration: 0.20, spring: .bouncy(duration: 0.20, extraBounce: 0.2))
                CubicKeyframe(1.62, duration: 0.08)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(0.95, duration: 0.07)
                LinearKeyframe(1, duration: 0.13)
                // The snap: the rim is still growing while it disappears, so the eye reads a
                // burst rather than something shrinking away.
                LinearKeyframe(0, duration: 0.07)
            }
            // The rim thins as the film stretches, the way a real bubble does just before it goes.
            KeyframeTrack(\.rim) {
                LinearKeyframe(1, duration: 0.20)
                LinearKeyframe(0.35, duration: 0.08)
            }
        }
    }

    /// Animated film pose. Scale and opacity are tracked separately so the opacity cut can be
    /// much shorter than the scale ramp.
    private struct Pose {
        var scale: CGFloat = 0.42
        var opacity: Double = 0
        var rim: CGFloat = 0.7
    }

    private var filmStyle: AnyShapeStyle {
        guard !reduceTransparency else { return AnyShapeStyle(Color.white.opacity(0.8)) }
        return AnyShapeStyle(
            AngularGradient(colors: [.white.opacity(0.95), .cyan.opacity(0.8), .purple.opacity(0.75),
                                     .yellow.opacity(0.75), .white.opacity(0.95)],
                            center: .center, angle: .degrees(hueAngle))
        )
    }
}

/// One droplet thrown by the burst: it waits for the film to go, flies out, and vanishes.
private struct DockSoapBubbleDropletView: View {
    let droplet: DockSoapBubblePop.Droplet
    let diameter: CGFloat
    let playing: Bool
    let hueAngle: Double
    let reduceTransparency: Bool

    private var size: CGFloat { max(1.5, diameter * droplet.size) }

    var body: some View {
        KeyframeAnimator(initialValue: Pose(), trigger: playing) { pose in
            Circle()
                .strokeBorder(dropletStyle, lineWidth: max(1, size * 0.28))
                .frame(width: size, height: size)
                // Travel is a fraction of the icon dimension along a fixed angle, so the spray
                // keeps its shape at every icon size.
                .offset(x: cos(droplet.angle) * droplet.reach * diameter * pose.travel,
                        y: sin(droplet.angle) * droplet.reach * diameter * pose.travel)
                .scaleEffect(pose.scale)
                .opacity(playing ? pose.opacity : 0)
        } keyframes: { _ in
            // Held at the centre until the film bursts, then one decelerating throw. The last
            // droplet finishes at 0.24 + 0.28 = 0.52s, inside the 0.55s lifetime.
            KeyframeTrack(\.travel) {
                LinearKeyframe(0, duration: droplet.delay)
                CubicKeyframe(1, duration: droplet.flight, startVelocity: 6, endVelocity: 0)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(0, duration: droplet.delay)
                LinearKeyframe(droplet.opacity, duration: 0.03)
                LinearKeyframe(droplet.opacity * 0.7, duration: droplet.flight * 0.5)
                LinearKeyframe(0, duration: droplet.flight * 0.5 - 0.03)
            }
            KeyframeTrack(\.scale) {
                LinearKeyframe(1, duration: droplet.delay)
                CubicKeyframe(0.45, duration: droplet.flight)
            }
        }
    }

    /// Animated droplet pose. `travel` is 0…1 along the droplet's fixed angle.
    private struct Pose {
        var travel: CGFloat = 0
        var opacity: Double = 0
        var scale: CGFloat = 0.8
    }

    private var dropletStyle: AnyShapeStyle {
        guard !reduceTransparency else { return AnyShapeStyle(Color.white.opacity(0.85)) }
        return AnyShapeStyle(
            AngularGradient(colors: [.white, .cyan.opacity(0.85), .white.opacity(0.9)],
                            center: .center, angle: .degrees(hueAngle + droplet.angle * 57.29))
        )
    }
}

/// Static description of one burst. Sizes and distances are fractions of the icon dimension so
/// the same pop works at every icon size.
private struct DockSoapBubblePop {
    /// A ring shard flung out of the film.
    struct Droplet: Identifiable {
        let id: Int
        /// Direction in radians, measured in the view's y-down space.
        let angle: Double
        /// Travel distance as a fraction of the icon dimension.
        let reach: CGFloat
        /// Diameter as a fraction of the icon dimension.
        let size: CGFloat
        let opacity: Double
        /// Wait before launch, covering the film's swell and snap.
        let delay: Double
        /// Outward travel time. `delay + flight` stays under the controller's lifetime.
        let flight: Double
    }

    /// Rotation of the iridescent gradient, so two pins in a row do not look identical.
    let hueAngle: Double
    let droplets: [Droplet]

    /// Builds a burst whose spread is fixed but whose angles, sizes, and count vary per burst.
    ///
    /// Every droplet finishes within ``DockSoapBubbleController/lifetime``: the launch delay is
    /// reserved out of the budget rather than added to it, so the controller's removal never
    /// clips a droplet mid-flight.
    init(seed: UInt64) {
        var generator = SplitMix64(seed: seed)
        hueAngle = Double.random(in: 0..<360, using: &generator)
        let count = Int.random(in: 3...6, using: &generator)
        let baseAngle = Double.random(in: 0..<(2 * .pi), using: &generator)
        droplets = (0..<count).map { index in
            let spin = Double.random(in: -0.4...0.4, using: &generator)
            let delay = Double.random(in: 0.20...0.24, using: &generator)
            let flight = min(0.28, DockSoapBubbleController.lifetime - delay - 0.03)
            return Droplet(
                id: index,
                angle: baseAngle + (Double(index) / Double(count)) * 2 * .pi + spin,
                reach: CGFloat.random(in: 0.38...0.62, using: &generator),
                size: CGFloat.random(in: 0.09...0.17, using: &generator),
                opacity: Double.random(in: 0.7...0.95, using: &generator),
                delay: delay,
                flight: flight)
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

/// Small deterministic generator so burst geometry depends only on the burst identifier.
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

#Preview("Pop playing") {
    DockSoapBubbleOverlayPreview.stage(enabled: true)
}

#Preview("Disabled, empty") {
    DockSoapBubbleOverlayPreview.stage(enabled: false)
}

#Preview("Reduce Motion, empty") {
    DockSoapBubbleOverlayPreview.stage(enabled: true)
}

#Preview("Reduce Transparency") {
    DockSoapBubbleOverlayPreview.stage(enabled: true)
}

#Preview("Light appearance") {
    DockSoapBubbleOverlayPreview.stage(enabled: true)
        .preferredColorScheme(.light)
}
#endif
