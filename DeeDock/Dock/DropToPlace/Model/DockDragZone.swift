import CoreGraphics

/// What releasing a dragged pin or running tile would do, by distance from the source dock.
///
/// The bands are measured with ``DockDragGeometry/distance(_:outside:)`` from the source dock's
/// resting glass:
/// - under ``DockDragGeometry/removalDistance`` (64 pt): ``near``, so reorder or fly back;
/// - from 64 pt to under ``DockDragGeometry/placeDistance`` (180 pt): ``unpin`` for a pin,
///   ``inert`` for a running-only tile;
/// - 180 pt or more: ``place`` for an application, which takes precedence over unpinning.
///
/// Over any dock that protects removal the drag is always ``near``.
nonisolated enum DockDragZone: Equatable, Sendable {
    case near
    case unpin
    case place
    /// Far enough to leave the dock, but releasing does nothing (a running-only tile in the
    /// Unpin band). The tile flies back.
    case inert

    /// - Parameters:
    ///   - distance: Points from the source dock's resting glass.
    ///   - overDock: Whether a dock protects removal at the pointer.
    ///   - isPinned: Whether the dragged item is a saved pin on the source dock.
    ///   - canPlace: Whether Drop to Place applies: an available application, not a folder.
    static func resolve(distance: CGFloat, overDock: Bool, isPinned: Bool, canPlace: Bool) -> DockDragZone {
        guard !overDock, distance >= DockDragGeometry.removalDistance else { return .near }
        if canPlace, distance >= DockDragGeometry.placeDistance { return .place }
        return isPinned ? .unpin : .inert
    }
}
