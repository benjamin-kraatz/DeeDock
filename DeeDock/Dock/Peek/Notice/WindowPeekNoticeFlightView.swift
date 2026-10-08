import Observation
import SwiftUI

/// One flight's geometry and clock sample, in the overlay's top-left-origin space.
@MainActor @Observable
final class WindowPeekNoticeFlightModel {
    /// Where the hover label stood.
    var start: CGRect
    /// The strip's resting frame, or nil until Peek has laid it out.
    var target: CGRect?
    /// The spring sample; may pass 1 briefly.
    var progress: Double = 0
    /// False once the strip in Peek has taken over; the overlay then only draws the landing edge.
    var carrying = true
    /// Strength of the red landing edge, 0 when none is drawn.
    var glint: Double = 0

    init(start: CGRect) { self.start = start }
}

/// Draws the hover label turning into Peek's notice strip on its way into the panel.
///
/// The label fades out over the first half of the flight while the strip, on Peek's card material,
/// fades in and grows from the label's size to its own. A lift shadow and a 3.5 % scale peak halfway.
struct WindowPeekNoticeFlightView: View {
    let model: WindowPeekNoticeFlightModel
    let label: DockTooltipArtwork
    let notice: WindowPeekNotice
    let reduceTransparency: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.glint > 0, let target = model.target { glint(target) }
            if model.carrying { flyer }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var flyer: some View {
        let target = model.target ?? model.start
        // Without a destination the label holds still rather than flying toward its own frame.
        let progress = model.target == nil ? 0 : model.progress
        let frame = WindowPeekNoticeMotion.flightFrame(from: model.start, to: target, progress: progress)
        let lift = WindowPeekNoticeMotion.lift(progress: progress)
        let stripOpacity = WindowPeekNoticeMotion.smoothstep(0.25, 0.85, progress)
        let radius = 7 + (WindowPeekNoticeStrip.cornerRadius - 7) * CGFloat(min(max(progress, 0), 1))
        return ZStack {
            ZStack(alignment: .topLeading) {
                // Peek's card material, so the strip reads in flight as it will once it lands.
                Rectangle().fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                                    : AnyShapeStyle(.regularMaterial))
                // Laid out at its resting width so the text wraps as it will in Peek.
                WindowPeekNoticeStrip(notice: notice)
                    .frame(width: target.width, height: target.height, alignment: .topLeading)
            }
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            .clipShape(.rect(cornerRadius: radius))
            .opacity(stripOpacity)
            label.opacity(1 - WindowPeekNoticeMotion.smoothstep(0, 0.5, progress))
        }
        .frame(width: frame.width, height: frame.height)
        .scaleEffect(1 + 0.035 * lift)
        .shadow(color: .black.opacity(0.32 * lift), radius: 14 * lift, y: 10 * lift)
        .position(x: frame.midX, y: frame.midY)
    }

    private func glint(_ target: CGRect) -> some View {
        let red = Color(nsColor: .systemRed)
        let rect = target.insetBy(dx: -1, dy: -1)
        return RoundedRectangle(cornerRadius: WindowPeekNoticeStrip.cornerRadius + 1)
            .strokeBorder(red.opacity(model.glint), lineWidth: 1)
            .shadow(color: reduceTransparency ? .clear : red.opacity(model.glint * 0.55), radius: 9)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

#if DEBUG
/// Scrubs one flight by hand; the preview canvas runs no display link.
private struct WindowPeekNoticeFlightPreview: View {
    @State private var model = WindowPeekNoticeFlightModel(start: CGRect(x: 60, y: 210, width: 220, height: 40))
    @State private var progress = 0.0

    var body: some View {
        VStack {
            WindowPeekNoticeFlightView(
                model: model,
                label: DockTooltipArtwork(name: "WhatsApp", preset: .classic,
                    badge: DockTooltipBadge(summary: "1 new", isNew: true,
                                            banner: "Mike Hoffmann: Good Morning, Mr Dikkmann")),
                notice: WindowPeekNotice(summary: "1 new", sender: "Mike Hoffmann",
                                         message: "Good Morning, Mr Dikkmann. Are we still on for 10 tomorrow?"),
                reduceTransparency: false)
                .frame(width: 340, height: 280)
                .background(.blue.gradient)
            Slider(value: $progress, in: 0...1.1)
        }
        .padding()
        .onAppear { model.target = CGRect(x: 30, y: 170, width: 264, height: 58) }
        .onChange(of: progress) { _, value in
            model.progress = value
            model.glint = value > 0.95 ? 0.9 * (1.1 - value) / 0.15 : 0
        }
    }
}

#Preview("Flight, scrubbed") { WindowPeekNoticeFlightPreview() }
#endif
