import AppKit
import Foundation

extension DockInteraction {
    /// The line glyph for an application tile, glowing in the app's own colors, or nil when this
    /// dock draws native artwork or the catalog has no glyph for the app.
    func lineIcon(for reference: ApplicationReference, artwork: NSImage) -> DockLineIcon? {
        guard iconStyle == .line, let glyph = LineIconCatalog.shared.glyph(for: reference) else { return nil }
        return DockLineIcon(glyph: glyph, glow: .artwork(artwork))
    }

    /// A fused window's line glyph, matched by bundle identifier and then by app name.
    ///
    /// Nil when this dock draws native artwork or the catalog has no glyph. `bundleIdentifier` is ignored
    /// when it is a path rather than a reverse-DNS id.
    func lineIcon(named name: String, bundleIdentifier: String?, artwork: NSImage) -> DockLineIcon? {
        guard iconStyle == .line else { return nil }
        let identifier = bundleIdentifier.flatMap { $0.contains(".") && !$0.contains("/") ? $0 : nil }
        let url = URL(fileURLWithPath: "/Applications/\(name).app")
        guard let glyph = LineIconCatalog.shared.glyph(bundleIdentifier: identifier, url: url) else { return nil }
        return DockLineIcon(glyph: glyph, glow: .artwork(artwork))
    }

    /// The line glyph for one of DOKK's own tiles, or nil when this dock draws native artwork.
    ///
    /// - Parameter artwork: Glows behind the glyph when given; otherwise the shared spectrum does.
    func lineIcon(for tile: LineIconTile, artwork: NSImage? = nil) -> DockLineIcon? {
        guard iconStyle == .line, let glyph = LineIconCatalog.shared.glyph(for: tile) else { return nil }
        return DockLineIcon(glyph: glyph, glow: artwork.map(DockLineGlow.artwork) ?? .spectrum)
    }
}

extension LineIconTile {
    /// The volume glyph for a mounted volume's kind.
    init(volume kind: VolumeKind) {
        self = switch kind {
        case .removable: .volumeRemovable
        case .network: .volumeNetwork
        case .diskImage: .volumeDiskImage
        case .externalDisk, .timeMachine: .volume
        }
    }
}
