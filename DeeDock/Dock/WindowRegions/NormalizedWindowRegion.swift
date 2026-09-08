import CoreGraphics
import Foundation

/// Unit coordinates measured from the preview's top-left, independent of screen origin and scale.
nonisolated struct NormalizedWindowRegion: Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 1
    var height: Double = 1

    /// The values displayed to the user and used by the crop must describe the same bounded rectangle.
    var clamped: Self {
        let rect = rect
        return Self(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    var rect: CGRect {
        CGRect(x: min(max(x, 0), 0.95), y: min(max(y, 0), 0.95),
               width: min(max(width, 0.05), 1 - min(max(x, 0), 0.95)),
               height: min(max(height, 0.05), 1 - min(max(y, 0), 0.95)))
    }
}

