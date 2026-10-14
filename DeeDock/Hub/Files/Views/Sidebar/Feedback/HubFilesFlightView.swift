import SwiftUI
import UniformTypeIdentifiers

/// A folder's icon arcing from where it was added (the item under the context menu) to its new
/// sidebar row, drawn in an overlay window that spans both points.
///
/// `start` and `end` are the icon's centers in this view's coordinate space. The arc rises above
/// the higher of the two points, the icon grows a little mid-flight and lands at the size of the
/// sidebar glyph, then fades out over `fadeDuration` while the row underneath glows.
struct HubFilesFlightView: View {
    /// How long the landed icon takes to fade. The window stays up at least this long after landing.
    static let fadeDuration: Double = 0.16

    let icon: NSImage
    let start: CGPoint
    let end: CGPoint
    let duration: Double

    @State private var progress: CGFloat = 0
    @State private var landed = false

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: 22, height: 22)
            .modifier(HubFilesFlightPath(progress: progress, start: start, end: end))
            .opacity(landed ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                withAnimation(.timingCurve(0.5, 0, 0.25, 1, duration: duration)) { progress = 1 }
            }
            .task {
                // Cancelled with the view if the window goes away first.
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: Self.fadeDuration)) { landed = true }
            }
            .accessibilityHidden(true)
    }
}

/// Positions and scales the flying icon along a quadratic curve. Animatable through `progress`,
/// so SwiftUI interpolates the curve rather than a straight line between the ends.
private struct HubFilesFlightPath: ViewModifier, Animatable {
    var progress: CGFloat
    let start: CGPoint
    let end: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 90)
        let t = progress, u = 1 - t
        let point = CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
        // 1 → 1.35 at the apex → 0.86 on landing, the sidebar glyph's size.
        let scale = t < 0.5 ? 1 + 0.7 * t : 1.35 - 0.98 * (t - 0.5)
        content
            .scaleEffect(scale)
            // Lands at 90 %, so the row's glyph reads through as it takes over.
            .opacity(Double(1 - 0.1 * t))
            .position(point)
    }
}

#Preview("Flight") {
    HubFilesFlightView(icon: NSWorkspace.shared.icon(for: .folder), start: CGPoint(x: 260, y: 160),
                       end: CGPoint(x: 40, y: 60), duration: 2)
        .frame(width: 300, height: 200)
}
