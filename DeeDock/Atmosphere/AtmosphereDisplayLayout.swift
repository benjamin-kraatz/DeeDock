import Foundation
import CoreGraphics

/// A panorama uses AppKit points across one contiguous row. Gaps, overlapping screens,
/// unequal vertical extents, and L-shaped layouts retain independent display edges.
enum AtmosphereDisplayLayout {
    static func isContinuousRow(_ displays: [DisplaySnapshot]) -> Bool {
        let ordered = displays.sorted { $0.frame.minX < $1.frame.minX }
        guard let first = ordered.first, ordered.count > 1 else { return false }
        return ordered.allSatisfy { abs($0.frame.minY - first.frame.minY) < 1 && abs($0.frame.height - first.frame.height) < 1 }
            && zip(ordered, ordered.dropFirst()).allSatisfy { abs($0.frame.maxX - $1.frame.minX) < 1 }
    }

    /// Quartz measures down from the primary screen's top; AppKit measures up.
    /// This conversion preserves displays with negative origins on either axis.
    static func quartzFrame(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }
}
