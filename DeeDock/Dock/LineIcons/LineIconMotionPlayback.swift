import Foundation

/// When a Line glyph plays its ``LineIconMotion``.
///
/// A dock setting with one case per trigger rather than a switch, so a launch trigger can join
/// later without migrating saved documents. Reduce Motion keeps every glyph still whatever the
/// case, without rewriting the saved preference.
nonisolated enum LineIconMotionPlayback: String, Codable, CaseIterable, Sendable {
    /// Glyphs never move.
    case off
    /// A glyph plays once when the pointer or keyboard selection rests on its tile.
    case hover

    /// Whether a highlighted tile sets its glyph moving.
    var playsOnHover: Bool { self == .hover }
}
