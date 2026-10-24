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
    ///
    /// - Parameters:
    ///   - position: Where the person dragged the tab, as the tab centre's fraction of the window's
    ///     width (see `tabX(window:position:display:)`). Nil centres it on the visible edge.
    ///   - stretch: A rubber-band offset past the end of the tab's track while it is dragged
    ///     beyond it, from `rubberBand(_:)`. Zero at rest.
    ///
    /// The panel is centred on the tab, so the wide prompt bar and card stay centred on it too and
    /// can overhang the window's side when the tab sits near a corner.
    static func panelFrame(window: CGRect, placement: RobiPlacement, size: CGSize, display: RobiScreenSpace.Display?,
                           position: Double? = nil, stretch: CGFloat = 0) -> CGRect {
        let top: CGFloat = switch placement {
        case .above: window.maxY - 1 + RobiMetrics.tabHeight + RobiMetrics.shadowMargin
        case .inside: window.maxY
        }
        var x = tabX(window: window, position: position, display: display) + stretch - size.width / 2
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

    // MARK: Moving the tab along the top edge

    /// The x values the tab's centre can take along the window's top edge: the part of the edge on
    /// the window's display, inset so the whole idle tab, flares included, stays over the window
    /// and clear of its rounded corners. A span too narrow for that collapses to its middle.
    static func tabTrack(window: CGRect, display: RobiScreenSpace.Display?) -> ClosedRange<CGFloat> {
        var left = window.minX, right = window.maxX
        if let display {
            let visibleLeft = max(left, display.frame.minX), visibleRight = min(right, display.frame.maxX)
            if visibleRight > visibleLeft { (left, right) = (visibleLeft, visibleRight) }
        }
        // The flares are part of `tabWidth`: the shape draws them inside its frame.
        let reach = RobiMetrics.tabWidth / 2 + RobiMetrics.edgeInset
        guard right - left > 2 * reach else { return ((left + right) / 2)...((left + right) / 2) }
        return (left + reach)...(right - reach)
    }

    /// The tab centre's x for a remembered position, clamped to `tabTrack`.
    ///
    /// A position is the centre's fraction of the window's whole width, measured from its left
    /// edge, so it survives resizing and moving the window. Nil gives the default, `anchorX`.
    static func tabX(window: CGRect, position: Double?, display: RobiScreenSpace.Display?) -> CGFloat {
        guard let position, position.isFinite else { return anchorX(window: window, display: display) }
        let track = tabTrack(window: window, display: display)
        return min(max(window.minX + CGFloat(position) * window.width, track.lowerBound), track.upperBound)
    }

    /// The position for a tab centre the pointer asks for while dragging: the inverse of
    /// `tabX(window:position:display:)`, clamped to the track first, so the position stored on
    /// release is one the tab can actually take.
    static func position(forTabX x: CGFloat, window: CGRect, display: RobiScreenSpace.Display?) -> Double {
        guard window.width > 0 else { return 0.5 }
        let track = tabTrack(window: window, display: display)
        let clamped = min(max(x, track.lowerBound), track.upperBound)
        return Double((clamped - window.minX) / window.width)
    }

    /// How far the tab follows a pointer that drags past the end of its track: a resistance that
    /// starts at half the overshoot and never exceeds `RobiMetrics.rubberBandLimit`.
    static func rubberBand(_ overshoot: CGFloat) -> CGFloat {
        let limit = RobiMetrics.rubberBandLimit
        let magnitude = limit * (1 - 1 / (abs(overshoot) * 0.5 / limit + 1))
        return overshoot < 0 ? -magnitude : magnitude
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
    /// The row of suggested questions under the built-in actions: a pill and the gap above it.
    static let generatedSuggestionHeight: CGFloat = 32
    static let cardHeight: CGFloat = 320
    static let minimumWindowSize = CGSize(width: 240, height: 140)
    /// How far a dragged tab's outer edge stays from the window's sides. macOS rounds window
    /// corners, and at this distance the top edge has curved down by about 2 pt at most.
    static let edgeInset: CGFloat = 16
    /// The furthest a tab dragged past the end of its track rubber-bands beyond it.
    static let rubberBandLimit: CGFloat = 18
    /// How far the pointer moves from a press on the face before the press becomes a drag.
    static let dragThreshold: CGFloat = 4
}
