import Foundation
import Testing
@testable import DeeDock

/// The search field's picture chip (`LookoutPictureSession`) and the Files model around it: a picture replaces the
/// words, ⌫ / ✕ / "Back to" bring them back, clear and Escape don't, typing replaces the picture, and a second
/// picture (Find Similar on a result) keeps the words from before the first.
@MainActor struct LookoutPictureSessionTests {
    private let beach = LookoutPictureQuery.dropped(URL(filePath: "/Users/tester/Desktop/IMG_5012.HEIC"))
    private let page = LookoutPictureQuery.similar(URL(filePath: "/Users/tester/Documents/lease.pdf"), segmentID: 7,
                                                   isPicture: false)

    @Test func removingThePictureBringsTheWordsBack() {
        var session = LookoutPictureSession()
        session.begin(beach, replacingWords: "  dog on the beach ")
        #expect(session.isActive && session.picture == beach && session.wordsBefore == "dog on the beach")
        #expect(session.remove(restoringWords: true) == "dog on the beach")
        #expect(!session.isActive && session.wordsBefore.isEmpty)
    }

    @Test func clearingRemovesPictureAndWords() {
        var session = LookoutPictureSession()
        session.begin(beach, replacingWords: "dog")
        #expect(session.remove(restoringWords: false).isEmpty)
        #expect(!session.isActive && session.wordsBefore.isEmpty)
    }

    @Test func aSecondPictureKeepsTheFirstWords() {
        var session = LookoutPictureSession()
        session.begin(beach, replacingWords: "dog")
        session.begin(page, replacingWords: "")
        #expect(session.picture == page && session.wordsBefore == "dog")
        #expect(session.remove(restoringWords: true) == "dog")
    }

    @Test func typingReplacesThePicture() {
        var session = LookoutPictureSession()
        session.begin(beach, replacingWords: "dog")
        session.typed()
        #expect(!session.isActive && session.wordsBefore.isEmpty)
    }

    // MARK: Model

    private func model() -> HubFilesModel {
        let suite = "dokk.tests.lookout.pictures.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return HubFilesModel(defaults: defaults, dataSource: HubFilesMemoryDataSource(home: URL(filePath: "/Users/tester")))
    }

    @Test func aPictureSearchesInPlaceOfTheWords() {
        let model = model()
        model.query = "dog on the beach"
        model.searchWithPicture(beach)
        #expect(model.query.isEmpty && model.isSearching && model.isPictureSearch)
        #expect(model.searchToken?.title == "IMG_5012.HEIC" && model.searchToken?.fileURL == beach.fileURL)
        #expect(model.pictureSession.wordsBefore == "dog on the beach")

        model.removeSearchToken()
        #expect(model.query == "dog on the beach" && !model.isPictureSearch && model.isSearching)
    }

    @Test func clearingEndsTheSearch() {
        let model = model()
        model.searchWithPicture(beach)
        #expect(model.isSearching)
        model.clearSearchWithToken()
        #expect(model.query.isEmpty && !model.isSearching && model.searchToken == nil)
    }

    @Test func typingAfterAPictureSearchesByWords() {
        let model = model()
        model.query = "dog"
        model.searchWithPicture(beach)
        model.query = "c"
        #expect(!model.isPictureSearch && model.query == "c" && model.pictureSession.wordsBefore.isEmpty)
    }

    @Test func aPictureSearchListsItsGroupsInOrder() {
        let model = model()
        let picture = LookoutUIFixtures.hit("/x/a.heic", kind: .image, segment: .image)
        let weaker = LookoutUIFixtures.hit("/x/b.heic", kind: .image, segment: .image)
        let document = LookoutUIFixtures.hit("/x/c.pdf", kind: .pdf, segment: .page, loc: 2)
        model.previewOverrides.pictureResults = LookoutSimilarResults(queryIsPicture: true, groups: [
            .init(kind: .pictures, strong: [picture], weak: [weaker]),
            .init(kind: .documents, strong: [document]),
        ])
        model.searchWithPicture(beach)
        #expect(model.searchOrder == [.lookout(picture.path), .lookout(document.path)])
        model.setPictureWeakExpanded(.pictures, true)
        #expect(model.searchOrder == [.lookout(picture.path), .lookout(weaker.path), .lookout(document.path)])
        model.lookoutSelection = weaker.path
        #expect(model.selectedPictureGroup?.kind == .pictures)
        // Folding a group with its weaker hit selected moves the selection to the group's last strong hit.
        model.setPictureWeakExpanded(.pictures, false)
        #expect(model.lookoutSelection == picture.path)
    }
}
