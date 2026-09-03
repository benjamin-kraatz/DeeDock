import CoreGraphics

/// A single presentation sample shared by drawing and native click passthrough.
struct DockAnimationSample: Equatable {
    var offset = CGSize.zero
    var scale: CGFloat = 1
    var opacity: Double = 1
    var mask: CGRect
    let anchor: CGPoint

    func transform(_ point: CGPoint) -> CGPoint {
        CGPoint(x: anchor.x + (point.x - anchor.x) * scale + offset.width,
                y: anchor.y + (point.y - anchor.y) * scale + offset.height)
    }
    func inverse(_ point: CGPoint) -> CGPoint {
        CGPoint(x: anchor.x + (point.x - anchor.x - offset.width) / scale,
                y: anchor.y + (point.y - anchor.y - offset.height) / scale)
    }
    /// Masks apply before scaling and translation, exactly as in the SwiftUI presentation modifier.
    func paintedRect(_ rect: CGRect) -> CGRect {
        guard opacity > 0 else { return .null }
        let clipped = rect.intersection(mask)
        guard !clipped.isNull, !clipped.isEmpty else { return .null }
        return CGRect(origin: transform(clipped.origin), size: CGSize(width: clipped.width * scale, height: clipped.height * scale))
    }
}

/// Pure effects in top-left logical coordinates: zero is fully shown, one is fully hidden.
enum DockAnimationGeometry {
    static let margin: CGFloat = 40
    static func sample(style: DockAnimationStyle, progress: Double, size: CGSize, reduceMotion: Bool) -> DockAnimationSample {
        let p = CGFloat(min(1, max(0, progress)))
        let bounds = CGRect(origin: .zero, size: size)
        var result = DockAnimationSample(mask: bounds, anchor: CGPoint(x: size.width / 2, y: size.height - DockGeometry.bottomMargin))
        if reduceMotion { result.opacity = 1 - Double(p); return result }
        switch style {
        case .slideFade: result.offset.height = 24 * p; result.opacity = 1 - Double(p)
        case .slide: result.offset.height = (size.height + margin) * p
        case .fade: result.opacity = 1 - Double(p)
        case .liftFade: result.offset.height = -24 * p; result.opacity = 1 - Double(p)
        case .leftFade: result.offset.width = -32 * p; result.opacity = 1 - Double(p)
        case .rightFade: result.offset.width = 32 * p; result.opacity = 1 - Double(p)
        case .scaleFade: result.scale = 1 - 0.15 * p; result.opacity = 1 - Double(p)
        case .verticalWipe:
            result.mask = CGRect(x: 0, y: result.anchor.y * p, width: size.width, height: result.anchor.y * (1 - p))
        case .horizontalWipe:
            result.mask = CGRect(x: size.width * p / 2, y: 0, width: size.width * (1 - p), height: size.height)
        case .bounceFade:
            if p < 0.2 {
                result.offset.height = -6 * p / 0.2
                result.scale = 1 + 0.04 * p / 0.2
            } else {
                let t = (p - 0.2) / 0.8
                result.offset.height = -6 + 30 * t
                result.scale = 1.04 - 0.19 * t
                result.opacity = 1 - Double(t)
            }
        }
        if p == 0 { result.mask = bounds }
        if p == 1 { result.opacity = 0; result.mask = .zero }
        return result
    }
}
