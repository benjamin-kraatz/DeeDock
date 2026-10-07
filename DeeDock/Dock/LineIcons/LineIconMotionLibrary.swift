import Foundation
import Synchronization

/// The bundled `LineIconMotions.json`: which choreography each line glyph plays.
///
/// A glyph with its own entry plays that. Every other glyph plays one of the shared fallbacks for
/// its kind, picked by a stable hash of its reference so the same app always moves the same way.
/// The file is hand-written; `scripts/line-icons/motion-gallery.py` previews it in a browser.
///
/// The JSON loads on the first lookup, and a motion that fails to decode is skipped rather than
/// taking the rest of the file with it. Lookups are cheap enough for a SwiftUI `body` and safe from
/// any thread.
nonisolated final class LineIconMotionLibrary: Sendable {
    /// The library shipped in the app bundle.
    static let shared = LineIconMotionLibrary {
        Bundle.main.url(forResource: "LineIconMotions", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }

    /// Decodes to nil instead of throwing, so one malformed motion costs only itself.
    private nonisolated struct Lenient: Decodable, Sendable {
        let motion: LineIconMotion?
        nonisolated init(from decoder: Decoder) throws { motion = try? LineIconMotion(from: decoder) }
    }

    private nonisolated struct Document: Decodable, Sendable {
        nonisolated struct Fallbacks: Decodable, Sendable {
            var stroke: [Lenient]?
            var fill: [Lenient]?
        }
        var motions: [String: Lenient]?
        var fallbacks: Fallbacks?
    }

    private nonisolated struct Contents: Sendable {
        var motions: [String: LineIconMotion] = [:]
        var strokeFallbacks: [LineIconMotion] = []
        var fillFallbacks: [LineIconMotion] = []
    }

    private let load: @Sendable () -> Data?
    private let contents = Mutex<Contents?>(nil)

    /// - Parameter load: Returns the library JSON. It runs at most once, on the first lookup;
    ///   nil or malformed data behaves as an empty library.
    init(load: @escaping @Sendable () -> Data?) {
        self.load = load
    }

    /// The motion `glyph` plays, or nil when the library has neither an entry nor a fallback for it.
    func motion(for glyph: LineIconGlyph) -> LineIconMotion? {
        contents.withLock { contents in
            let loaded = contents ?? read()
            contents = loaded
            if let motion = loaded.motions[glyph.id] { return motion }
            let pool = glyph.isFilledMark ? loaded.fillFallbacks : loaded.strokeFallbacks
            return pool.isEmpty ? nil : pool[Int(Self.stableHash(glyph.id) % UInt32(pool.count))]
        }
    }

    private func read() -> Contents {
        guard let document = load().flatMap({ try? JSONDecoder().decode(Document.self, from: $0) }) else { return Contents() }
        return Contents(motions: (document.motions ?? [:]).compactMapValues(\.motion),
                        strokeFallbacks: (document.fallbacks?.stroke ?? []).compactMap(\.motion),
                        fillFallbacks: (document.fallbacks?.fill ?? []).compactMap(\.motion))
    }

    /// FNV-1a over the UTF-8 bytes. `Hasher` is seeded per launch, which would reshuffle the
    /// fallbacks every time DOKK starts.
    static func stableHash(_ text: String) -> UInt32 {
        text.utf8.reduce(2_166_136_261) { ($0 ^ UInt32($1)) &* 16_777_619 }
    }
}
