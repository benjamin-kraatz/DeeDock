import SwiftUI

/// Faint alignment guides drawn over the desktop while a dragged pin or stack is snapped.
///
/// Guides arrive already converted to this view's top-left canvas space: a `.vertical` guide
/// draws at `position` on x between `start` and `end` on y, a `.horizontal` guide the other way
/// around. The view is purely decorative — it never hit-tests and is hidden from accessibility —
/// so it can be rebuilt on every pointer move without touching drag targeting.
struct DockMagneticGuidesView: View {
    /// Guides to draw, in the canvas' top-left space.
    let guides: [DockMagneticGuide]
    /// Size of the hosting overlay. Guides are clipped to it so a stale extent cannot bleed out.
    var canvasSize: CGSize = .zero
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Hairline core; the guide should read as a line, never as a bar.
    private var lineWidth: CGFloat { reduceTransparency ? 1.5 : 1 }
    /// The contrast halo sits under the core so the guide survives both a white and a black wallpaper.
    private var haloWidth: CGFloat { lineWidth + 2 }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            for guide in guides {
                guard let path = path(for: guide, in: bounds) else { continue }
                context.stroke(
                    path,
                    with: .color(.black.opacity(reduceTransparency ? 0.35 : 0.22)),
                    style: StrokeStyle(lineWidth: haloWidth, lineCap: .round)
                )
                context.stroke(
                    path,
                    with: .color(.accentColor.opacity(coreOpacity(for: guide.kind))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Edge guides read as the harder constraint; a peer alignment is the same line, just quieter.
    private func coreOpacity(for kind: DockMagneticGuide.Kind) -> Double {
        if reduceTransparency { return kind == .edge ? 1 : 0.85 }
        return kind == .edge ? 0.75 : 0.55
    }

    private func path(for guide: DockMagneticGuide, in bounds: CGRect) -> Path? {
        let position = pixelAligned(guide.position)
        var path = Path()
        switch guide.axis {
        case .vertical:
            guard let span = span(guide.start, guide.end, within: bounds.minY ... bounds.maxY) else { return nil }
            path.move(to: CGPoint(x: position, y: span.lowerBound))
            path.addLine(to: CGPoint(x: position, y: span.upperBound))
        case .horizontal:
            guard let span = span(guide.start, guide.end, within: bounds.minX ... bounds.maxX) else { return nil }
            path.move(to: CGPoint(x: span.lowerBound, y: position))
            path.addLine(to: CGPoint(x: span.upperBound, y: position))
        }
        return path
    }

    /// Clamps a guide's extent to the canvas, dropping guides that fall entirely outside it.
    private func span(_ start: CGFloat, _ end: CGFloat, within limits: ClosedRange<CGFloat>) -> ClosedRange<CGFloat>? {
        guard limits.lowerBound < limits.upperBound else { return start <= end ? start ... end : end ... start }
        let low = max(min(start, end), limits.lowerBound)
        let high = min(max(start, end), limits.upperBound)
        guard low <= high else { return nil }
        return low ... high
    }

    /// Snaps the line's center to a half-point so a hairline stays crisp instead of smearing
    /// across two rows of pixels on both 1x and 2x displays.
    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}

#if DEBUG
private struct GuidePreviewDesktop<Content: View>: View {
    var colors: [Color]
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: 400, height: 300)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

#Preview("Edge and peer guides — dark desktop") {
    GuidePreviewDesktop(colors: [.indigo, .black]) {
        DockMagneticGuidesView(
            guides: [
                DockMagneticGuide(axis: .vertical, position: 40, start: 20, end: 280, kind: .edge),
                DockMagneticGuide(axis: .horizontal, position: 90, start: 40, end: 360, kind: .peer),
            ],
            canvasSize: CGSize(width: 400, height: 300)
        )
    }
}

#Preview("Edge and peer guides — light desktop") {
    GuidePreviewDesktop(colors: [.white, Color(white: 0.85)]) {
        DockMagneticGuidesView(
            guides: [
                DockMagneticGuide(axis: .vertical, position: 40, start: 20, end: 280, kind: .edge),
                DockMagneticGuide(axis: .horizontal, position: 90, start: 40, end: 360, kind: .peer),
            ],
            canvasSize: CGSize(width: 400, height: 300)
        )
    }
}

#Preview("Reduce Transparency") {
    GuidePreviewDesktop(colors: [Color(white: 0.4), Color(white: 0.6)]) {
        DockMagneticGuidesView(
            guides: [
                DockMagneticGuide(axis: .vertical, position: 120, start: 10, end: 290, kind: .edge),
                DockMagneticGuide(axis: .horizontal, position: 200, start: 10, end: 390, kind: .peer),
            ],
            canvasSize: CGSize(width: 400, height: 300)
        )
    }
}

#Preview("No guides") {
    GuidePreviewDesktop(colors: [.teal, .black]) {
        DockMagneticGuidesView(guides: [], canvasSize: CGSize(width: 400, height: 300))
    }
}
#endif
