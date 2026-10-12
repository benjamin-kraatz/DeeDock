import Foundation

/// "Why it matched" for a result of a search with a picture or Find Similar (the mockup's `previewImgHTML`): one
/// sentence from what the result is and what was searched with, and how close it is in three steps. Pure.
nonisolated struct LookoutPictureWhy: Equatable, Sendable {
    enum Sentence: Equatable, Sendable {
        /// A picture found with a picture.
        case alike
        /// A document (or a page) found with a picture.
        case about(page: Int?)
        /// A picture found with a document.
        case pictureOf
        /// A document (or a page) found with a document.
        case says(page: Int?)
    }

    /// The three-step meter, from how far the result stands out (its z): 4 and up is very close, 3 and up close, the
    /// rest (still past the 2.0 gate) somewhat alike.
    enum Closeness: Int, Equatable, Sendable, CaseIterable {
        case somewhat = 1, close, veryClose

        init(z: Double) {
            self = z >= 4 ? .veryClose : z >= 3 ? .close : .somewhat
        }

        var title: String {
            switch self {
            case .somewhat: String(localized: .lookoutPictureSomewhat)
            case .close: String(localized: .lookoutPictureClose)
            case .veryClose: String(localized: .lookoutPictureVeryClose)
            }
        }
    }

    let sentence: Sentence
    let closeness: Closeness
    /// The result is a picture or screenshot (its side of the comparison shows its thumbnail, not a page).
    let resultIsPicture: Bool

    init(hit: LookoutHit, queryIsPicture: Bool) {
        let picture = hit.kind == .image || hit.kind == .screenshot
        resultIsPicture = picture
        closeness = Closeness(z: hit.z ?? hit.score)
        switch (picture, queryIsPicture) {
        case (true, true): sentence = .alike
        case (true, false): sentence = .pictureOf
        case (false, true): sentence = .about(page: hit.page)
        case (false, false): sentence = .says(page: hit.page)
        }
    }

    var text: String {
        switch sentence {
        case .alike: String(localized: .lookoutPictureWhyAlike)
        case .pictureOf: String(localized: .lookoutPictureWhyPictureOf)
        case .about(let page?): String(localized: .lookoutPictureWhyAboutPage(page))
        case .about(nil): String(localized: .lookoutPictureWhyAbout)
        case .says(let page?): String(localized: .lookoutPictureWhySaysPage(page))
        case .says(nil): String(localized: .lookoutPictureWhySays)
        }
    }

    /// The match chip on a result row: "Looks alike" for a picture (or a folder of them) found with a picture,
    /// "Same subject" for the rest.
    static func matchTitle(hit: LookoutHit, group: LookoutSimilarResults.GroupKind, queryIsPicture: Bool) -> String {
        hit.isFolder || (group == .pictures && queryIsPicture)
            ? String(localized: .lookoutPictureMatchAlike) : String(localized: .lookoutPictureMatchSame)
    }
}
