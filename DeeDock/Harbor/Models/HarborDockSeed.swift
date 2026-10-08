import AppKit

/// Where a display's dock was drawn the instant Harbor opened, so the running-apps strip can
/// start as a copy of the dock and transform into itself rather than fade in beside it.
///
/// All frames are in the Harbor panel's top-left, y-down coordinates. A seed is only a picture
/// of the dock: the strip draws the icons it names, the backdrop covers the real dock, and
/// nothing here keeps the dock from hiding or changing while Harbor is open.
struct HarborDockSeed: Equatable {
    /// One tile as the dock showed it.
    struct Tile: Identifiable, Equatable {
        enum Kind: Equatable {
            /// An app pin or running app. `running` decides whether it survives the transform.
            case app(appID: String, running: Bool)
            /// DOKK's own Harbor tile, which stays and lights up.
            case harbor
            /// Folders, Trash, Shelf, and other tiles that collapse while Harbor is open.
            case other
        }

        /// The dock entry's hit identifier, stable across the transform.
        let id: String
        let kind: Kind
        /// The icon square the dock drew, which may be magnified.
        let frame: CGRect
        /// Nil for tiles the strip cannot redraw, such as a Focus timer; they dim away under the backdrop.
        let icon: NSImage?
    }

    /// The painted glass behind the tiles. The strip's own glass fades in over it while the
    /// backdrop covers the real one, so the two are never both fully visible.
    let glass: CGRect
    let cornerRadius: CGFloat
    let tiles: [Tile]

    func tile(for id: String) -> Tile? { tiles.first { $0.id == id } }
}
