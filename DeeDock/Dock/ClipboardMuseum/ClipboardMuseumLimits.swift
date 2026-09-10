import Foundation

/// Bounds that keep a long-running clipboard collection small and quick to load.
nonisolated enum ClipboardMuseumLimits {
    /// Oldest exhibits leave the collection past this count, with their image files.
    static let maximumExhibits = 200
    /// Longer text is cut here before it is stored. Settings copy quotes this number.
    static let maximumTextCharacters = 20_000
    /// File copies beyond this count keep only the first paths.
    static let maximumFiles = 50
    /// Image payloads larger than this are skipped rather than decoded.
    static let maximumImageInputBytes = 32 * 1_048_576
    /// Guards against decompression bombs before ImageIO allocates a full frame.
    static let maximumImagePixels = 40_000_000
    /// Stored images are downsampled so the longest side fits this many pixels.
    static let maximumImageDimension = 2_048
    /// Collection files larger than this are treated as corrupt rather than loaded.
    static let maximumDocumentBytes = 16 * 1_048_576
    /// Pasteboard change-count check interval while collecting is on.
    static let pollInterval: TimeInterval = 0.75
}
