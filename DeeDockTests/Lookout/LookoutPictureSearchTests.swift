import Foundation
import Testing
@testable import DeeDock

/// `LookoutPictureSearch` over fakes: honest phases while the picture reader wakes and reads, a stored vector reused
/// for Find Similar without encoding anything, the file searched with left out, and nothing from a search that ended.
@MainActor struct LookoutPictureSearchTests {
    private let reader = FakePictureReader()
    private let encoder = FakePictureEncoder()
    private let folder = LookoutTestFolder()

    private func search() -> LookoutPictureSearch {
        let search = LookoutPictureSearch(reader: reader, encoder: encoder)
        search.isAvailable = true
        return search
    }

    private func someResults() -> LookoutSimilarResults {
        LookoutSimilarResults(queryIsPicture: true, groups: [
            .init(kind: .pictures, strong: [LookoutUIFixtures.hit("/x/a.heic", kind: .image, segment: .image)]),
            .init(kind: .documents),
        ])
    }

    @Test func aColdReaderWakesThenReadsThenFinds() async throws {
        await reader.setResults(someResults())
        encoder.delay = .milliseconds(120)
        let file = try LookoutTestPictures.file(named: "IMG_1.png", in: folder)
        let search = search()
        let cold = search.search(.file(file), source: .drop, scope: .thisMac)
        #expect(cold && search.phase == .waking)
        #expect(await eventually { search.phase == .reading })
        #expect(await eventually { search.phase == .done })
        #expect(encoder.pictureWarmUps == 1 && encoder.pictures.count == 1)
        let picture = try #require(encoder.pictures.first)
        // A photo is sized as the indexer sizes photos: 140 soft tokens, each side a multiple of 48 px.
        #expect(picture.budget == 140 && picture.width % 48 == 0 && picture.height % 48 == 0)
        #expect(picture.pixels.count == picture.width * picture.height * 3)
        #expect((search.readSeconds ?? 0) > 0 && search.storedSource == nil)
        #expect(search.results.groups.first?.strong.count == 1)
        let request = try #require(await reader.requests.first)
        #expect(request.queryIsPicture && request.excluding == [file.path])
    }

    @Test func aWarmReaderGoesStraightToReading() async throws {
        await reader.setResults(someResults())
        try await encoder.warmUpPictureReader()
        let search = search()
        let cold = search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac)
        #expect(!cold && search.phase == .reading)
        #expect(await eventually { search.phase == .done })
        #expect(encoder.pictureWarmUps == 1)   // only the one above
        // Pasted bytes are sized as a screenshot, and exclude nothing.
        #expect(encoder.pictures.first?.budget == 280)
        #expect(await reader.requests.first?.excluding.isEmpty == true)
    }

    @Test func findSimilarReusesTheStoredVector() async throws {
        let path = "/Users/tester/Documents/lease.pdf"
        var stored = [Float](repeating: 0, count: Vectors.dimension)
        stored[3] = 1
        await reader.setSource(LookoutSimilarSource(vector: stored, modality: .text, segment: .page, page: 7, path: path))
        await reader.setResults(someResults())
        let search = search()
        let cold = search.search(.indexed(path: path, segmentID: 42, fallback: nil), source: .similar, scope: .thisMac)
        #expect(!cold && search.phase == .lookingUp)
        #expect(await eventually { search.phase == .done })
        #expect(encoder.pictures.isEmpty && encoder.pictureWarmUps == 0)
        #expect(search.storedSource?.page == 7 && search.readSeconds == nil)
        let lookup = try #require(await reader.sourceLookups.first)
        #expect(lookup.path == path && lookup.segmentID == 42)
        let request = try #require(await reader.requests.first)
        // A page's text vector: documents first, and the PDF itself left out.
        #expect(request.vector == stored && !request.queryIsPicture && request.excluding == [path])
        #expect(!search.results.queryIsPicture)
    }

    @Test func aPictureOutsideTheIndexIsReadLikeADroppedOne() async throws {
        await reader.setResults(someResults())
        let file = try LookoutTestPictures.file(named: "Screenshot 2026-10-11 at 18.40.02.png", in: folder)
        let search = search()
        search.search(.indexed(path: file.path, segmentID: nil, fallback: file), source: .similar, scope: .thisMac)
        #expect(await eventually { search.phase == .done })
        #expect(encoder.pictures.count == 1 && encoder.pictures.first?.budget == 280)   // a screenshot, by its name
        #expect(search.storedSource == nil && search.readSeconds != nil)
        #expect(await reader.requests.first?.excluding == [file.path])
    }

    @Test func aDocumentOutsideTheIndexHasNothingToSearchWith() async {
        let search = search()
        search.search(.indexed(path: "/x/notes.md", segmentID: nil, fallback: nil), source: .similar, scope: .thisMac)
        #expect(await eventually { search.phase == .failed })
        #expect(encoder.pictures.isEmpty)
        #expect(await reader.requests.isEmpty)
    }

    @Test func anUnreadablePictureFails() async throws {
        let file = try folder.write("broken.png", Data("not a picture".utf8))
        let search = search()
        search.search(.file(file), source: .drop, scope: .thisMac)
        #expect(await eventually { search.phase == .failed })
        #expect(search.results.hasNoStrongHits)
    }

    @Test func clearingDropsALateResult() async throws {
        await reader.setResults(someResults())
        encoder.delay = .milliseconds(200)
        let search = search()
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac)
        search.clear()
        try await Task.sleep(for: .milliseconds(450))
        #expect(search.phase == .idle && search.results.hasNoStrongHits)
        #expect(await reader.requests.isEmpty)
    }

    @Test func aNewScopeReusesTheVector() async throws {
        await reader.setResults(someResults())
        let search = search()
        #expect(!search.rescope(.thisMac))   // nothing to reuse yet
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac)
        #expect(await eventually { search.phase == .done })
        #expect(search.rescope(.folder(URL(filePath: "/Users/tester/Desktop"))))
        #expect(await eventually { await reader.requests.count == 2 })
        #expect(encoder.pictures.count == 1)
        #expect(await reader.requests.last?.scope == "/Users/tester/Desktop")
    }

    @Test func turningLookoutOffEndsTheSearch() async {
        let search = search()
        encoder.delay = .milliseconds(200)
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac)
        search.isAvailable = false
        #expect(search.phase == .unavailable)
        #expect(!search.search(.data(Data()), source: .paste, scope: .thisMac))
        #expect(search.phase == .unavailable)
    }

    @Test func warmingUpWakesTheReaderOnce() async {
        let search = search()
        encoder.delay = .milliseconds(100)
        search.warmUp()
        search.warmUp()
        #expect(await eventually { encoder.isPictureReaderWarm })
        search.warmUp()
        #expect(encoder.pictureWarmUps == 1 && !search.isReaderCold)
    }
}
