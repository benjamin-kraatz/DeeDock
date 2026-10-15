// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// What a file is, for indexing and for grouping results.
///
/// Lookout indexes these four only. Audio and video are ignored (Spotlight still finds them by name), and code isn't
/// indexed (`Rules` skips it, as DigUp does without its code index).
nonisolated enum FileKind: String, CaseIterable, Sendable, Codable {
    case screenshot, image, pdf, doc

    /// The tie-break of the first pass's order, after recency (`IndexStore.pendingOrderSQL`): what people look for
    /// most comes first.
    static let kindOrderSQL = """
        CASE kind WHEN 'screenshot' THEN 0 WHEN 'image' THEN 1 WHEN 'pdf' THEN 2 WHEN 'doc' THEN 3 ELSE 4 END
        """
}
