import Darwin
import Foundation
import Testing
@testable import DeeDock

/// `LookoutPictureSearch` over fakes: honest phases while the picture reader wakes and reads, a stored vector reused
/// for Find Similar without encoding anything, the file searched with left out, and nothing from a search that ended.
@MainActor struct LookoutPictureSearchTests {
    private let reader = FakePictureReader()
    private let connection = FakeIndexConnection()
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

    // MARK: Running again

    @Test func aSearchThatCouldNotRunRunsOnceLookoutIsAvailable() async throws {
        await reader.setResults(someResults())
        let search = LookoutPictureSearch(reader: reader, encoder: encoder)
        search.search(.data(LookoutTestPictures.png()), source: .drop, scope: .thisMac)
        #expect(search.phase == .unavailable)   // dropped before setup
        search.isAvailable = true                // set up, "Start searching"
        #expect(await eventually { search.phase == .done })
        #expect(search.results.groups.first?.strong.count == 1)
        // Off and on again: the same picture searches again, with the vector it has.
        search.isAvailable = false
        #expect(search.phase == .unavailable && search.results.groups.allSatisfy { $0.strong.isEmpty })
        search.isAvailable = true
        #expect(await eventually { search.phase == .done && search.results.groups.first?.strong.count == 1 })
        #expect(encoder.pictures.count == 1)
    }

