import SwiftUI

/// The Line icon badge: a red ring around the tile while its badge is news.
///
/// When `active` turns on, the ring draws itself in clockwise from the top. When it turns off, a
/// white ring draws in over the red the same way and then draws out the same way, so
/// acknowledging a badge plays the arrival back in white. Both gestures take ``duration``. Hover
/// and keyboard selection brighten and thicken the ring and add a red glow.
///
/// Reduce Motion fades the ring in and out instead of drawing it. Reduce Transparency keeps the
/// brighter, thicker hover ring and drops the glow. A ring already active when the tile appears is
/// drawn without animating, so opening a dock does not replay every standing badge. The ring sits
/// inside the tile's square and never takes hit-testing.
struct DockBadgeRing: View {
    let active: Bool
    /// The tile's icon size in points.
    let size: CGFloat
    let highlighted: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool

    /// How long the red ring takes to draw in, and the white ring to draw in and out together.
    static let duration = 0.7
    /// Ring diameter as a share of the tile.
    static let diameterFraction: CGFloat = 0.9

    /// How far round the red ring reaches, from 0 to 1.
    @State private var redEnd: Double
    @State private var redVisible = true
    /// The white sweep's trailing and leading ends.
    @State private var whiteStart = 0.0
    @State private var whiteEnd = 0.0
    /// Reduce Motion fades the whole ring rather than drawing it.
    @State private var fade = 1.0
    /// Bumped by each arrival or clear, so a superseded gesture's completion does nothing.
    @State private var generation = 0

    init(active: Bool, size: CGFloat, highlighted: Bool, reduceMotion: Bool, reduceTransparency: Bool) {
        self.active = active
        self.size = size
        self.highlighted = highlighted
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        _redEnd = State(initialValue: active ? 1 : 0)
    }

    /// At rest the ring is a little lighter than the glyph's own lines; highlighted it matches them.
    private var lineWidth: CGFloat {
        let glyphStroke = LineIconArtwork.strokeWidth * size * LineIconArtwork.boxFraction / LineIconPath.canvas
        return glyphStroke * (highlighted ? 1 : 0.7)
    }

    private var glowing: Bool { highlighted && !reduceTransparency }
    private var red: Color { highlighted ? Color(red: 1, green: 0.42, blue: 0.37) : Color(nsColor: .systemRed) }

    var body: some View {
        let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        ZStack {
            Circle()
                .trim(from: 0, to: redEnd)
                .stroke(red, style: stroke)
                .shadow(color: glowing ? Color(nsColor: .systemRed).opacity(0.95) : .clear, radius: glowing ? lineWidth * 1.1 : 0)
                .shadow(color: glowing ? Color(nsColor: .systemRed).opacity(0.55) : .clear, radius: glowing ? lineWidth * 3 : 0)
                .opacity(redVisible ? 1 : 0)
            Circle()
                .trim(from: whiteStart, to: whiteEnd)
                .stroke(.white, style: stroke)
                .shadow(color: glowing ? .white.opacity(0.8) : .clear, radius: glowing ? lineWidth * 1.3 : 0)
        }
        // Circle paths start at three o'clock; a quarter turn back starts both sweeps at the top.
        .rotationEffect(.degrees(-90))
        .frame(width: size * Self.diameterFraction, height: size * Self.diameterFraction)
        .frame(width: size, height: size)
        .opacity(fade)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: highlighted)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: active) { _, isActive in
            if isActive { arrive() } else { clear() }
        }
    }

    private func arrive() {
        generation += 1
        // A clear still running is abandoned; the red ring starts over from the top.
        reset(redEnd: 0)
        if reduceMotion {
            redEnd = 1
            fade = 0
            withAnimation(.easeOut(duration: 0.25)) { fade = 1 }
        } else {
            // Ease-out cubic: the ring leaves the top quickly and settles as it closes.
            withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: Self.duration)) { redEnd = 1 }
        }
    }

    private func clear() {
        generation += 1
        let token = generation
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.25)) { fade = 0 } completion: {
                guard generation == token else { return }
                reset(redEnd: 0)
            }
            return
        }
        // One ease-in-out cubic split at its midpoint: the white accelerates in over the red, then
        // decelerates out. Both halves meet at the same speed, so the handover shows no seam.
        let half = Self.duration / 2
        withAnimation(.timingCurve(0.32, 0, 0.67, 0, duration: half)) { whiteEnd = 1 } completion: {
            guard generation == token else { return }
            redVisible = false
            withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: half)) { whiteStart = 1 } completion: {
                guard generation == token else { return }
                reset(redEnd: 0)
            }
        }
    }

    /// Returns every stroke to rest without animating.
    private func reset(redEnd: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.redEnd = redEnd
            redVisible = true
            whiteStart = 0
            whiteEnd = 0
            fade = 1
        }
    }
}

#if DEBUG
/// Toggles one ring so the preview canvas can play arrival and clear.
private struct DockBadgeRingPreview: View {
    let reduceMotion: Bool
    @State private var active = true
    @State private var highlighted = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Image(systemName: "message").font(.system(size: 30, weight: .light)).foregroundStyle(.white)
                DockBadgeRing(active: active, size: 64, highlighted: highlighted,
                              reduceMotion: reduceMotion, reduceTransparency: false)
            }
            .frame(width: 64, height: 64)
            .onHover { highlighted = $0 }
            Button { active.toggle() } label: { Text(verbatim: active ? "Clear" : "Arrive") }
        }
        .padding(30)
        .background(.black)
    }
}

#Preview("Ring: arrive, hover, clear") {
    HStack(spacing: 0) {
        DockBadgeRingPreview(reduceMotion: false)
        // A local flag stands in for Reduce Motion; the environment key is not overridden.
        DockBadgeRingPreview(reduceMotion: true)
    }
}

#Preview("Ring sizes, resting and highlighted") {
    HStack(spacing: 20) {
        ForEach([32.0, 48, 80], id: \.self) { size in
            DockBadgeRing(active: true, size: size, highlighted: false, reduceMotion: false, reduceTransparency: false)
            DockBadgeRing(active: true, size: size, highlighted: true, reduceMotion: false, reduceTransparency: false)
        }
        DockBadgeRing(active: true, size: 48, highlighted: true, reduceMotion: false, reduceTransparency: true)
    }
    .padding(30)
    .background(.black)
}
#endif
