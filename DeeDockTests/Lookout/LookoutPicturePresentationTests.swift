import Foundation
import Testing
@testable import DeeDock

/// What searching with a picture shows and offers, from pure inputs: which drags the field takes, where Find Similar
/// is offered, what the results show, the results bar's line, "why it matched", and the analytics.
@MainActor struct LookoutPicturePresentationTests {
    private let photo = URL(filePath: "/Users/tester/Desktop/IMG_5012.HEIC")
    private let zip = URL(filePath: "/Users/tester/Documents/Taxes 2024 archive.zip")
    private let pdf = URL(filePath: "/Users/tester/Downloads/Invoice_October.pdf")

    // MARK: Dropping

    @Test func picturesAreTakenAndAnythingElseRefused() {
        let none: (URL) -> LookoutSimilarAvailability? = { _ in nil }
        #expect(LookoutPictureDrop.classify(urls: [photo], hasImageData: false, result: none) == .picture(photo))
        #expect(LookoutPictureDrop.classify(urls: [zip], hasImageData: false, result: none) == .refused)
        #expect(LookoutPictureDrop.classify(urls: [URL(filePath: "/x/logo.svg")], hasImageData: false, result: none)
            == .refused)
        let folder = URL(filePath: "/Users/tester/Pictures/Holiday", directoryHint: .isDirectory)
        #expect(LookoutPictureDrop.classify(urls: [folder], hasImageData: false, result: none) == .refused)
        #expect(LookoutPictureDrop.classify(urls: [], hasImageData: true, result: none) == .imageData)
        #expect(LookoutPictureDrop.classify(urls: [], hasImageData: false, result: none) == nil)
        #expect(LookoutPictureDrop.refused.isAccepted == false && LookoutPictureDrop.imageData.isAccepted)
        #expect(LookoutPictureDrop.unread.isAccepted == false)
    }

    /// A document is taken when the index holds it (its stored vector), refused with why when it doesn't, and waits
    /// for the index's answer before saying either.
    @Test func aDocumentIsTakenOnlyWhenTheIndexHoldsIt() {
        let none: (URL) -> LookoutSimilarAvailability? = { _ in nil }
        func drop(_ known: Bool?, fromFilesPane: Bool = false) -> LookoutPictureDrop? {
            LookoutPictureDrop.classify(urls: [pdf], hasImageData: false, fromFilesPane: fromFilesPane,
                                        inIndex: { _ in known }, result: none)
        }
        #expect(drop(nil) == nil)
        #expect(drop(true) == .similar(pdf))
        #expect(drop(false) == .unread)
        // Moving files between panes opens the well for a document the index holds, and stays quiet otherwise.
        #expect(drop(true, fromFilesPane: true) == .similar(pdf))
        #expect(drop(false, fromFilesPane: true) == nil)
        #expect(LookoutSimilarAvailability.dependsOnIndex(pdf, isDirectory: false))
        #expect(!LookoutSimilarAvailability.dependsOnIndex(photo, isDirectory: false))
        #expect(!LookoutSimilarAvailability.dependsOnIndex(zip, isDirectory: false))
        // A dropped picture prefers its stored vector and is read when the index doesn't hold it; a document has no
        // picture to fall back on.
        #expect(LookoutPictureQuery.dropped(photo).input == .indexed(path: photo.path, segmentID: nil, fallback: photo))
        #expect(LookoutPictureQuery.dropped(pdf).input == .indexed(path: pdf.path, segmentID: nil, fallback: nil))
    }

    @Test func aResultDraggedOntoTheFieldFindsSimilar() {
        let available: (URL) -> LookoutSimilarAvailability? = { $0 == self.pdf ? .available(isPicture: false) : nil }
        #expect(LookoutPictureDrop.classify(urls: [pdf], hasImageData: false, result: available) == .similar(pdf))
        let unsupported: (URL) -> LookoutSimilarAvailability? = { _ in .unsupported }
        #expect(LookoutPictureDrop.classify(urls: [zip], hasImageData: false, result: unsupported) == .refused)
    }

    @Test func movingFilesBetweenPanesShowsNoRefusal() {
        let none: (URL) -> LookoutSimilarAvailability? = { _ in nil }
        #expect(LookoutPictureDrop.classify(urls: [zip], hasImageData: false, fromFilesPane: true, result: none) == nil)
        #expect(LookoutPictureDrop.classify(urls: [photo], hasImageData: false, fromFilesPane: true, result: none)
            == .picture(photo))
    }

    // MARK: Find Similar

    @Test func findSimilarFollowsWhatLookoutReads() throws {
        func of(_ url: URL, folder: Bool = false, canSearch: Bool = true, inIndex: Bool? = nil) -> LookoutSimilarAvailability {
            LookoutSimilarAvailability.of(url, isDirectory: folder, canSearch: canSearch, inIndex: inIndex)
        }
        #expect(of(photo) == .available(isPicture: true))
        #expect(of(photo, inIndex: false) == .available(isPicture: true))   // read like a dropped picture
        #expect(of(pdf, inIndex: true) == .available(isPicture: false))
        #expect(of(pdf) == .available(isPicture: false))                    // not known yet
        #expect(of(pdf, inIndex: false) == .notIndexed)                     // nothing to search with: says why
        #expect(String(localized: try #require(LookoutSimilarAvailability.notIndexed.disabledReason))
            == String(localized: .lookoutSimilarNotIndexed))
        #expect(LookoutSimilarAvailability.available(isPicture: true).disabledReason == nil)
        let letter = URL(filePath: "/x/Letter.rtfd", directoryHint: .isDirectory)
        #expect(of(letter, folder: true, inIndex: true) == .available(isPicture: false))   // a package document
        #expect(of(URL(filePath: "/x/logo.svg")) == .unsupported)
        #expect(of(zip) == .unsupported)
        #expect(of(URL(filePath: "/x/main.swift")) == .unsupported)
        #expect(of(URL(filePath: "/x/Holiday", directoryHint: .isDirectory), folder: true) == .hidden)
        #expect(of(photo, canSearch: false) == .hidden)
        var options = IndexOptions()
        options.excludedExtensions = ["pdf"]
        #expect(LookoutSimilarAvailability.of(pdf, isDirectory: false, canSearch: true, inIndex: true, options: options)
            == .unsupported)
    }

    // MARK: Results

    @Test func theResultsFollowStatusAndPhase() {
        let empty = LookoutSimilarResults(queryIsPicture: true)
        let some = LookoutSimilarResults(queryIsPicture: true, groups: [
            .init(kind: .pictures), .init(kind: .documents, strong: [LookoutUIFixtures.hit("/x/a.md")]),
        ])
        func content(_ status: LookoutStatus, _ phase: LookoutPictureSearch.Phase,
                     _ results: LookoutSimilarResults) -> LookoutPictureContent {
            LookoutPictureContent(status: status, phase: phase, results: results)
        }
        #expect(content(.notSetUp, .unavailable, empty).body == .promo)
        #expect(content(.waitingForModel, .unavailable, empty).body == .download)
        #expect(content(.ready, .waking, empty).body == .skeleton)
        #expect(content(.ready, .reading, empty).body == .skeleton)
        #expect(content(.ready, .lookingUp, empty).body == .skeleton)
        #expect(content(.ready, .failed, empty).body == .unreadable)
        #expect(content(.ready, .done, empty).body == .honest)
        #expect(content(.ready, .done, some).body == .groups)
        #expect(content(.ready, .done, some).notice == nil)
        #expect(content(.indexing(remaining: 12, progress: nil), .done, some).notice == .indexing(remaining: 12))
        #expect(content(.paused(.lowPowerMode), .done, some).notice == .paused(.lowPowerMode))
        #expect(content(.off, .done, some).body == .nothing)
    }

    @Test func theResultsBarSaysHowThePictureWasRead() {
        func line(pasted: Bool = false, _ phase: LookoutPictureSearch.Phase, canSearch: Bool = true,
                  stored: LookoutSimilarSource? = nil, seconds: Double? = 0.35) -> LookoutPictureSubtitle {
            LookoutPictureSubtitle(isPasted: pasted, phase: phase, canSearch: canSearch, stored: stored,
                                   readSeconds: seconds)
        }
        #expect(line(.waking) == .waking && line(.waking).isBusy)
        #expect(line(.reading) == .reading)
        #expect(line(.done) == .new(seconds: 0.35))
        #expect(line(pasted: true, .done) == .pasted(seconds: 0.35))
        #expect(line(.unavailable, canSearch: false) == .new(seconds: nil))
        let page = LookoutSimilarSource(vector: [], modality: .text, segment: .page, page: 7, path: "/x.pdf")
        #expect(line(.done, stored: page, seconds: nil) == .fromIndex(page: 7))
        #expect(line(.lookingUp, seconds: nil) == .fromIndex(page: nil))
        #expect(LookoutPictureSubtitle.new(seconds: nil).text.contains("·"))
    }

    @Test func whyItMatchedDependsOnBothSides() {
        let picture = hit("/x/a.heic", kind: .image, z: 4.2)
        let page = hit("/x/lease.pdf", kind: .pdf, z: 3.4, segment: .page, loc: 7)
        let note = hit("/x/notes.md", kind: .doc, z: 2.1, segment: .chunk)
        #expect(LookoutPictureWhy(hit: picture, queryIsPicture: true).sentence == .alike)
        #expect(LookoutPictureWhy(hit: picture, queryIsPicture: false).sentence == .pictureOf)
        #expect(LookoutPictureWhy(hit: page, queryIsPicture: true).sentence == .about(page: 7))
        #expect(LookoutPictureWhy(hit: note, queryIsPicture: false).sentence == .says(page: nil))
        #expect(LookoutPictureWhy(hit: picture, queryIsPicture: true).closeness == .veryClose)
        #expect(LookoutPictureWhy(hit: page, queryIsPicture: true).closeness == .close)
        #expect(LookoutPictureWhy(hit: note, queryIsPicture: true).closeness == .somewhat)
        #expect(LookoutPictureWhy.Closeness(z: 4) == .veryClose && LookoutPictureWhy.Closeness(z: 3) == .close)
        #expect(LookoutPictureWhy.Closeness(z: 2.99) == .somewhat)

        let alike = String(localized: .lookoutPictureMatchAlike), same = String(localized: .lookoutPictureMatchSame)
        #expect(LookoutPictureWhy.matchTitle(hit: picture, group: .pictures, queryIsPicture: true) == alike)
        #expect(LookoutPictureWhy.matchTitle(hit: picture, group: .pictures, queryIsPicture: false) == same)
        #expect(LookoutPictureWhy.matchTitle(hit: page, group: .documents, queryIsPicture: true) == same)
        let folder = LookoutUIFixtures.hit("/x/Holiday", folderFiles: 4)
        #expect(LookoutPictureWhy.matchTitle(hit: folder, group: .documents, queryIsPicture: false) == alike)
    }

    @Test func whyItMatchedNamesTheWordsBesideThePicture() {
        let picture = hit("/x/a.heic", kind: .image, z: 4.2)
        let named = hit("/x/Sunset.jpg", kind: .image, z: 3.1, match: .both)
        let byName = hit("/x/Sunset gradient.png", kind: .image, z: 0.4, segment: .name, match: .words)

        let fits = LookoutPictureWhy(hit: picture, queryIsPicture: true, words: "at sunset")
        #expect(fits.sentence == .alike && fits.wordsNote == .fits("at sunset") && fits.matchedInMeaning)
        #expect(fits.text.hasPrefix(String(localized: .lookoutPictureWhyAlike)) && fits.text.contains("at sunset"))
        #expect(LookoutPictureWhy(hit: named, queryIsPicture: true, words: "at sunset").wordsNote == .found)
        // Found only by the words: no likeness claimed, no meter.
        let words = LookoutPictureWhy(hit: byName, queryIsPicture: true, words: "at sunset")
        #expect(words.sentence == .wordsOnly && words.wordsNote == nil && !words.matchedInMeaning)
        #expect(words.text == String(localized: .lookoutPictureWhyWordsOnly))
        // Without words, nothing changes.
        #expect(LookoutPictureWhy(hit: picture, queryIsPicture: true).wordsNote == nil)

        #expect(LookoutPictureWhy.matchTitle(hit: byName, group: .pictures, queryIsPicture: true) == nil)
        #expect(LookoutPictureWhy.matchTitle(hit: named, group: .pictures, queryIsPicture: true)
            == String(localized: .lookoutPictureMatchAlike))
    }

    // MARK: Analytics

    @Test func aPictureSearchReportsItsSourceAndColdStartOnly() {
        let event = LookoutAnalytics.imageSearch(source: .drop, cold: true)
        #expect(event.name == "lookout_image_search")
        #expect(event.properties.values.mapValues(\.displayText) == ["source": "drop", "cold": "true"])
        #expect([AnalyticsLookoutImageSource.drop, .paste, .similar, .browser, .hubTile].map(\.rawValue)
            == ["drop", "paste", "similar", "browser", "hub_tile"])
        #expect(LookoutPictureQuery.dropped(photo).analyticsSource == .drop)
        #expect(LookoutPictureQuery.dropped(photo, via: .paste).analyticsSource == .paste)
        #expect(LookoutPictureQuery.pasted(Data(), image: nil).analyticsSource == .paste)
        #expect(LookoutPictureQuery.similar(pdf, segmentID: nil, isPicture: false).analyticsSource == .similar)
        #expect(LookoutPictureQuery.similar(pdf, segmentID: nil, isPicture: false, via: .browser).analyticsSource
            == .browser)
    }

    @Test func anOpenedPictureResultSaysItWasAPictureSearch() {
        let opened = LookoutAnalytics.opened(hit("/Users/tester/Desktop/Secret Trip/IMG_1.HEIC", kind: .image, z: 3),
                                             section: .strong, rank: 1, scope: .thisMac, isLookup: false, query: .image)
        let values = opened.properties.values.mapValues(\.displayText)
        #expect(values["query"] == "image" && values["kind"] == "image" && values["section"] == "strong")
        #expect(!values.values.contains { $0.contains("Secret") || $0.contains("/Users") || $0.contains("IMG_1") })
        #expect(values["words_weight"] == nil)
    }

    @Test func anOpenedResultOfPictureAndWordsSaysTheSlidersPlaceOnly() {
        let result = hit("/Users/tester/Desktop/Sunset Sylt.jpg", kind: .image, z: 3, match: .both)
        let opened = LookoutAnalytics.opened(result, section: .weak, rank: 2, scope: .folder, isLookup: false,
                                             query: .imageWords, wordsWeight: 0.65)
        let values = opened.properties.values.mapValues(\.displayText)
        #expect(values["query"] == "image_words" && values["words_weight"] == "65" && values["match"] == "both")
        #expect(!values.values.contains { $0.contains("Sunset") || $0.contains("/Users") })
        // Only a search with both reports the slider.
        let text = LookoutAnalytics.opened(result, section: .strong, rank: 1, scope: .thisMac, isLookup: false,
                                           wordsWeight: 0.65)
        #expect(text.properties.values["words_weight"] == nil)
        #expect(AnalyticsCounter.lookoutPictureWordsAdded.key == "lookout_picture_words_added")
        #expect(AnalyticsCounter.lookoutPictureWeightChanged.key == "lookout_picture_weight_changed")
    }

    private func hit(_ path: String, kind: FileKind, z: Double, segment: SegmentKind = .image,
                     loc: Double? = nil, match: LookoutHit.Match = .meaning) -> LookoutHit {
        LookoutHit(path: path, kind: kind, folder: nil, score: z, z: z, cosine: nil, coverage: match == .meaning ? 0 : 1,
                   keywordRank: match == .meaning ? nil : 1, match: match, segment: segment, segmentID: nil, loc: loc,
                   locEnd: loc, snippet: nil, excerpt: nil, modified: nil, size: nil, info: [:])
    }
}