    @Test func aNewFilterSearchesAgainWithTheSameVector() async throws {
        await reader.setResults(someResults())
        let search = search()
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac)
        #expect(await eventually { search.phase == .done })
        let removed = LookoutSearchFilter(folders: ["/Users/tester/Documents"])
        search.filter = removed
        search.refresh()
        #expect(await eventually { await reader.requests.count == 2 })
        #expect(await reader.requests.last?.filter == removed)
        #expect(encoder.pictures.count == 1)     // nothing read again
        #expect(await eventually { search.phase == .done })
    }

    @Test func theIndexAppearingRunsASearchThatFoundNoIndex() async throws {
        await reader.setResults(nil)            // no index yet
        let search = search()
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac)
        #expect(await eventually { search.phase == .unavailable && encoder.pictures.count == 1 })
        await reader.setResults(someResults())
        search.refresh()
        #expect(await eventually { search.phase == .done })
        #expect(encoder.pictures.count == 1)
        // A cleared search has nothing to run again.
        search.clear()
        search.refresh()
        #expect(search.phase == .idle)
    }

    // MARK: Words beside the picture

    @Test func typedWordsSearchAgainWithoutReadingThePicture() async throws {
        await reader.setResults(someResults())
        let search = search()
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac)
        #expect(await eventually { search.phase == .done })
        search.updateWords("  at night ")
        #expect(search.words == "at night")
        #expect(await eventually { await reader.requests.count == 2 })
        let request = try #require(await reader.requests.last)
        #expect(request.words == LookoutSimilarWords(text: "at night", vector: encoder.wordsVector,
                                                     weight: LookoutRanking.pictureWordsWeight))
        #expect(request.vector == encoder.vector && request.queryIsPicture)
        #expect(encoder.pictures.count == 1 && encoder.queries == ["at night"])
        // Back to no words: the picture alone again, nothing embedded.
        search.updateWords("")
        #expect(await eventually { await reader.requests.count == 3 })
        #expect(await reader.requests.last?.words == nil && encoder.queries.count == 1)
    }

    @Test func typingWaitsForTheDebounce() async throws {
        await reader.setResults(someResults())
        let search = search()
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac)
        #expect(await eventually { search.phase == .done })
        for prefix in ["a", "at", "at n", "at ni", "at night"] { search.updateWords(prefix) }
        #expect(await eventually { await reader.requests.count == 2 })
        try await Task.sleep(for: LookoutSearch.debounce * 3)
        // One search for the last words, one embedding.
        #expect(await reader.requests.count == 2 && encoder.queries == ["at night"])
    }

    @Test func wordsTypedWhileThePictureIsReadWaitForIt() async throws {
        await reader.setResults(someResults())
        encoder.delay = .milliseconds(150)
        let search = search()
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac)
        search.updateWords("at night")
        #expect(search.phase == .waking)
        #expect(await eventually { search.phase == .done })
        // The read went on: one picture, one search, with the words.
        #expect(encoder.pictures.count == 1)
        let requests = await reader.requests
        #expect(requests.count == 1 && requests.first?.words?.text == "at night")
    }

    @Test func theSliderRanksAgainWithTheVectorsItHas() async throws {
        await reader.setResults(someResults())
        let search = search()
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac)
        #expect(await eventually { search.phase == .done })
        // Without words the slider has nothing to weigh.
        search.setWordsWeight(0.7)
        try await Task.sleep(for: LookoutPictureSearch.weightPause * 3)
        #expect(await reader.requests.count == 1)
        search.updateWords("at night")
        #expect(await eventually { await reader.requests.count == 2 })
        search.setWordsWeight(0.75)
        search.setWordsWeight(2)                         // past the end: held at the end
        #expect(search.wordsWeight == LookoutRanking.pictureWordsWeights.upperBound)
        #expect(await eventually { await reader.requests.count == 3 })
        #expect(await reader.requests.last?.words?.weight == LookoutRanking.pictureWordsWeights.upperBound)
        // A new scope keeps the words and the weight, and embeds nothing again.
        search.rescope(.folder(URL(filePath: "/Users/tester/Desktop")), words: "at night")
        #expect(await eventually { await reader.requests.count == 4 })
        #expect(await reader.requests.last?.words?.weight == LookoutRanking.pictureWordsWeights.upperBound)
        #expect(encoder.queries == ["at night"] && encoder.pictures.count == 1)
        // A new filter refreshes with the words it has.
        search.filter = LookoutSearchFilter(folders: ["/Users/tester/Desktop"])
        search.refresh()
        #expect(await eventually { await reader.requests.count == 5 })
        #expect(await reader.requests.last?.words?.text == "at night" && search.words == "at night")
    }

    @Test func aNewPictureStartsAtTheDefaultWeight() async throws {
        await reader.setResults(someResults())
        let search = search()
        let first = UUID()
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac, id: first)
        #expect(await eventually { search.phase == .done })
        search.updateWords("at night")
        search.setWordsWeight(0.8)
        // The same picture searched again (a restart) keeps the slider; a new one doesn't.
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac, id: first, words: "at night")
        #expect(search.wordsWeight == 0.8)
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac, id: UUID())
        #expect(search.wordsWeight == LookoutRanking.pictureWordsWeight && search.words.isEmpty)
        search.clear()
        #expect(search.wordsWeight == LookoutRanking.pictureWordsWeight && search.words.isEmpty)
    }

    @Test func wordsTheEncoderCantReadCountAsKeywords() async throws {
        await reader.setResults(someResults())
        encoder.failsWords = true
        let search = search()
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac)
        #expect(await eventually { search.phase == .done })
        search.updateWords("sunset")
        #expect(await eventually { await reader.requests.count == 2 })
        let words = try #require(await reader.requests.last?.words)
        #expect(words.text == "sunset" && words.vector == nil)
        #expect(search.phase == .done)
    }

    @Test func theFirstWordsArePerPictureInAnalytics() async throws {
        await reader.setResults(someResults())
        let search = search()
        var counted: [AnalyticsCounter] = []
        search.countAnalytics = { counted.append($0) }
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac, id: UUID())
        #expect(await eventually { search.phase == .done })
        search.updateWords("at")
        search.updateWords("at night")
        search.updateWords("")
        search.updateWords("at dusk")
        #expect(counted == [.lookoutPictureWordsAdded])
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac, id: UUID())
        search.updateWords("red")
        #expect(counted == [.lookoutPictureWordsAdded, .lookoutPictureWordsAdded])
    }

    // MARK: Reading a dropped file

    @Test func aDroppedFileIsReadFromOneCheckedDescriptor() throws {
        let file = try folder.write("IMG_1.png", Data(repeating: 7, count: 10))
        #expect(try LookoutPictureReading.bytes(at: file).count == 10)
        // Over the cap, checked on the open file: refused before anything is read.
        #expect(throws: QueryPicture.Failure.self) { try LookoutPictureReading.bytes(at: file, maxBytes: 4) }
        // Not a regular file, or not there: refused, never a silent zero size.
        let subfolder = try folder.folder("Holiday.png")
        #expect(throws: QueryPicture.Failure.self) { try LookoutPictureReading.bytes(at: subfolder) }
        let fifo = folder.url.appendingPathComponent("pipe.png")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: QueryPicture.Failure.self) { try LookoutPictureReading.bytes(at: fifo) }
        #expect(throws: QueryPicture.Failure.self) {
            try LookoutPictureReading.bytes(at: folder.url.appendingPathComponent("gone.png"))
        }
    }

    @Test func aFileOverTheCapIsRefusedWithoutReadingIt() throws {
        let file = try folder.write("huge.png", Data())
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(LookoutPictureReading.maxBytes) + 1)   // sparse: nothing written
        try handle.close()
        #expect(throws: QueryPicture.Failure.self) { try LookoutPictureReading.bytes(at: file) }
    }

    // MARK: Round 7

    /// The first index arrives while a reader call that found none is still on its way back: the refresh the
    /// engine sends then wins, and the stale "no index" is dropped.
    @Test func theFirstIndexArrivingDuringAReaderCallStillSearches() async throws {
        await reader.setResults(nil)
        await reader.holdNextAnswer()                     // "no index", held in flight until released below
        let engine = LookoutEngine(settings: .activeForTests, repository: nil, connection: connection,
                                   encoder: encoder, reader: reader, monitor: FakeMonitor(), power: FakePowerPolicy(),
                                   paths: LookoutPaths(base: URL(fileURLWithPath: "/tmp/lookout-picture-engine-tests",
                                                                 isDirectory: true)),
                                   canRun: true)
        engine.start()
        let search = engine.pictureSearch
        search.search(.data(LookoutTestPictures.png()), source: .paste, scope: .thisMac)
        #expect(await eventually { await reader.requests.count == 1 })
        #expect(search.phase == .reading)                 // the reader call is in flight
        await reader.setResults(someResults())
        var status = LookoutIndexStatus()
        status.activity = .indexing
        status.counts = IndexStore.Counts(byKindAndState: ["image": ["done": 1, "pending": 9]])
        connection.send(status)                           // the first files
        #expect(await eventually { search.phase == .done && search.results.groups.first?.strong.count == 1 })
        await reader.releaseHeld()                        // the stale "no index" comes back, and is dropped
        #expect(await eventually { await reader.answered == 2 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(search.phase == .done && search.results.groups.first?.strong.count == 1)
        engine.stop()
    }

    @Test func theSamePictureSearchedAgainSendsItsAnalyticsOnce() async throws {
        await reader.setResults(someResults())
        encoder.delay = .milliseconds(200)
        let file = try LookoutTestPictures.file(named: "IMG_1.png", in: folder)
        let search = search()
        var events: [String] = []
        search.sendAnalytics = { events.append($0.name) }
        let picture = UUID()
        search.search(.file(file), source: .drop, scope: .thisMac, id: picture)
        #expect(events.count == 1)
        // A scope change while it's still being read, or the Files tab appearing again: the same picture.
        search.search(.file(file), source: .drop, scope: .folder(folder.url), id: picture)
        search.refresh()
        #expect(events.count == 1)
        #expect(await eventually { search.phase == .done })
        #expect(events.count == 1)
        // Another picture, or one without an identity, is a new request.
        search.search(.file(file), source: .drop, scope: .thisMac, id: UUID())
        search.search(.file(file), source: .drop, scope: .thisMac)
        #expect(events.count == 3)
    }

    @Test func aCancelledCallerReadsAndDecodesNothing() async throws {
        let file = try LookoutTestPictures.file(named: "IMG_1.png", in: folder)
        let task = Task { try await LookoutPictureReading.picture(at: file) }
        task.cancel()                                     // before it ran
        await #expect(throws: CancellationError.self) { try await task.value }
        let pasted = Task { try await LookoutPictureReading.picture(from: LookoutTestPictures.png()) }
        pasted.cancel()
        await #expect(throws: CancellationError.self) { try await pasted.value }
    }

    @Test func aReadStopsBetweenPiecesWhenItIsCancelled() throws {
        let file = try folder.write("big.png", Data())
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 20 << 20)           // sparse, three 8 MB pieces
        try handle.close()
        var checks = 0
        #expect(throws: CancellationError.self) {
            _ = try LookoutPictureReading.bytes(at: file) {
                checks += 1
                if checks == 3 { throw CancellationError() }   // before the second piece
            }
        }
        #expect(checks == 3)
        var all = 0
        #expect(try LookoutPictureReading.bytes(at: file) { all += 1 }.count == 20 << 20)
        #expect(all == 4)                                 // before allocating, and before each of three pieces
    }
}
