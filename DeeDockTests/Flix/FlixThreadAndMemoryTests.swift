import Foundation
import Testing
@testable import DeeDock

/// Threads without Lookout (time, working folder, shared name words), and drag memory's counts and
/// filter tip.
struct FlixThreadAndMemoryTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let home = "/Users/test"

    private func entry(_ path: String, at hours: Double, vector: [Float]? = nil) -> FlixThreadClusterer.Entry {
        let full = home + "/" + path
        return FlixThreadClusterer.Entry(id: UUID(), date: t0.addingTimeInterval(hours * 3_600),
                                         folder: (full as NSString).deletingLastPathComponent,
                                         words: FlixWords.distinctive((full as NSString).lastPathComponent),
                                         vector: vector.map { LookoutFileVector(vector: $0, isPicture: false) })
    }

    // MARK: Threads

    @Test func workingFoldersAndSharedWordsFormThreadsCatchAllFoldersDoNot() {
        let brief = entry("Projects/Oak/brief.pdf", at: 0), quote = entry("Projects/Oak/quote.pdf", at: 1)
        let board = entry("Projects/Oak/moodboard.png", at: 2)
        let zip = entry("Downloads/random.zip", at: 1), dmg = entry("Downloads/other.dmg", at: 1.5)
        let photo1 = entry("Downloads/Berlin-1.jpg", at: 5), photo2 = entry("Downloads/Berlin-2.jpg", at: 6)
        let map = entry("Desktop/Berlin map.png", at: 7)
        let groups = FlixThreadClusterer.groups([brief, quote, board, zip, dmg, photo1, photo2, map],
                                                catchAll: FlixThreadClusterer.catchAllFolders(home: home))
        #expect(groups.count == 2)
        #expect(groups.first == [map.id, photo2.id, photo1.id])
        #expect(groups.last.map(Set.init) == Set([brief.id, quote.id, board.id]))
    }

    @Test func farApartAndTooSmallGroupsAreNotThreads() {
        let spread = [entry("Projects/Tax/alpha.pdf", at: 0), entry("Projects/Tax/beta.pdf", at: 20),
                      entry("Projects/Tax/gamma.pdf", at: 40)]
        let pair = [entry("Projects/Talk/slides.key", at: 0), entry("Projects/Talk/notes.txt", at: 1)]
        #expect(FlixThreadClusterer.groups(spread + pair, catchAll: FlixThreadClusterer.catchAllFolders(home: home)).isEmpty)
    }

    @Test func relatedVectorsLinkAcrossCatchAllFolders() {
        let a = entry("Downloads/one.pdf", at: 0, vector: [1, 0, 0])
        let b = entry("Desktop/two.pdf", at: 3, vector: [0.95, 0.31, 0])
        let c = entry("Documents/three.pdf", at: 6, vector: [0.9, 0.43, 0])
        let groups = FlixThreadClusterer.groups([a, b, c], catchAll: FlixThreadClusterer.catchAllFolders(home: home))
        #expect(groups.count == 1)
    }

    @Test func stableIdentityNeedsAThirdOfTheMembers() {
        let ids = (0..<6).map { _ in UUID() }
        #expect(FlixThreadProvider.overlap(Set(ids[0..<3]), Set(ids[1..<4])) == 0.5)
        #expect(FlixThreadProvider.overlap(Set(ids[0..<2]), Set(ids[2..<6])) == 0)
    }

    /// Two parts of one piece of work, named the same, read as one thread: never "Craft Anything
    /// and Craft Anything" on the morning card.
    @Test func threadsWithTheSameNameAreShownAsOne() {
        let ids = (0..<7).map { _ in UUID() }
        let dates = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, t0.addingTimeInterval(Double($0) * 3_600)) })
        typealias Record = FlixThreadProvider.Record
        let records = [
            Record(id: "newer", memberIDs: [ids[6], ids[5], ids[4]], name: "Craft Anything", emoji: "🎨",
                   summary: "Icons.", namedByModel: true),
            Record(id: "trip", memberIDs: [ids[3]], name: "Berlin trip", emoji: "🧳"),
            Record(id: "older", memberIDs: [ids[2], ids[1], ids[0], ids[4]], name: " craft anything ", emoji: "📄"),
        ]
        let threads = FlixThreadProvider.displayThreads(records, dates: dates)
        #expect(threads.map(\.id) == ["newer", "trip"])
        #expect(threads[0].name == "Craft Anything" && threads[0].emoji == "🎨" && threads[0].summary == "Icons.")
        #expect(threads[0].memberIDs == [ids[6], ids[5], ids[4], ids[2], ids[1], ids[0]])
        #expect(threads[1].memberIDs == [ids[3]])
    }

    // MARK: Drag memory

    private func item(_ name: String, kind: FlixItemKind = .document, folder: String = "/Users/test/Projects/Oak",
                      date: Date? = nil, activity: FlixActivity = .opened) -> FlixItem {
        FlixItem(path: folder + "/" + name, name: name, kind: kind, activity: activity, date: date ?? t0)
    }

    @Test func kindsAreCountedPerApp() {
        #expect(FlixDragMemory.kindClass(of: item("Invoice.pdf")) == "pdf")
        #expect(FlixDragMemory.kindClass(of: item("Shot.png", kind: .screenshot)) == "image")
        #expect(FlixDragMemory.kindClass(of: item("Budget.xlsx")) == "spreadsheet")

        var memory = FlixDragMemory()
        let pdf = item("Invoice.pdf")
        var noticed: [[String]] = []
        for _ in 0..<4 { noticed.append(memory.recordDrop(of: [pdf], destination: "com.apple.Safari", name: "Safari")) }
        // Said once, on the third drop.
        #expect(noticed == [[], [], ["pdf"], []])
        #expect(memory.count(kind: "pdf", destination: "com.apple.Safari") == 4)
        #expect(memory.count(kind: "pdf", destination: "com.apple.mail") == 0)
        _ = memory.recordDrop(of: [item("Shot.png", kind: .image)], destination: "com.apple.Safari", name: "Safari")
        #expect(memory.usualKind(for: "com.apple.Safari") == "pdf")
    }

    @Test func aFolderOpenedOnThreeMorningsEarnsOneTip() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        let folder = "/Users/test/Projects/Oak"
        var memory = FlixDragMemory()
        let id = UUID()
        for day in 0..<3 {
            let opened = FlixItem(id: id, path: folder + "/brief.pdf", name: "brief.pdf", kind: .document, activity: .opened,
                                  date: monday.addingTimeInterval(Double(day) * 86_400))
            let counted = memory.observeOpens([opened], calendar: calendar)
            #expect(counted)
            // The same open seen again is not counted twice.
            let countedAgain = memory.observeOpens([opened], calendar: calendar)
            #expect(!countedAgain)
        }
        let now = monday.addingTimeInterval(3 * 86_400)
        let tip = try #require(memory.tipCandidate(now: now, calendar: calendar, excluding: []))
        #expect(tip.folder == folder)
        #expect(tip.part == .morning)
        memory.offeredTips.insert(FlixDragMemory.tipID(folder: tip.folder, part: tip.part))
        #expect(memory.tipCandidate(now: now, calendar: calendar, excluding: []) == nil)
        #expect(FlixDragMemory().tipCandidate(now: now, calendar: calendar, excluding: []) == nil)
    }
}
