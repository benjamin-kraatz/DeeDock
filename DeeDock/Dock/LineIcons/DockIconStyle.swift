import Foundation

/// How dock tiles draw their artwork.
///
/// `line` swaps each tile's artwork for a bundled white glyph from ``LineIconCatalog`` and adds a
/// colored glow on hover. Tiles without a glyph keep their native artwork, so the dock never shows
/// an empty slot.
nonisolated enum DockIconStyle: String, Codable, CaseIterable, Sendable {
    case native, line
}
