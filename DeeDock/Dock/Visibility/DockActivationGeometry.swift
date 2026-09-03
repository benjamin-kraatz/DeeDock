import CoreGraphics

/// Screen-coordinate trigger and retention regions. These never become event-capturing windows.
struct DockActivationGeometry {
    let zone: CGRect
    let retention: CGRect

    init(screen: CGRect, restingGlass: CGRect, envelope: CGRect, settings: DockBehaviorSettings) {
        let width = min(screen.width, CGFloat(settings.widthMode == .dockWidth ? Double(restingGlass.width) : settings.customWidth))
        let x = min(max(restingGlass.midX - width / 2 + CGFloat(settings.zoneOffset), screen.minX), screen.maxX - width)
        let y = settings.activationLocation == .screenEdge ? screen.minY : restingGlass.minY
        let height = min(screen.height, CGFloat(settings.zoneHeight))
        zone = CGRect(x: x, y: min(max(y, screen.minY), screen.maxY - height), width: width, height: height)
        // The bounding rectangle bridges an offset trigger and an elevated dock without stealing clicks.
        retention = envelope.union(zone).intersection(screen)
    }
}

/// Reserves effect space without moving the resting dock. All native geometry remains in screen points.
struct DockPresentationGeometry {
    let windowFrame: CGRect
    let contentOrigin: CGPoint
    let contentSize: CGSize
    let activation: DockActivationGeometry

    init(screen: CGRect, restingFrame: CGRect, layout: DockGeometry.Layout, settings: DockBehaviorSettings) {
        windowFrame = restingFrame.insetBy(dx: -DockAnimationGeometry.margin, dy: -DockAnimationGeometry.margin).intersection(screen)
        contentOrigin = CGPoint(x: restingFrame.minX - windowFrame.minX, y: windowFrame.maxY - restingFrame.maxY)
        contentSize = restingFrame.size
        let width = min(layout.viewportWidth, layout.contentWidth(sizes: Array(repeating: layout.iconSize, count: layout.restingCenters.count)))
        let glass = CGRect(x: restingFrame.midX - width / 2, y: restingFrame.minY + DockGeometry.bottomMargin,
                           width: width, height: layout.surfaceHeight)
        activation = DockActivationGeometry(screen: screen, restingGlass: glass, envelope: restingFrame, settings: settings)
    }
}
