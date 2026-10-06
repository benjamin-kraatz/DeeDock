import CoreGraphics

/// Fixed measurements of the compact Launcher.
///
/// The panel keeps one size for its whole presentation, so typing never resizes or re-anchors it.
/// Rows past ``visibleRows`` scroll.
nonisolated enum CompactLauncherLayout {
    static let columns = 6
    static let visibleRows = 4
    static let iconSize: CGFloat = 52
    static let tileWidth: CGFloat = 96
    static let tileHeight: CGFloat = 92
    static let spacing: CGFloat = 6
    static let padding: CGFloat = 16
    static let headerHeight: CGFloat = 52

    /// The panel size handed to ``DockPopoverGeometry``, pointer included. The geometry still
    /// shrinks it to fit small screens.
    static var idealSize: CGSize {
        let columns = CGFloat(columns), rows = CGFloat(visibleRows)
        let width = columns * tileWidth + (columns - 1) * spacing + padding * 2
        let grid = rows * tileHeight + (rows - 1) * spacing
        return CGSize(width: width, height: headerHeight + grid + padding * 2 + DockPopoverGeometry.pointerDepth)
    }
}
