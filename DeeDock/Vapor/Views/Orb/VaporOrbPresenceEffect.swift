import SwiftUI

/// The orb's entrance and exit, played from ``VaporController/orbPresence``.
///
/// Turned on, the orb grows from 15 % with a spring that overshoots a little while it fades in,
/// as particles gather into it (``VaporOrbCondense``). Turned off, it swells slightly, then
/// shrinks and fades. Under Reduce Motion both are a plain fade. A presence without a token
/// (launch) shows the orb as it is.
///
/// The coordinator keeps the orb's window for ``VaporMotion/orbExitDuration(reduceMotion:)``
/// after turning Vapor off, so the exit has time to play.
struct VaporOrbPresenceEffect: ViewModifier {
    let presence: VaporOrbPresence
    let reduceMotion: Bool

    @State private var scale: CGFloat
    @State private var opacity: Double
    @State private var shrink: Task<Void, Never>?

    static let hiddenScale: CGFloat = 0.15

    init(presence: VaporOrbPresence, reduceMotion: Bool) {
        self.presence = presence
        self.reduceMotion = reduceMotion
        // An orb that is about to condense starts out hidden, so its first frame doesn't flash.
        _scale = State(initialValue: presence.isEntering && !reduceMotion ? Self.hiddenScale : 1)
        _opacity = State(initialValue: presence.isEntering ? 0 : 1)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onChange(of: presence, initial: true) { _, presence in play(presence) }
            .onDisappear { shrink?.cancel() }
    }

    private func play(_ presence: VaporOrbPresence) {
        shrink?.cancel()
        shrink = nil
        guard presence.token != nil else {
            scale = 1
            opacity = presence.isShown ? 1 : 0
            return
        }
        if reduceMotion {
            scale = 1
            withAnimation(.easeOut(duration: VaporMotion.orbFade)) { opacity = presence.isShown ? 1 : 0 }
        } else if presence.isShown {
            // Also brings back an orb that was turned on again while still shrinking away.
            withAnimation(VaporMotion.orbEnter) { scale = 1 }
            withAnimation(.easeOut(duration: 0.22)) { opacity = 1 }
        } else {
            withAnimation(.easeOut(duration: VaporMotion.orbExitSwell)) { scale = 1.06 }
            shrink = Task {
                try? await Task.sleep(for: .seconds(VaporMotion.orbExitSwell))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: VaporMotion.orbExitShrink)) {
                    scale = Self.hiddenScale
                    opacity = 0
                }
            }
        }
    }
}

/// Particles gathering into the orb as it condenses: thirty soft dots start in a ring around
/// it and fall into its centre, slowly at first.
///
/// Positions are a pure function of the time since the entrance began, from a fixed seed. The
/// timeline runs only for ``VaporMotion/orbCondense`` seconds after each entrance and is paused
/// otherwise, so a resting orb draws nothing here. Not shown under Reduce Motion.
struct VaporOrbCondense: View {
    let presence: VaporOrbPresence
    let reduceMotion: Bool
    let color: Color

    /// When the current entrance began; nil while nothing gathers.
    @State private var start: Date?

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                Self.draw(elapsed: timeline.date.timeIntervalSince(start), in: &context, size: size, color: color)
            }
        }
        .onChange(of: presence, initial: true) { _, presence in
            start = presence.isEntering && !reduceMotion ? .now : nil
        }
        .task(id: start) {
            guard start != nil else { return }
            try? await Task.sleep(for: .seconds(VaporMotion.orbCondense + 0.05))
            guard !Task.isCancelled else { return }
            start = nil
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct Mote {
        let angle: Double
        /// Starting distance from the orb's centre, in orb diameters.
        let distance: Double
        let lifetime: Double
        let radius: Double
    }

    private static let motes: [Mote] = {
        var random = VaporSeededRandom(seed: 0xC0DE_15ED)
        return (0..<30).map { _ in
            Mote(angle: random.value(in: 0...(2 * .pi)), distance: random.value(in: 0.58...0.86),
                 lifetime: random.value(in: 0.45...VaporMotion.orbCondense), radius: random.value(in: 1...2.4))
        }
    }()

    /// Draws the motes `elapsed` seconds into an entrance. Internal so a snapshot can show a frame.
    static func draw(elapsed: Double, in context: inout GraphicsContext, size: CGSize, color: Color) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let diameter = Double(VaporGeometry.orbDiameter)
        for mote in motes {
            let progress = elapsed / mote.lifetime
            guard progress >= 0, progress < 1 else { continue }
            // Accelerating fall toward the centre; quick fade in, dimming a little on the way.
            let remaining = mote.distance * diameter * (1 - progress * progress)
            let opacity = min(1, progress * 3) * (1 - progress * 0.3) * 0.8
            let x = center.x + CGFloat(cos(mote.angle) * remaining), y = center.y + CGFloat(sin(mote.angle) * remaining)
            let r = CGFloat(mote.radius)
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(opacity)))
        }
    }
}

#if DEBUG
#Preview("Condensing") {
    let controller = VaporPreviewData.controller(Array(VaporPreviewData.pile.prefix(3)))
    controller.showOrb(animated: true)
    return VaporOrbView(controller: controller, pile: VaporPreviewData.settledPile(for: controller))
        .background(VaporPreviewBackdrop())
}

#Preview("Shrinking away") {
    let controller = VaporPreviewData.controller(Array(VaporPreviewData.pile.prefix(3)))
    controller.hideOrb()
    return VaporOrbView(controller: controller, pile: VaporPreviewData.settledPile(for: controller))
        .background(VaporPreviewBackdrop())
}
#endif
