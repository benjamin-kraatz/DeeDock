import CoreGraphics

/// Converts display frames between AppKit and Quartz global coordinates.
enum DisplayQuartzFrame {
    /// Returns an AppKit screen frame in the Quartz space used by `CGWindowListCopyWindowInfo` bounds.
    ///
    /// Quartz measures down from the primary screen's top; AppKit measures up from its bottom.
    /// Only the vertical axis flips, so displays with negative origins on either axis keep their
    /// position relative to the primary screen.
    ///
    /// - Parameters:
    ///   - frame: A global AppKit frame in points.
    ///   - primaryTop: The primary screen's `frame.maxY` in AppKit points.
    static func quartzFrame(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }
}
