import SwiftUI

/// The spotlight over the window: the window dims a little except around the landmark, which
/// gets a ring in the accent colour with a soft glow on the dimmed side. Each show lands the ring
/// from a few points out and sends one pulse outwards; moving to another landmark slides the
/// cut-out and the ring there together.
///
/// The settle and the pulse travel a fixed distance in points, not a fraction of the landmark,
/// so a checkbox and a paragraph get the same motion. With Reduce Motion the ring fades in place,
/// without the settle, pulse, or slide. With Reduce Transparency the glow goes and the dim is a
/// little stronger, so the cut-out still reads.
struct RobiSpotlightView: View {
    let state: RobiSpotlightState

    /// Room between the landmark and the ring's centre line, so the ring never covers the text
    /// it points at.
    private static let inset: CGFloat = 5
    /// The ring's stroke, centred on the cut-out's edge: half over the dim, half inside it.
    private static let lineWidth: CGFloat = 2
    /// The smallest rect the ring draws around, so a checkbox or a short word still gets a ring
    /// the eye can find.
    private static let minimumSize = CGSize(width: 28, height: 22)
    /// The window's own corner radius, so the dim never pokes past its rounded corners.
    private static let windowCornerRadius: CGFloat = 16

    /// The ring's rect: the landmark with breathing room, at least `minimumSize`, and inside the
    /// window.
    private func ring(in size: CGSize) -> CGRect {
        var rect = state.target.insetBy(dx: -Self.inset, dy: -Self.inset)
        if rect.width < Self.minimumSize.width { rect = rect.insetBy(dx: (rect.width - Self.minimumSize.width) / 2, dy: 0) }
        if rect.height < Self.minimumSize.height { rect = rect.insetBy(dx: 0, dy: (rect.height - Self.minimumSize.height) / 2) }
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
        let clipped = rect.intersection(bounds)
        return clipped.isNull ? rect : clipped
    }

    /// Tight on a small control, rounder on a block of text or an image, never a pill.
    private static func cornerRadius(for rect: CGRect) -> CGFloat {
        min(12, max(6, min(rect.width, rect.height) * 0.3))
    }

    var body: some View {
        GeometryReader { proxy in
            let rect = ring(in: proxy.size)
            let radius = Self.cornerRadius(for: rect)
            ZStack(alignment: .topLeading) {
                RobiSpotlightDim(cutout: rect, radius: radius, opacity: state.reduceTransparency ? 0.32 : 0.2,
                                 glows: !state.reduceTransparency)
                    .clipShape(RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous))
                RobiSpotlightRing(rect: rect, radius: radius, lineWidth: Self.lineWidth, isShown: state.isShown,
                                  pulse: state.pulse, reduceMotion: state.reduceMotion)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            // The slide to another landmark: firm, with no visible overshoot, so the ring reads
            // as pointing rather than bouncing.
            .animation(state.reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: state.target)
        }
        .opacity(state.isShown ? 1 : 0)
        .animation(.easeOut(duration: state.isShown ? 0.18 : 0.32), value: state.isShown)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Everything outside the cut-out: the dim, and the ring's glow. The glow lives here, under the
/// same mask, so it lights the dimmed window around the landmark and never softens the landmark
/// itself.
private struct RobiSpotlightDim: View {
    let cutout: CGRect
    let radius: CGFloat
    let opacity: Double
    let glows: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black.opacity(opacity))
            if glows {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.85), lineWidth: 6)
                    .blur(radius: 7)
                    .frame(width: cutout.width, height: cutout.height)
                    .offset(x: cutout.minX, y: cutout.minY)
            }
        }
        .reverseMask(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .frame(width: cutout.width, height: cutout.height)
                .offset(x: cutout.minX, y: cutout.minY)
        }
    }
}

/// The ring on the cut-out's edge, its landing, and the pulse it sends out when it lands.
///
/// Landing and pulse both grow the ring by `reach` points and its corner radius by the same, so
/// the larger ring stays concentric with the cut-out instead of scaling about its centre.
private struct RobiSpotlightRing: View {
    let rect: CGRect
    let radius: CGFloat
    let lineWidth: CGFloat
    let isShown: Bool
    let pulse: Int
    let reduceMotion: Bool

