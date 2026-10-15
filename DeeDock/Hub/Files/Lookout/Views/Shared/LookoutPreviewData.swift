import Foundation

/// Deterministic Lookout results for previews, modeled on the mockup's sample queries ("dog on the beach", "pets in
/// the lease", "payment declined", "K7Q2LM"). Paths are under `HubFilesPreviewData.home`; nothing here touches the
/// index, the XPC services or the files.
@MainActor
enum LookoutPreviewData {
    /// 16 Aug 2026, 10:00 UTC, and days before it, so dates read the same in every preview.
    private static let august16: Double = 1_786_874_400
    private static func day(_ daysBefore: Double) -> Double { august16 - daysBefore * 86_400 }

    static let beach = hit("/Users/benn/Desktop/Holiday Sylt 2026/IMG_4821.HEIC", kind: .image, score: 5.8, match: .meaning,
                           segment: .image, modified: day(0), size: 3_100_000)
    static let beach2 = hit("/Users/benn/Desktop/Holiday Sylt 2026/IMG_4790.HEIC", kind: .image, score: 4.9,
                            match: .meaning, segment: .image, modified: day(1), size: 2_800_000)
    static let beach3 = hit("/Users/benn/Desktop/Holiday Sylt 2026/IMG_4802.HEIC", kind: .image, score: 4.1,
                            match: .meaning, segment: .image, modified: day(1), size: 2_900_000)
    static let beach4 = hit("/Users/benn/Desktop/Holiday Sylt 2026/IMG_4811.HEIC", kind: .image, score: 2.6,
                            match: .meaning, segment: .image, modified: day(0), size: 3_000_000)
    static let receipt = hit("/Users/benn/Downloads/Fressnapf receipt.pdf", kind: .pdf, score: 2.2, match: .both,
                             segment: .page, loc: 1, snippet: "1× Trockenfutter für «Hunde», 12 kg … 2× Kauknochen",
                             modified: day(-17), size: 64_000)
    static let sylt = LookoutHit(
        path: "/Users/benn/Desktop/Holiday Sylt 2026", kind: nil,
        folder: .init(matchingFiles: 4, topFiles: [beach.path, beach2.path, beach3.path]),
        score: 5.2, z: 4.8, cosine: nil, coverage: 0, keywordRank: nil, match: .meaning, segment: nil, segmentID: nil,
        loc: nil, locEnd: nil, snippet: nil, excerpt: nil, modified: nil, size: nil, info: [:])

    static let lease = hit("/Users/benn/Documents/Home/Mietvertrag_Wohnung_Kreuzberg.pdf", kind: .pdf, score: 4.4,
                           match: .meaning, segment: .page, loc: 7,
                           excerpt: "§ 12 Tierhaltung: Die Haltung von Hunden und Katzen bedarf der vorherigen schriftlichen Zustimmung des Vermieters …",
                           modified: day(533), size: 1_800_000)
    static let leaseNotes = hit("/Users/benn/Documents/Home/Lease renewal notes.md", kind: .doc, score: 3.6, match: .both,
                                segment: .chunk, loc: 0,
                                snippet: "Ask landlord whether the cat counts under the «pet» clause before signing.",
                                modified: day(-48), size: 6_000)
    static let houseRules = hit("/Users/benn/Documents/Home/Hausordnung.pdf", kind: .pdf, score: 2.1, match: .meaning,
                                segment: .page, loc: 2, excerpt: "Tiere sind im Treppenhaus an der Leine zu führen.",
                                modified: day(533), size: 340_000)

    static let screenshot = hit("/Users/benn/Desktop/Screenshots/Screenshot 2026-10-02 at 14.12.33.png", kind: .screenshot,
                                score: 4.1, match: .words, segment: .ocr,
                                snippet: "Your card was declined. «Payment» «declined» (card_declined). Try another card.",
                                modified: day(-47), size: 412_000)
    static let invoice = hit("/Users/benn/Downloads/Invoice_October.pdf", kind: .pdf, score: 4.6, match: .words,
                             segment: .page, loc: 1, snippet: "Invoice no. «K7Q2LM» · due 31 Oct 2026 · 1,450.00 €",
                             modified: day(-51), size: 88_000)

    /// "dog on the beach": pictures, the folder they're in, and a receipt among the weaker matches.
    static let beachResults = results(strong: [beach, beach2, sylt, beach3], weak: [beach4, receipt],
                                      terms: ["dog", "beach"])
    /// "pets in the lease": a PDF page by meaning, a note by both, one weaker page.
    static let leaseResults = results(strong: [lease, leaseNotes], weak: [houseRules], terms: ["pets", "lease"])
    /// "payment declined" before the query vector arrives: the screenshot by its words only.
    static let keywordResults = results(strong: [screenshot], weak: [], terms: ["payment", "declined"], usedMeaning: false)

    /// A Files model searching `query` with Lookout overridden to `status`, `phase` and `results`, and `names` as
    /// Spotlight's results. Uses `HubFilesModel.preview` (a throwaway defaults suite) and its inert Lookout engine.
    static func model(status: LookoutStatus, phase: LookoutSearch.Phase, results: LookoutResultSet = .empty,
                      query: String = "dog", names: [HubFileItem] = [],
                      configure: (HubFilesModel) -> Void = { _ in }) -> HubFilesModel {
        HubFilesModel.preview { model in
            model.previewOverrides.searchResults = names
            model.previewOverrides.lookoutStatus = status
            model.previewOverrides.lookoutPhase = phase
            model.previewOverrides.lookoutResults = results
            model.query = query
            configure(model)
        }
    }

    private static func results(strong: [LookoutHit], weak: [LookoutHit], terms: [String],
                                usedMeaning: Bool = true) -> LookoutResultSet {
        var set = LookoutResultSet()
        set.strong = strong
        set.weak = weak
        set.terms = terms
        set.usedMeaning = usedMeaning
        return set
    }

    private static func hit(_ path: String, kind: FileKind, score: Double, match: LookoutHit.Match,
                            segment: SegmentKind, loc: Double? = nil, snippet: String? = nil, excerpt: String? = nil,
                            modified: Double, size: Int64) -> LookoutHit {
        LookoutHit(path: path, kind: kind, folder: nil, score: score, z: match == .words ? nil : score - 1,
                   cosine: nil, coverage: match == .meaning ? 0 : 1, keywordRank: match == .meaning ? nil : 1,
                   match: match, segment: segment, segmentID: nil, loc: loc, locEnd: loc, snippet: snippet,
                   excerpt: excerpt ?? snippet?.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: ""),
                   modified: modified, size: size, info: [:])
    }
}
