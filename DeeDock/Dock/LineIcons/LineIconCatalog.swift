import CoreGraphics
import Foundation
import Synchronization

/// One white glyph in the 24-point catalog box.
///
/// Lucide and DOKK-drawn glyphs are strokes; Simple Icons brand marks are filled silhouettes, and a
/// few glyphs mix both. `CGPath` is immutable, so sharing a glyph across actors is safe.
nonisolated struct LineIconGlyph: Equatable, @unchecked Sendable {
    /// The catalog reference, such as `lucide:compass`; equal references draw identical glyphs.
    let id: String
    let stroke: CGPath?
    let fill: CGPath?

    /// Brand marks fill their whole box and read heavier than strokes, so they draw slightly smaller.
    var isFilledMark: Bool { stroke == nil }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Dock tiles that are not applications but still get a line glyph.
nonisolated enum LineIconTile: String, CaseIterable, Sendable {
    case launcher, trash, trashFull, folder, shelf, sessionCapsules
    case volume, volumeRemovable, volumeNetwork, volumeDiskImage
}

/// The bundled `LineIcons.json` catalog behind ``DockIconStyle/line``.
///
/// The JSON loads on the first lookup, so docks that keep native artwork never read it. Glyph paths
/// parse once per reference and stay cached for the app's lifetime. Lookups are cheap enough for a
/// SwiftUI `body`, which can run on every pointer move over the dock, and are safe from any thread.
///
/// Applications resolve by bundle identifier first, then by lowercased `.app` name, the same order
/// the launcher's description catalog uses. An unknown app returns nil and keeps its real icon.
nonisolated final class LineIconCatalog: Sendable {
    /// The catalog shipped in the app bundle.
    static let shared = LineIconCatalog {
        Bundle.main.url(forResource: "LineIcons", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }

    private nonisolated struct Document: Decodable, Sendable {
        nonisolated struct Paths: Decodable, Sendable {
            var stroke: [String]?
            var fill: [String]?
        }
        var glyphs: [String: Paths] = [:]
        var bundleIdentifiers: [String: String] = [:]
        var appNames: [String: String] = [:]
        var tiles: [String: String] = [:]
    }

    private nonisolated struct State: Sendable {
        var document: Document?
        /// Nil records a reference whose paths failed to parse, so it is not retried on every lookup.
        var glyphs: [String: LineIconGlyph?] = [:]
    }

    private let load: @Sendable () -> Data?
    private let state = Mutex(State())

    /// - Parameter load: Returns the catalog JSON. It runs at most once, on the first lookup;
    ///   nil or malformed data behaves as an empty catalog.
    init(load: @escaping @Sendable () -> Data?) {
        self.load = load
    }

    /// The glyph for an application, or nil when the catalog has none.
    func glyph(bundleIdentifier: String?, url: URL) -> LineIconGlyph? {
        state.withLock { state in
            let document = loaded(&state)
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            guard let reference = bundleIdentifier.flatMap({ document.bundleIdentifiers[$0] })
                    ?? document.appNames[name] else { return nil }
            return glyph(reference, document: document, state: &state)
        }
    }

    func glyph(for reference: ApplicationReference) -> LineIconGlyph? {
        glyph(bundleIdentifier: reference.bundleIdentifier, url: reference.url)
    }

    /// The glyph for one of DOKK's own tiles, or nil when the catalog has none.
    func glyph(for tile: LineIconTile) -> LineIconGlyph? {
        state.withLock { state in
            let document = loaded(&state)
            guard let reference = document.tiles[tile.rawValue] else { return nil }
            return glyph(reference, document: document, state: &state)
        }
    }

    private func loaded(_ state: inout State) -> Document {
        if let document = state.document { return document }
        let document = load().flatMap { try? JSONDecoder().decode(Document.self, from: $0) } ?? Document()
        state.document = document
        return document
    }

    private func glyph(_ reference: String, document: Document, state: inout State) -> LineIconGlyph? {
        if let cached = state.glyphs[reference] { return cached }
        let glyph = document.glyphs[reference].flatMap { Self.parse($0, id: reference) }
        state.glyphs[reference] = glyph
        return glyph
    }

    private static func parse(_ paths: Document.Paths, id: String) -> LineIconGlyph? {
        func combined(_ list: [String]?) -> (path: CGPath?, valid: Bool) {
            guard let list, !list.isEmpty else { return (nil, true) }
            let path = CGMutablePath()
            for data in list {
                guard let parsed = LineIconPath.parse(data) else { return (nil, false) }
                path.addPath(parsed)
            }
            return (path.copy(), true)
        }
        let stroke = combined(paths.stroke)
        let fill = combined(paths.fill)
        guard stroke.valid, fill.valid, stroke.path != nil || fill.path != nil else { return nil }
        return LineIconGlyph(id: id, stroke: stroke.path, fill: fill.path)
    }
}
