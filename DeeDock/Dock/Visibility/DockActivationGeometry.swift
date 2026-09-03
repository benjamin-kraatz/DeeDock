import CoreGraphics

/// Screen-coordinate trigger and retention regions. These never capture events themselves.
struct DockActivationGeometry {
    let zone: CGRect
    let retention: CGRect

    init(screen: CGRect, restingGlass: CGRect, envelope: CGRect, settings: DockBehaviorSettings, edge: DockEdge = .bottom) {
        let length = min(edge.length(of: screen.size), CGFloat(settings.lengthMode == .dockLength
            ? Double(edge.length(of: restingGlass.size)) : settings.customLength))
        let depth = min(edge.depth(of: screen.size), CGFloat(settings.zoneDepth))
        let offset = CGFloat(settings.zoneOffset)
        switch edge {
        case .bottom:
            let x = min(max(restingGlass.midX - length / 2 + offset, screen.minX), screen.maxX - length)
            let y = settings.activationLocation == .screenEdge ? screen.minY : restingGlass.minY
            zone = CGRect(x: x, y: min(max(y, screen.minY), screen.maxY - depth), width: length, height: depth)
        case .left, .right:
            // Positive offsets move down, opposite AppKit's screen y axis.
            let y = min(max(restingGlass.midY - length / 2 - offset, screen.minY), screen.maxY - length)
            let boundary = settings.activationLocation == .screenEdge
                ? (edge == .left ? screen.minX : screen.maxX)
                : (edge == .left ? restingGlass.minX : restingGlass.maxX)
            let x = edge == .left ? boundary : boundary - depth
            zone = CGRect(x: min(max(x, screen.minX), screen.maxX - depth), y: y, width: depth, height: length)
        }
        retention = envelope.union(zone).intersection(screen)
    }
}

/// Fixed animation envelope in screen points. Content keeps its unclipped local coordinate system.
struct DockPresentationGeometry {
    let windowFrame: CGRect
    let contentOrigin: CGPoint
    let contentSize: CGSize
    let activation: DockActivationGeometry

    init(screen: CGRect, restingFrame: CGRect, layout: DockGeometry.Layout, settings: DockBehaviorSettings) {
        windowFrame = restingFrame.insetBy(dx: -DockAnimationGeometry.margin, dy: -DockAnimationGeometry.margin).intersection(screen)
        contentOrigin = CGPoint(x: restingFrame.minX - windowFrame.minX, y: windowFrame.maxY - restingFrame.maxY)
        contentSize = restingFrame.size
        activation = DockActivationGeometry(screen: screen, restingGlass: DockGeometry.restingGlass(frame: restingFrame, layout: layout),
                                            envelope: restingFrame, settings: settings, edge: layout.edge)
    }
}
