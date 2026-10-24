import SwiftUI

/// The flying piece: the picked region as the selection sheet drew it, a faint accent fill with
/// a dashed accent outline, now off the sheet with a shadow under it. It is drawn straight from
/// `RobiFlightPath.frame(at:)` each frame, so the moment it lands is the same one the controller
/// startles the face at. With Reduce Motion it stays put and fades, without a shadow.
struct RobiFlightView: View {
    let state: RobiFlightState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 120, paused: state.flight == nil)) { context in
            ZStack(alignment: .topLeading) {
                if let flight = state.flight {
                    let frame = flight.frame(at: context.date)
                    RobiFlightPiece(cornerRadius: frame.cornerRadius, lineWidth: frame.lineWidth, lift: frame.lift)
                        .frame(width: frame.rect.width, height: frame.rect.height)
                        .offset(x: frame.rect.minX, y: frame.rect.minY)
                        .opacity(frame.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The region as `RobiSelectionSheet` draws it, so the hand-off is seamless: the same corner
/// radius, fill, 2 pt dash of 7 on and 4 off, stroked on the edge. The shadow fades in with
/// `lift` as the piece comes off the sheet.
private struct RobiFlightPiece: View {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let lift: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.accentColor.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, dash: [7, 4]))
            }
            .shadow(color: .black.opacity(0.22 * lift), radius: 10 * lift, y: 5 * lift)
    }
}

#if DEBUG
/// A window-sized stand-in with Robi's face above its top edge, and a region flying from a few
/// spots in turn: close to the face, far down on the other side, and a wide one.
private struct RobiFlightPreview: View {
    @State private var state = RobiFlightState()
    let reduceMotion: Bool

    /// The stand-in window and face, in AppKit points, as the controller would hand them over.
    private static let window = CGRect(x: 0, y: 0, width: 480, height: 260)
    private static let face = CGPoint(x: 150, y: window.maxY + RobiMetrics.tabHeight / 2)
    private static let regions: [CGRect] = [
        CGRect(x: 60, y: 40, width: 150, height: 34),
        CGRect(x: 320, y: 170, width: 120, height: 60),
        CGRect(x: 30, y: 110, width: 400, height: 90),
    ]
    private static let sample = RobiFlightPath(region: regions[0], window: window, face: face, reduceMotion: false)

    var body: some View {
        let frame = Self.sample.overlayFrame
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: Self.window.width, height: Self.window.height)
                .offset(x: Self.window.minX - frame.minX, y: frame.maxY - Self.window.maxY)
            RobiFaceView(eyes: RobiEyes(), phase: .prompting, compact: true, reduceMotion: reduceMotion)
                .position(x: Self.face.x - frame.minX, y: frame.maxY - Self.face.y)
            RobiFlightView(state: state)
        }
        .frame(width: frame.width, height: frame.height)
        .background(Color(red: 0.86, green: 0.83, blue: 0.95))
        .task {
            var index = 0
            while !Task.isCancelled {
                state.flight = RobiFlightPath(region: Self.regions[index % Self.regions.count], window: Self.window,
                                              face: Self.face, reduceMotion: reduceMotion)
                index += 1
                try? await Task.sleep(for: .seconds(1.6))
            }
        }
    }
}

#Preview("Region flying into the face") { RobiFlightPreview(reduceMotion: false) }
#Preview("Region fading in place, Reduce Motion") { RobiFlightPreview(reduceMotion: true) }
#endif
