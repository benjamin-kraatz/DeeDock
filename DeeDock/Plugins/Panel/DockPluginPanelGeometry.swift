import CoreGraphics

/// The size of a plugin's panel, from the content size the plugin asks for.
///
/// DOKK owns the panel's frame: the remote scene reports no usable preferred size (the plugin
/// spike saw `preferredContentSize` stay zero), so the plugin states one in its tile state. DOKK
/// adds its header and the pointer, then keeps the result between the shared popover minimum
/// (280 × 220) and the popover default (560 × 420). ``DockPopoverGeometry`` then fits it on screen.
enum DockPluginPanelGeometry {
    /// The bar above the plugin's content with its icon, name, and More button.
    static let headerHeight: CGFloat = 40

    /// - Parameters:
    ///   - content: The plugin's requested content size, or nil for the popover default.
    ///   - edge: The dock's edge. The pointer adds depth across the side that faces the dock: height
    ///     for a bottom or top dock, width for a side dock.
    static func panelSize(content: CGSize?, edge: DockEdge) -> CGSize {
        let minimum = DockPopoverGeometry.minimumSize
        let maximum = DockPopoverGeometry.idealSize
        guard let content, content.width.isFinite, content.height.isFinite,
              content.width > 0, content.height > 0 else { return maximum }
        var size = CGSize(width: content.width, height: content.height + headerHeight)
        if edge.isVertical { size.width += DockPopoverGeometry.pointerDepth }
        else { size.height += DockPopoverGeometry.pointerDepth }
        return CGSize(width: min(maximum.width, max(minimum.width, size.width)),
                      height: min(maximum.height, max(minimum.height, size.height)))
    }

    /// The panel size for a plugin's tile state.
    static func panelSize(for state: DOKKPluginTileState?, edge: DockEdge) -> CGSize {
        panelSize(content: state?.panelSize.map { CGSize(width: $0.width, height: $0.height) }, edge: edge)
    }
}
