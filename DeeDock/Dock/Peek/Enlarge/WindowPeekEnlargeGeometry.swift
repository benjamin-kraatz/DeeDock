import CoreGraphics

/// Places the enlarged preview ("hero") for a Peek card.
///
/// Inputs and outputs are AppKit screen coordinates in points, y pointing up, so negative display
/// origins and secondary displays need no special casing. `local(_:in:)` is the one conversion into
/// the stage panel's SwiftUI space (y pointing down from the panel's top-left corner).
nonisolated enum WindowPeekEnlargeGeometry {
    /// Clearance from the display's usable edges. The hero is a centered exhibit, never edge to edge.
    static let screenMargin: CGFloat = 48
    /// Clearance between the hero block and the Peek panel it came from.
    static let peekGap: CGFloat = 24
    /// Space under the hero for the window-title placard.
    static let placardSpace: CGFloat = 44
    /// Largest share of the usable display either hero dimension may take.
    static let maximumShare: CGFloat = 0.72
    /// Below this, an enlargement is barely larger than a Large card and is not worth staging.
    static let minimumSide: CGFloat = 240
    /// Exact centering wins unless it costs more than 30% of the hero's size.
    static let minimumCenteredShare: CGFloat = 0.7

    /// The hero's image frame, or `nil` when the display has no room for a meaningful enlargement.
    ///
    /// The hero keeps the window's aspect ratio and never exceeds the window's own size in points, so it
    /// never upscales past the source. The image is centered exactly on the display (`screenFrame`, not
    /// the visible frame, so the menu bar does not pull it off center); it shrinks until it clears the
    /// usable margins, its placard, and the Peek panel symmetrically about that center. When a tall
    /// Peek panel would shrink a centered hero below `minimumCenteredShare` of what the free region
    /// allows, it grows into that region off center instead, sliding away from the dock edge. It never covers the Peek panel, because the pointer is still scrubbing the cards.
    static func hero(windowSize: CGSize, screenFrame: CGRect, visibleFrame: CGRect, peekFrame: CGRect,
                     edge: DockEdge) -> CGRect? {
        guard windowSize.width > 1, windowSize.height > 1 else { return nil }
        var region = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        switch edge {
        case .bottom: region = region.clampingMinY(peekFrame.maxY + peekGap)
        case .top: region = region.clampingMaxY(peekFrame.minY - peekGap)
        case .left: region = region.clampingMinX(peekFrame.maxX + peekGap)
        case .right: region = region.clampingMaxX(peekFrame.minX - peekGap)
        }
        let center = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
        // The placard hangs below the image, so the lower half also has to hold it.
        let halfWidth = min(center.x - region.minX, region.maxX - center.x)
        let halfHeight = min(region.maxY - center.y, center.y - region.minY - placardSpace)
        let centered = fitted(windowSize, into: CGSize(width: 2 * halfWidth, height: 2 * halfHeight),
                              visibleFrame: visibleFrame)
        let free = fitted(windowSize, into: CGSize(width: region.width, height: region.height - placardSpace),
                          visibleFrame: visibleFrame)
        if let centered, centered.width >= (free?.width ?? 0) * minimumCenteredShare {
            return CGRect(x: center.x - centered.width / 2, y: center.y - centered.height / 2,
                          width: centered.width, height: centered.height)
        }
        guard let size = free else { return nil }
        let origin = CGPoint(x: min(max(center.x - size.width / 2, region.minX), region.maxX - size.width),
                             y: min(max(center.y - size.height / 2, region.minY + placardSpace),
                                    region.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }

    /// The window's size scaled to fit `bounds`, the display share, and its own size; `nil` if too small.
    private static func fitted(_ windowSize: CGSize, into bounds: CGSize, visibleFrame: CGRect) -> CGSize? {
        let limit = CGSize(width: min(bounds.width, visibleFrame.width * maximumShare, windowSize.width),
                           height: min(bounds.height, visibleFrame.height * maximumShare, windowSize.height))
        guard limit.width > 0, limit.height > 0 else { return nil }
        let scale = min(limit.width / windowSize.width, limit.height / windowSize.height)
        let size = CGSize(width: (windowSize.width * scale).rounded(.down),
                          height: (windowSize.height * scale).rounded(.down))
        return max(size.width, size.height) >= minimumSide ? size : nil
    }

    /// The rectangle a `scaledToFit` image of `imageSize` occupies inside `container`.
    static func aspectFit(_ imageSize: CGSize, in container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return container
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: container.midX - size.width / 2, y: container.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Converts a screen rectangle into the top-left-origin space of a panel covering `container`.
    static func local(_ rect: CGRect, in container: CGRect) -> CGRect {
        CGRect(x: rect.minX - container.minX, y: container.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The inverse of `local(_:in:)`: a panel-space rectangle back in screen coordinates.
    static func screen(_ rect: CGRect, in container: CGRect) -> CGRect {
        CGRect(x: container.minX + rect.minX, y: container.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a Quartz global rectangle (Accessibility and ScreenCaptureKit window frames: y down from
    /// the primary display's top) to AppKit screen coordinates (y up from the primary display's bottom).
    static func appKit(fromQuartz rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryMaxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Hi-res capture budget: the hero's logical size in the display's backing pixels.
    static func capturePixels(hero: CGSize, backingScale: CGFloat) -> CGSize {
        let scale = max(1, backingScale)
        return CGSize(width: (hero.width * scale).rounded(.up), height: (hero.height * scale).rounded(.up))
    }
}

nonisolated private extension CGRect {
    func clampingMinY(_ value: CGFloat) -> CGRect {
        let minY = Swift.max(self.minY, value)
        return CGRect(x: minX, y: minY, width: width, height: Swift.max(0, maxY - minY))
    }

    func clampingMaxY(_ value: CGFloat) -> CGRect {
        CGRect(x: minX, y: minY, width: width, height: Swift.max(0, Swift.min(maxY, value) - minY))
    }

    func clampingMinX(_ value: CGFloat) -> CGRect {
        let minX = Swift.max(self.minX, value)
        return CGRect(x: minX, y: minY, width: Swift.max(0, maxX - minX), height: height)
    }

    func clampingMaxX(_ value: CGFloat) -> CGRect {
        CGRect(x: minX, y: minY, width: Swift.max(0, Swift.min(maxX, value) - minX), height: height)
    }
}

/// Pointer timing for the enlarged preview. Pure values so dwell and scrub rules stay testable.
nonisolated enum WindowPeekEnlargeTiming {
    /// A deliberate rest on a card before the first enlargement.
    static let dwell: Duration = .milliseconds(450)
    /// Once a hero is staged, moving to a neighbor swaps after a short settle instead of a full
    /// dwell. Sweeping across several cards still stages nothing until the pointer stops.
    static let scrubDwell: Duration = .milliseconds(140)
    /// Pointer travel through the gap between two cards must not dismiss the stage.
    static let leaveGrace: Duration = .milliseconds(120)

    static func dwell(staged: Bool) -> Duration { staged ? scrubDwell : dwell }
}
