import SwiftUI

extension EnvironmentValues {
    /// Whether the pointer is over this dock tile. `DockSurfaceView` sets it per entry from the same
    /// hover state the tooltips use; line glyphs read it to show their glow.
    @Entry var dockTileHovered = false
}
