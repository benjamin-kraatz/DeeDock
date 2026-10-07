import AppKit

extension LauncherState {
    /// The line glyph for an application tile, glowing in the app's own colors, or nil when this
    /// Launcher draws native artwork or the catalog has no glyph for the app.
    ///
    /// - Parameter artwork: The app's native icon; nil while it is still loading, which falls back
    ///   to the shared spectrum glow.
    func lineIcon(for application: LauncherApplication, artwork: NSImage?) -> DockLineIcon? {
        guard usesLineIcons, let glyph = LineIconCatalog.shared.glyph(for: application.reference) else { return nil }
        return DockLineIcon(glyph: glyph, glow: artwork.map(DockLineGlow.artwork) ?? .spectrum, motion: lineIconMotion)
    }
}
