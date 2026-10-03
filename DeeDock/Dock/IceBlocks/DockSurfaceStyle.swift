import Foundation

/// How the dock paints its background and running markers.
///
/// `iceBlocks` is an evaluation look. It gives each dock section its own tinted glass block
/// and draws its own running marker, so it ignores the running indicator style and the
/// divider lines between sections. Geometry, hit regions, and every other preference are shared.
enum DockSurfaceStyle: String, Codable, CaseIterable {
    case glass, iceBlocks
}
