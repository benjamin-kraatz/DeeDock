import CoreGraphics

/// Two native glass shapes share a sampling region. The source is absorbed into the growing
/// bubble during expansion.
struct LauncherLiquidGeometry {
    let dock: CGRect
    let destination: CGRect
    let dockRadius: CGFloat

    struct Sample: Equatable {
        let dock: CGRect
        let bubble: CGRect
        let dockRadius: CGFloat
        let bubbleRadius: CGFloat
        let dockContentOpacity: CGFloat
        let launcherContentOpacity: CGFloat
        let launcherContentScale: CGFloat
        let dockHidden: Bool
        let bubbleHidden: Bool
    }

    /// Coordinates are local, flipped AppKit points. Progress can overshoot slightly while the
    /// spring settles; visibility and opacity use clamped progress to avoid a second flash.
    func sample(at progress: Double) -> Sample {
        let p = CGFloat(max(0, progress))
        let clamped = min(1, p)
        let thickness = min(dock.width, dock.height)
        let seed = CGRect(
            x: dock.midX - thickness / 2, y: dock.midY - thickness / 2,
            width: thickness, height: thickness
        )
        let bubble = interpolate(seed, destination, p)
        let absorption = smooth((clamped - 0.08) / 0.68)
        // Absorption moves the remaining dock into the bubble before hiding it, so removing
        // the source never removes a visible piece of the glass silhouette.
        let absorbed = CGRect(x: bubble.midX - thickness / 2, y: bubble.midY - thickness / 2,
                              width: thickness, height: thickness)
        let dockShape = interpolate(dock, absorbed, absorption)
        let seedRadius = min(seed.width, seed.height) / 2
        let rounding = smooth(clamped)
        return Sample(
            dock: dockShape, bubble: bubble,
            dockRadius: min(dockRadius + (thickness / 2 - dockRadius) * absorption,
                            min(dockShape.width, dockShape.height) / 2),
            bubbleRadius: min(seedRadius + (28 - seedRadius) * rounding,
                              min(bubble.width, bubble.height) / 2),
            dockContentOpacity: 1 - smooth(clamped / 0.28),
            launcherContentOpacity: smooth((clamped - 0.25) / 0.55),
            launcherContentScale: 0.82 + 0.18 * clamped,
            dockHidden: absorption >= 1,
            bubbleHidden: p <= 0
        )
    }

    private func smooth(_ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private func interpolate(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: max(1, a.width + (b.width - a.width) * t),
               height: max(1, a.height + (b.height - a.height) * t))
    }
}
