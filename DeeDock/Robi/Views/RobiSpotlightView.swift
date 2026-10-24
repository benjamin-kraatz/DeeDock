import SwiftUI

/// The spotlight over the window: the window dims a little except around the landmark, which
/// gets a ring in the accent colour with a soft glow. Each show lands the ring with a small
/// settle and sends one pulse outwards; moving to another landmark slides the cut-out and the
/// ring there together.
///
/// With Reduce Motion the ring fades in place, without the settle, pulse, or slide. With Reduce
/// Transparency the glow goes and the dim is a little stronger, so the cut-out still reads.
struct RobiSpotlightView: View {
    let state: RobiSpotlightState

    /// Room between the landmark and the ring, so the ring never covers the text it points at.
    private static let inset: CGFloat = 5
    /// The window's own corner radius, so the dim never pokes past its rounded corners.
    private static let windowCornerRadius: CGFloat = 16

    /// The ring's rect: the landmark with breathing room, at least big enough to see, and inside
    /// the window.
    private func ring(in size: CGSize) -> CGRect {
        var rect = state.target.insetBy(dx: -Self.inset, dy: -Self.inset)
        if rect.width < 28 { rect = rect.insetBy(dx: (rect.width - 28) / 2, dy: 0) }
        if rect.height < 22 { rect = rect.insetBy(dx: 0, dy: (rect.height - 22) / 2) }
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
        let clipped = rect.intersection(bounds)
        return clipped.isNull ? rect : clipped
    }

    var body: some View {
        GeometryReader { proxy in
            let rect = ring(in: proxy.size)
            let radius = min(10, rect.height / 2)
            ZStack(alignment: .topLeading) {
                RobiSpotlightDim(cutout: rect, radius: radius, opacity: state.reduceTransparency ? 0.32 : 0.2)
                    .clipShape(RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous))
                RobiSpotlightRing(rect: rect, radius: radius, isShown: state.isShown, pulse: state.pulse,
                                  reduceMotion: state.reduceMotion, glows: !state.reduceTransparency)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .animation(state.reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82), value: state.target)
        }
        .opacity(state.isShown ? 1 : 0)
        .animation(.easeOut(duration: state.isShown ? 0.2 : 0.34), value: state.isShown)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The dim with a rounded hole where the landmark is.
private struct RobiSpotlightDim: View {
    let cutout: CGRect
    let radius: CGFloat
    let opacity: Double

    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(opacity))
            .reverseMask(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .frame(width: cutout.width, height: cutout.height)
                    .offset(x: cutout.minX, y: cutout.minY)
            }
    }
}

/// The ring around the landmark, and the pulse it sends out when it lands.
private struct RobiSpotlightRing: View {
    let rect: CGRect
    let radius: CGFloat
    let isShown: Bool
    let pulse: Int
    let reduceMotion: Bool
    let glows: Bool

    var body: some View {
        ZStack {
            if !reduceMotion {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
                    .keyframeAnimator(initialValue: RobiSpotlightPulse(), trigger: pulse) { view, value in
                        view.scaleEffect(value.scale).opacity(value.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(1, duration: 0.12)
                            CubicKeyframe(1.35, duration: 0.7)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0.9, duration: 0.12)
                            CubicKeyframe(0, duration: 0.7)
                        }
                    }
            }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2.5)
                .shadow(color: glows ? Color.accentColor.opacity(0.55) : .clear, radius: 8)
                .scaleEffect(isShown || reduceMotion ? 1 : 1.18)
                .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.68), value: isShown)
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }
}

/// One frame of the outward pulse.
private struct RobiSpotlightPulse {
    var scale: CGFloat = 1
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
/// A window-sized stand-in with a few controls, and the spotlight hopping between them.
private struct RobiSpotlightPreview: View {
    @State private var state = RobiSpotlightState()
    let reduceMotion: Bool
    let reduceTransparency: Bool

    private static let spots: [CGRect] = [
        CGRect(x: 432, y: 14, width: 64, height: 24),
        CGRect(x: 32, y: 96, width: 220, height: 18),
        CGRect(x: 32, y: 250, width: 120, height: 28),
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
                Text(verbatim: "Could you share the slides before then? I'd like to look them over.")
                    .foregroundStyle(.secondary)
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
