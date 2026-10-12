import AppKit

/// The picture a Files search is searching with, as the search field's chip and the results bar show it.
struct LookoutPictureQuery: Identifiable, Equatable {
    /// Where the picture came from.
    enum Origin: Equatable {
        /// Dropped on the search field (or a copied picture file, pasted).
        case dropped(URL)
        /// Picture bytes pasted from the pasteboard.
        case pasted
        /// Find Similar on a result: a file in the index, by its path, or a picture read like a dropped one when the
        /// index doesn't hold it.
        case similar(URL)
    }

    let id: UUID
    let origin: Origin
    /// The file's name, or "Pasted picture".
    let name: String
    /// A small picture of it for the chip and the results bar: a pasted picture's own pixels. Files draw their
    /// thumbnail through Quick Look instead (`fileURL`).
    let image: NSImage?
    /// What it searches with, for `LookoutPictureSearch`.
    let input: LookoutPictureInput

    /// The file the picture is, when it is one.
    var fileURL: URL? {
        switch origin {
        case .dropped(let url), .similar(let url): url
        case .pasted: nil
        }
    }

    /// How the person started the search, for `lookout_image_search`.
    let analyticsSource: AnalyticsLookoutImageSource

    init(origin: Origin, name: String, image: NSImage? = nil, input: LookoutPictureInput,
         analyticsSource: AnalyticsLookoutImageSource, id: UUID = UUID()) {
        self.id = id
        self.origin = origin
        self.name = name
        self.image = image
        self.input = input
        self.analyticsSource = analyticsSource
    }

    /// A picture file dropped on the field, or copied in Finder and pasted (`via: .paste`).
    static func dropped(_ url: URL, via source: AnalyticsLookoutImageSource = .drop) -> LookoutPictureQuery {
        LookoutPictureQuery(origin: .dropped(url), name: url.lastPathComponent, input: .file(url),
                            analyticsSource: source)
    }

    /// Picture bytes: pasted, or dragged out of an app that offers no file (`via: .drop`).
    static func pasted(_ data: Data, image: NSImage?, via source: AnalyticsLookoutImageSource = .paste)
        -> LookoutPictureQuery {
        LookoutPictureQuery(origin: .pasted, name: String(localized: .lookoutPicturePasted), image: image,
                            input: .data(data), analyticsSource: source)
    }

    /// Find Similar on the file at `url`: its stored vector (`segmentID` preferred), or, for a picture the index
    /// doesn't hold, the picture read like a dropped one.
    static func similar(_ url: URL, segmentID: Int64?, isPicture: Bool) -> LookoutPictureQuery {
        LookoutPictureQuery(origin: .similar(url), name: url.lastPathComponent,
                            input: .indexed(path: url.path, segmentID: segmentID, fallback: isPicture ? url : nil),
                            analyticsSource: .similar)
    }

    static func == (lhs: LookoutPictureQuery, rhs: LookoutPictureQuery) -> Bool { lhs.id == rhs.id }
}
