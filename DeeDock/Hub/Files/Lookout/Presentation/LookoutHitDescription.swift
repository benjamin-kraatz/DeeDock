import Foundation

/// What a Lookout hit is, for its kind chip, the "why it matched" sentence and analytics.
nonisolated enum LookoutHitKind: Equatable, Sendable {
    case picture
    case screenshot
    /// A PDF, with the page the hit points at when it points at one.
    case pdf(page: Int?)
    case document
    /// A folder whose files match, with how many do.
    case folder(matchingFiles: Int)

    init(_ hit: LookoutHit) {
        if let folder = hit.folder {
            self = .folder(matchingFiles: folder.matchingFiles)
            return
        }
        switch hit.kind {
        case .image: self = .picture
        case .screenshot: self = .screenshot
        case .pdf: self = .pdf(page: hit.page)
        case .doc, nil: self = .document
        }
    }

    /// The kind chip: "Picture", "PDF · Page 7", "Folder · 6 matching files".
    var title: String {
        switch self {
        case .picture: String(localized: .lookoutKindPicture)
        case .screenshot: String(localized: .lookoutKindScreenshot)
        case .pdf(let page?): String(localized: .lookoutKindPDFPage(page))
        case .pdf(nil): String(localized: .lookoutKindPDF)
        case .document: String(localized: .lookoutKindDocument)
        case .folder(let count): String(localized: .lookoutKindFolder(count))
        }
    }
}

extension LookoutHit.Match {
    /// The match chip: "Meaning", "Exact words", "Meaning + words".
    nonisolated var title: String {
        switch self {
        case .meaning: String(localized: .lookoutMatchMeaning)
        case .words: String(localized: .lookoutMatchWords)
        case .both: String(localized: .lookoutMatchBoth)
        }
    }
}

/// The preview's "Why it matched" sentence, chosen from what matched (meaning, words, both), what the hit is, and
/// the page. The cases are the sentences; `text` localizes them.
nonisolated struct LookoutWhy: Equatable, Sendable {
    enum Sentence: Equatable, Sendable {
        case pageMeaning(Int), pageWords(Int), pageBoth(Int)
        case pictureMeaning, pictureBoth
        case screenshotMeaning, screenshotBoth
        case passageMeaning, passageBoth
        /// Words alone, for anything but a page.
        case words
        case folder(matchingFiles: Int)
    }

    let sentence: Sentence
    /// A lookup query (codes, IDs, long numbers), where words counted double: the card says so after the sentence.
    let explainsLookup: Bool

    init(hit: LookoutHit, isLookup: Bool) {
        let kind = LookoutHitKind(hit)
        sentence = Self.sentence(kind: kind, match: hit.match)
        if case .folder = kind {
            explainsLookup = false
        } else {
            explainsLookup = isLookup && hit.match != .meaning
        }
    }

    private static func sentence(kind: LookoutHitKind, match: LookoutHit.Match) -> Sentence {
        switch (kind, match) {
        case (.folder(let count), _): .folder(matchingFiles: count)
        case (.pdf(let page?), .meaning): .pageMeaning(page)
        case (.pdf(let page?), .words): .pageWords(page)
        case (.pdf(let page?), .both): .pageBoth(page)
        case (_, .words): .words
        case (.picture, .meaning): .pictureMeaning
        case (.picture, .both): .pictureBoth
        case (.screenshot, .meaning): .screenshotMeaning
        case (.screenshot, .both): .screenshotBoth
        case (_, .meaning): .passageMeaning
        case (_, .both): .passageBoth
        }
    }

    /// The localized sentence, with the lookup note when it applies.
    var text: String {
        let main: String = switch sentence {
        case .pageMeaning(let page): String(localized: .lookoutWhyPageMeaning(page))
        case .pageWords(let page): String(localized: .lookoutWhyPageWords(page))
        case .pageBoth(let page): String(localized: .lookoutWhyPageBoth(page))
        case .pictureMeaning: String(localized: .lookoutWhyPictureMeaning)
        case .pictureBoth: String(localized: .lookoutWhyPictureBoth)
        case .screenshotMeaning: String(localized: .lookoutWhyScreenshotMeaning)
        case .screenshotBoth: String(localized: .lookoutWhyScreenshotBoth)
        case .passageMeaning: String(localized: .lookoutWhyPassageMeaning)
        case .passageBoth: String(localized: .lookoutWhyPassageBoth)
        case .words: String(localized: .lookoutWhyWords)
        case .folder(let count): String(localized: .lookoutWhyFolder(count))
        }
        return explainsLookup ? main + " " + String(localized: .lookoutWhyLookup) : main
    }
}
