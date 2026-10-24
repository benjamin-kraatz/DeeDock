import CoreGraphics

/// Where Robi's tab goes relative to its window.
nonisolated enum RobiPlacement: Equatable, Sendable {
    /// Grows up out of the window's top edge, like the Figma design.
    case above
    /// Hangs down inside the top edge like a notch, when nothing fits above the window
    /// (maximized under the menu bar, or full screen).
    case inside
}

/// Pure geometry for Robi's panel, kept apart from AppKit so it can be reasoned about and tested.
///
/// All rects here are AppKit (bottom-left) points. The panel is a transparent window that holds
/// the tab plus, while answering, the suggestion row or answer card hanging into the window. Its
/// top edge carries a margin for the tab's shadow when the tab sits above the window.
nonisolated enum RobiLayout {
    static func placement(window: CGRect, isFullScreen: Bool, display: RobiScreenSpace.Display?) -> RobiPlacement {
        guard !isFullScreen, let display else { return isFullScreen ? .inside : .above }
        let roomAbove = display.visibleFrame.maxY - window.maxY
        return roomAbove < RobiMetrics.tabHeight ? .inside : .above
    }

    /// The panel's frame for a panel content size. The tab's bottom edge overlaps the window's top
    /// edge by one point so no seam shows between them.
    static func panelFrame(window: CGRect, placement: RobiPlacement, size: CGSize, display: RobiScreenSpace.Display?) -> CGRect {
        let top: CGFloat = switch placement {
        case .above: window.maxY - 1 + RobiMetrics.tabHeight + RobiMetrics.shadowMargin
        case .inside: window.maxY
        }
        var x = anchorX(window: window, display: display) - size.width / 2
        if let display {
            // Keep a wide prompt bar on the window's display even when the window is partly off it.
            x = min(max(x, display.frame.minX + 4), display.frame.maxX - size.width - 4)
        }
        return CGRect(x: x.rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
    }

    /// The middle of the part of the window's top edge that is on its display.
    static func anchorX(window: CGRect, display: RobiScreenSpace.Display?) -> CGFloat {
        guard let display else { return window.midX }
        let left = max(window.minX, display.frame.minX), right = min(window.maxX, display.frame.maxX)
        return right > left ? (left + right) / 2 : window.midX
    }

    /// A window is worth a companion only when it is big enough to hold the tab comfortably.
    static func accepts(windowSize size: CGSize) -> Bool {
        size.width >= RobiMetrics.minimumWindowSize.width && size.height >= RobiMetrics.minimumWindowSize.height
    }
}

/// Robi's measurements, shared by the layout, the panel and the views. Values come from the
/// spike's lab (`docs/mockups/robi.html` uses the same ones).
nonisolated enum RobiMetrics {
    static let tabHeight: CGFloat = 42
    static let tabWidth: CGFloat = 108
    static let selectingWidth: CGFloat = 340
    static let flare: CGFloat = 11
    static let corner: CGFloat = 15
    static let shadowMargin: CGFloat = 10
    static let sideMargin: CGFloat = 12
    static let cardWidth: CGFloat = 470
    static var barWidth: CGFloat { cardWidth + 2 * flare }
    static let suggestionHeight: CGFloat = 46
    static let cardHeight: CGFloat = 320
    static let minimumWindowSize = CGSize(width: 240, height: 140)
}
