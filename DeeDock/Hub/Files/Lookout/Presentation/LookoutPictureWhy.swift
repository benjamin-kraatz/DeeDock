import Foundation

/// "Why it matched" for a result of a search with a picture or Find Similar (the mockup's `previewImgHTML`): one
/// sentence from what the result is and what was searched with, and how close it is in three steps. With words typed
/// beside the picture (DEE-126), a second sentence says how they fit, and a file only the words found says so
/// instead of claiming a likeness. Pure.
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
        /// Found by the typed words alone: nothing about it stands out next to the picture.
        case wordsOnly
    }

    /// How the words typed beside the picture fit a result that also matched in meaning.
    enum WordsNote: Equatable, Sendable {
        /// Its name or text has them (`LookoutHit.Match.both`).
        case found
        /// They shaped its meaning match: "It also fits “at night”."
        case fits(String)
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
    /// How the typed words fit; nil without words, and for a file only the words found.
    let wordsNote: WordsNote?

    /// - Parameter words: The words typed beside the picture (`LookoutSimilarResults.words`); empty for none.
    init(hit: LookoutHit, queryIsPicture: Bool, words: String = "") {
        let picture = hit.kind == .image || hit.kind == .screenshot
        resultIsPicture = picture
        closeness = Closeness(z: hit.z ?? hit.score)
        if hit.match == .words {
            sentence = .wordsOnly
            wordsNote = nil
            return
        }
        switch (picture, queryIsPicture) {
        case (true, true): sentence = .alike
        case (true, false): sentence = .pictureOf
        case (false, true): sentence = .about(page: hit.page)
        case (false, false): sentence = .says(page: hit.page)
        }
        wordsNote = words.isEmpty ? nil : hit.match == .both ? .found : .fits(words)
    }

    /// Whether it matched in meaning: the comparison and the closeness meter show. Not for a file only the words
    /// found, which isn't close to the picture.
    var matchedInMeaning: Bool { sentence != .wordsOnly }

    /// The sentence, and the words' sentence after it.
    var text: String {
        guard let note = wordsNote else { return sentenceText }
        let words = switch note {
        case .found: String(localized: .lookoutPictureWhyWordsFound)
        case .fits(let words): String(localized: .lookoutPictureWhyWordsFit(words))
        }
        return sentenceText + " " + words
    }

    private var sentenceText: String {
        switch sentence {
        case .alike: String(localized: .lookoutPictureWhyAlike)
        case .pictureOf: String(localized: .lookoutPictureWhyPictureOf)
        case .about(let page?): String(localized: .lookoutPictureWhyAboutPage(page))
        case .about(nil): String(localized: .lookoutPictureWhyAbout)
        case .says(let page?): String(localized: .lookoutPictureWhySaysPage(page))
        case .says(nil): String(localized: .lookoutPictureWhySays)
        case .wordsOnly: String(localized: .lookoutPictureWhyWordsOnly)
        }
    }

    /// The match chip on a result row: "Looks alike" for a picture (or a folder of them) found with a picture,
    /// "Same subject" for the rest, and nil for a file only typed words found, which keeps Lookout's own words chip.
    static func matchTitle(hit: LookoutHit, group: LookoutSimilarResults.GroupKind, queryIsPicture: Bool) -> String? {
        if !hit.isFolder, hit.match == .words { return nil }
        return hit.isFolder || (group == .pictures && queryIsPicture)
            ? String(localized: .lookoutPictureMatchAlike) : String(localized: .lookoutPictureMatchSame)
    }
}
