// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// One searchable piece of a file. The raw values are what `segments.kind` stores.
nonisolated enum SegmentKind: String, Sendable {
    /// The file name and folder names (keyword search only).
    case name
    /// The image itself.
    case image
    /// Text Apple Vision read from a screenshot (keyword search only: see `Indexer`).
    case ocr
    /// A PDF page's text.
    case page
    /// A PDF page rendered as an image (scans, slides).
    case pageImage = "page_image"
    /// A piece of a document's text.
    case chunk
}
