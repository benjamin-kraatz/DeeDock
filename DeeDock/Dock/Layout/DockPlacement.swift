import CoreGraphics

extension DockGeometry {
    /// Chooses the coordinate frame that the user's position settings refer to.
    static func referenceFrame(screenFrame: CGRect, visibleFrame: CGRect, settings: DockSettings) -> CGRect {
        settings.positionReference == .usableDesktop ? visibleFrame : screenFrame
    }

    /// Anchors the resting glass, then clamps the whole magnification envelope to the reference frame.
    /// Only the transparent bottom margin may extend below it, allowing zero glass-to-edge distance.
    static func panelFrame(referenceFrame: CGRect, layout: Layout, settings: DockSettings) -> CGRect {
        let settings = settings.normalized ?? .defaults
        let restingWidth = layout.contentWidth(sizes: Array(repeating: layout.iconSize, count: layout.restingCenters.count))
        let inset = max(0, (layout.viewportWidth - restingWidth) / 2)
        let alignedX: CGFloat
        switch settings.alignment {
        case .left: alignedX = referenceFrame.minX + 8 - inset
        case .center: alignedX = referenceFrame.midX - layout.viewportWidth / 2
        case .right: alignedX = referenceFrame.maxX - 8 - layout.viewportWidth + inset
        }
        let minimumX = referenceFrame.minX + 8
        let maximumX = max(minimumX, referenceFrame.maxX - 8 - layout.viewportWidth)
        let x = min(max(alignedX + CGFloat(settings.horizontalOffset), minimumX), maximumX)
        let minimumY = referenceFrame.minY - bottomMargin
        let maximumY = max(minimumY, referenceFrame.maxY - layout.panelHeight)
        let y = min(max(minimumY + CGFloat(settings.bottomDistance), minimumY), maximumY)
        return CGRect(x: x, y: y, width: layout.viewportWidth, height: layout.panelHeight)
    }
}
