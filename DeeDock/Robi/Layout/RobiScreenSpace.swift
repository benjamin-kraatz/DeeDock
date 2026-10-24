import AppKit

/// Conversions between the window server's global top-left points and AppKit's bottom-left ones.
///
/// Both spaces are anchored to the primary display (the one holding the menu bar at the origin),
/// so other displays can have negative coordinates in either. Only the y axis flips, around the
/// primary display's height.
nonisolated struct RobiScreenSpace: Equatable, Sendable {
    /// One display's frames, in AppKit coordinates.
    struct Display: Equatable, Sendable {
        let frame: CGRect
        let visibleFrame: CGRect
    }

    let primaryHeight: CGFloat
    let displays: [Display]

    @MainActor static var current: RobiScreenSpace {
        RobiScreenSpace(primaryHeight: NSScreen.screens.first?.frame.height ?? 0,
                        displays: NSScreen.screens.map { Display(frame: $0.frame, visibleFrame: $0.visibleFrame) })
    }

    func appKitRect(fromTopLeft rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    func topLeftPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// The display showing the middle of a window's top edge (AppKit rect), or the one it overlaps most.
    func display(for appKitWindow: CGRect) -> Display? {
        let topMiddle = CGPoint(x: appKitWindow.midX, y: appKitWindow.maxY - 1)
        if let hit = displays.first(where: { $0.frame.contains(topMiddle) }) { return hit }
        return displays.max { overlap($0.frame, appKitWindow) < overlap($1.frame, appKitWindow) }
    }

    /// The top-left y below which a window's title bar cannot go on the display under `point`
    /// (top-left coordinates): the bottom of that display's menu bar.
    func topLimit(at point: CGPoint) -> CGFloat {
        let appKit = CGPoint(x: point.x, y: primaryHeight - point.y)
        guard let display = displays.first(where: { $0.frame.contains(appKit) }) ?? displays.first else { return -.greatestFiniteMagnitude }
        return primaryHeight - display.visibleFrame.maxY
    }

    private func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }
}
