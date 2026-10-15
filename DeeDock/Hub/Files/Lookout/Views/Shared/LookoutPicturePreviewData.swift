import Foundation

/// Deterministic results of searches with a picture for previews, after the mockup's samples
/// (`docs/mockups/lookout-image-search.html`): a beach photo dropped from the Desktop, a pasted screenshot, and Find
/// Similar on page 7 of a lease. Nothing here reads a file, the index, or a service.
@MainActor
enum LookoutPicturePreviewData {
    private static let home = "/Users/benn"

    static let dropped = LookoutPictureQuery.dropped(URL(filePath: home + "/Desktop/IMG_5012.HEIC"))
    static let pasted = LookoutPictureQuery.pasted(Data(), image: nil)
    static let similarLease = LookoutPictureQuery.similar(
        URL(filePath: home + "/Documents/Home/Mietvertrag_Wohnung_Kreuzberg.pdf"), segmentID: nil, isPicture: false)

    /// The beach photo: four pictures and their folder that look like it (one weaker), and two documents about it.
    static let beachResults = LookoutSimilarResults(queryIsPicture: true, groups: [
        LookoutSimilarResults.Group(kind: .pictures, strong: [
            hit("/Desktop/Holiday Sylt 2026/IMG_4821.HEIC", kind: .image, z: 5.1, segment: .image),
            hit("/Desktop/Holiday Sylt 2026/IMG_4790.HEIC", kind: .image, z: 4.2, segment: .image),
            LookoutPreviewData.sylt,
            hit("/Desktop/Holiday Sylt 2026/IMG_4802.HEIC", kind: .image, z: 3.6, segment: .image),
            hit("/Desktop/Holiday Sylt 2026/IMG_4811.HEIC", kind: .image, z: 2.9, segment: .image),
        ], weak: [
            hit("/Documents/Family/Fynn’s birthday.jpg", kind: .image, z: 2.2, segment: .image),
        ]),
        LookoutSimilarResults.Group(kind: .documents, strong: [
            hit("/Documents/Home/Ferienwohnung Dünenblick.pdf", kind: .pdf, z: 3.0, segment: .page, loc: 1,
                excerpt: "Ferienwohnung „Dünenblick“, Westerland · 200 m zum Strand · Hunde willkommen"),
            hit("/Documents/Dog walking schedule.numbers", kind: .doc, z: 2.3, segment: .chunk, loc: 0,
                excerpt: "Mon–Fri 7:30, beach loop with Bruno · Sat: long walk at the dunes"),
        ]),
    ])

    /// Page 7 of the lease: documents that say something similar first, and no pictures of it.
    static let leaseResults = LookoutSimilarResults(queryIsPicture: false, groups: [
        LookoutSimilarResults.Group(kind: .documents, strong: [
            hit("/Documents/Home/Hausordnung.pdf", kind: .pdf, z: 3.4, segment: .page, loc: 2,
                excerpt: "Tiere sind im Treppenhaus an der Leine zu führen."),
            hit("/Documents/Home/Lease renewal notes.md", kind: .doc, z: 3.1, segment: .chunk, loc: 0,
                excerpt: "Ask landlord whether the cat counts under the pet clause before signing."),
        ], weak: [
            hit("/Documents/Insurance/Haftpflicht Hund Police.pdf", kind: .pdf, z: 2.2, segment: .page, loc: 3,
                excerpt: "Tierhalterhaftpflicht für einen Hund … Mietsachschäden mitversichert."),
        ]),
        LookoutSimilarResults.Group(kind: .pictures),
    ])

    /// The lease's page 7 as Find Similar reuses it from the index, for "From your index · Page 7 · instant".
    static let leaseSource = LookoutSimilarSource(vector: [], modality: .text, segment: .page, page: 7,
                                                  path: similarLease.fileURL?.path ?? "")

    /// A Files model searching with `picture`, Lookout overridden to `status`, `phase`, `results` and `seconds`.
    /// Find Similar on the lease reads as reused from the index (`leaseSource`).
    static func model(picture: LookoutPictureQuery, status: LookoutStatus = .ready,
                      phase: LookoutPictureSearch.Phase = .done,
                      results: LookoutSimilarResults = LookoutSimilarResults(queryIsPicture: true),
                      seconds: Double? = 0.35, wordsBefore: String = "",
                      configure: (HubFilesModel) -> Void = { _ in }) -> HubFilesModel {
        HubFilesModel.preview { model in
            model.previewOverrides.lookoutStatus = status
            model.previewOverrides.picturePhase = phase
            model.previewOverrides.pictureResults = results
            model.previewOverrides.pictureReadSeconds = seconds
            if picture == similarLease { model.previewOverrides.pictureStoredSource = leaseSource }
            model.query = wordsBefore
            model.searchWithPicture(picture)
            model.lookoutSelection = results.groups.first?.strong.first?.path
            configure(model)
        }
    }

    private static func hit(_ relative: String, kind: FileKind, z: Double, segment: SegmentKind, loc: Double? = nil,
                            excerpt: String? = nil) -> LookoutHit {
        LookoutHit(path: home + relative, kind: kind, folder: nil, score: z, z: z, cosine: nil, coverage: 0,
                   keywordRank: nil, match: .meaning, segment: segment, segmentID: nil, loc: loc, locEnd: loc,
                   snippet: nil, excerpt: excerpt, modified: 1_786_874_400, size: 2_900_000, info: [:])
    }
}
