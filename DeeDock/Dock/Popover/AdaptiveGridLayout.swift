import CoreGraphics

/// Cell size for the folder-stack icon grid. The view and the key handler both read these.
nonisolated enum FolderStackGridMetrics {
    /// `GridItem.Size.adaptive` minimum.
    static let minimumCell: CGFloat = 82
    /// Gap between columns. Row spacing does not change how many columns fit.
    static let columnSpacing: CGFloat = 12
    /// Inset on each side of the grid. `.padding` uses the same value.
    static let horizontalPadding: CGFloat = 16
}

/// Cell size for the Shelf icon grid. The view and the key handler both read these.
nonisolated enum ShelfGridMetrics {
    static let minimumCell: CGFloat = 92
    static let columnSpacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 8
    /// Width of the Shelf popover on a roomy display. Narrow displays use `DockPopoverGeometry.minimumSize`.
    static let idealPanelWidth: CGFloat = 420
}

/// Column count of a `LazyVGrid` that uses one adaptive column, and the index arrows land on.
///
/// SwiftUI picks the largest `n` such that `n * minimum + (n - 1) * spacing` still fits the
/// width offered to the grid. Up and Down move by that `n`, so the selection follows the row
/// on screen instead of a fixed stride.
nonisolated enum AdaptiveGridLayout {
    /// Columns that fit in `width` points.
    static func columnCount(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        guard minimum > 0, width > 0 else { return 1 }
        var count = max(1, Int((width + spacing) / (minimum + spacing)))
        while count > 1, CGFloat(count) * minimum + CGFloat(count - 1) * spacing > width {
            count -= 1
        }
        while CGFloat(count + 1) * minimum + CGFloat(count) * spacing <= width {
            count += 1
        }
        return count
    }

    /// Columns inside a dock popover of `panelWidth`.
    ///
    /// Side docks spend `pointerInset` on the pointer. `horizontalPadding` is the grid inset
    /// on each side, so the grid is narrower than the panel.
    static func columnCount(panelWidth: CGFloat, minimum: CGFloat, spacing: CGFloat,
                            horizontalPadding: CGFloat, pointerInset: CGFloat) -> Int {
        columnCount(width: panelWidth - pointerInset - horizontalPadding * 2, minimum: minimum, spacing: spacing)
    }

    /// Left, right, up, and down (`123`, `124`, `125`, `126`). Horizontal steps are one cell.
    /// Vertical steps are one row. Any other key returns nil.
    static func gridStep(keyCode: UInt16, columns: Int) -> Int? {
        let row = max(columns, 1)
        switch keyCode {
        case 123: return -1
        case 124: return 1
        case 125: return row
        case 126: return -row
        default: return nil
        }
    }

    /// Index after moving `delta` items, staying on the first or last item.
    static func clampedIndex(current: Int, count: Int, delta: Int) -> Int {
        guard count > 0 else { return 0 }
        let base = min(max(current, 0), count - 1)
        return min(max(base + delta, 0), count - 1)
    }
}