    /// Where the ring starts before it lands, and where it goes as the spotlight lets go.
    private static let settleReach: CGFloat = 8
    /// How far the pulse travels.
    private static let pulseReach: CGFloat = 14

    private var settle: CGFloat { isShown || reduceMotion ? 0 : Self.settleReach }

    var body: some View {
        ZStack {
            if !reduceMotion {
                KeyframeAnimator(initialValue: RobiSpotlightPulse(), trigger: pulse) { value in
                    RobiSpotlightOutline(radius: radius, reach: value.reach, lineWidth: lineWidth)
                        .opacity(value.opacity)
                } keyframes: { _ in
                    // Holds while the ring lands, then leaves quickly and slows as it fades.
                    KeyframeTrack(\.reach) {
                        LinearKeyframe(0, duration: 0.1)
                        SpringKeyframe(Self.pulseReach, duration: 0.55, spring: .smooth(duration: 0.5))
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0.7, duration: 0.1)
                        LinearKeyframe(0, duration: 0.55)
                    }
                }
            }
            RobiSpotlightOutline(radius: radius, reach: settle, lineWidth: lineWidth)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: isShown)
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }
}

/// A stroke in the accent colour on the cut-out's edge, pushed out by `reach` points on every side.
private struct RobiSpotlightOutline: View {
    let radius: CGFloat
    let reach: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius + reach, style: .continuous)
            .stroke(Color.accentColor, lineWidth: lineWidth)
            .padding(-reach)
    }
}

/// One frame of the outward pulse.
private struct RobiSpotlightPulse {
    var reach: CGFloat = 0
    var opacity: Double = 0
}

private extension View {
    /// Keeps this view everywhere except where `mask` draws.
    func reverseMask<Mask: View>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: alignment) { mask().blendMode(.destinationOut) }
                .compositingGroup()
        }
    }
}

#if DEBUG
/// A window-sized stand-in with a few controls, and the spotlight hopping between them: a
/// button, a line of text, a checkbox smaller than the ring's minimum, and a block.
private struct RobiSpotlightPreview: View {
    @State private var state = RobiSpotlightState()
    let reduceMotion: Bool
    let reduceTransparency: Bool

    private static let spots: [CGRect] = [
        CGRect(x: 432, y: 14, width: 64, height: 24),
        CGRect(x: 32, y: 96, width: 220, height: 18),
        CGRect(x: 32, y: 128, width: 14, height: 14),
        CGRect(x: 32, y: 170, width: 300, height: 90),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RobiSpotlightPreviewWindow()
            RobiSpotlightView(state: state)
        }
        .frame(width: 520, height: 320)
        .task {
            state.reduceMotion = reduceMotion
            state.reduceTransparency = reduceTransparency
            var index = 0
            while !Task.isCancelled {
                state.target = Self.spots[index % Self.spots.count]
                state.isShown = true
                state.pulse += 1
                index += 1
                try? await Task.sleep(for: .seconds(1.8))
            }
        }
    }
}

private struct RobiSpotlightPreviewWindow: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .windowBackgroundColor))
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(verbatim: "Inbox").font(.headline)
                    Spacer()
                    Button { } label: { Text(verbatim: "Send") }
                }
                .padding(.top, 2)
                Text(verbatim: "Meeting moved to 3 pm on Thursday")
                    .padding(.top, 50)
                Toggle(isOn: .constant(true)) { Text(verbatim: "Remind me") }
                    .toggleStyle(.checkbox)
                Text(verbatim: "Could you share the slides before then? I'd like to look them over, and I'd like to send a few notes to the team ahead of the meeting so nobody is surprised.")
                    .foregroundStyle(.secondary)
                    .frame(width: 300, alignment: .leading)
                Spacer()
                Button { } label: { Text(verbatim: "Reply All") }
            }
            .padding(16)
        }
    }
}

#Preview("Spotlight hopping between landmarks") { RobiSpotlightPreview(reduceMotion: false, reduceTransparency: false) }
#Preview("Spotlight, Reduce Motion and Reduce Transparency") { RobiSpotlightPreview(reduceMotion: true, reduceTransparency: true) }
#endif
