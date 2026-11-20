import Foundation
import Testing
@testable import DeeDock

/// Noise rules, Smart Filter rules, and the list's time sections.
struct FlixRulesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ path: String, kind: FlixItemKind = .document, activity: FlixActivity = .opened,
                      age: TimeInterval = 0, host: String? = nil, flagged: Bool = false) -> FlixItem {
        FlixItem(path: path, name: (path as NSString).lastPathComponent, kind: kind, activity: activity,
                 date: now.addingTimeInterval(-age), sourcePage: host.map { URL(string: "https://\($0)/page")! },
                 isFlagged: flagged)
    }

    // MARK: Noise

    @Test(arguments: [
        ("/Users/x/Downloads/brand-kit.zip.download", FlixNoiseRules.Reason.partialDownload),
        ("/Users/x/Downloads/movie.mp4.crdownload", .partialDownload),
        ("/Users/x/Documents/~$Report.docx", .autosave),
        ("/Users/x/Documents/Budget.numbers.sb-2f1a9c", .autosave),
        ("/Users/x/Code/main.swift.swp", .autosave),
        ("/Users/x/Projects/App/build/Release/App.o", .buildProduct),
        ("/Users/x/Library/Developer/Xcode/DerivedData/App/Info.plist", .buildProduct),
        ("/Users/x/web/node_modules/left-pad/index.js", .buildProduct),
        ("/private/var/folders/ab/T/item.png", .temporary),
        ("/Users/x/Desktop/.DS_Store", .temporary),
    ])
    func noiseIsRecognized(path: String, reason: FlixNoiseRules.Reason) {
        #expect(FlixNoiseRules.reason(forPath: path) == reason)
    }

    @Test(arguments: ["/Users/x/Documents/Build plans.pdf", "/Users/x/Documents/Build/Report.pdf",
                      "/Users/x/Desktop/Screenshot 2026-11-20 at 21.18.png", "/Users/x/Downloads/Invoice.pdf",
                      "/Users/x/Documents/target/notes.txt"])
    func ordinaryFilesAreNotNoise(path: String) {
        #expect(FlixNoiseRules.reason(forPath: path) == nil)
    }

    @Test func partialDownloadsKnowTheirFinishedName() {
        #expect(FlixNoiseRules.completedPath(ofPartial: "/d/Report.pdf.crdownload") == "/d/Report.pdf")
        #expect(FlixNoiseRules.completedPath(ofPartial: "/d/Report.pdf") == nil)
        #expect(FlixNoiseRules.completedPath(ofPartial: "/d/blob.part") == nil)
    }

    // MARK: Smart Filters

    @Test func rulesMatchWhatTheySay() {
        let invoice = item("/Users/x/Documents/Finance/Invoice-2026-11.pdf", activity: .downloaded, age: 3_600,
                           host: "www.billing.example.com")
        let match: (FlixSmartFilterRule) -> Bool = { $0.matches(invoice, now: self.now, semantic: { _, _ in nil }) }
        #expect(match(.nameContains("invoice")))
        #expect(!match(.nameContains("receipt")))
        #expect(match(.locationContains("finance")))
        #expect(!match(.locationContains("Invoice")))
        #expect(match(.kind(.document)))
        #expect(match(.activity(.downloaded)))
        #expect(match(.sourceContains("billing")))
        #expect(match(.fileExtension(".PDF")))
        #expect(match(.withinDays(1)))
        #expect(!match(.flagged))
        #expect(match(.about("invoice finance")))
        #expect(!match(.about("invoice travel")))
    }

    @Test func imagesIncludeScreenshots() {
        let shot = item("/d/Screenshot.png", kind: .screenshot)
        #expect(FlixSmartFilterRule.kind(.image).matches(shot, now: now, semantic: { _, _ in nil }))
        #expect(!FlixSmartFilterRule.kind(.screenshot).matches(item("/d/photo.heic", kind: .image), now: now,
                                                                semantic: { _, _ in nil }))
    }

    @Test func allAndAnyCombineRules() {
        let photo = item("/Pictures/Berlin/IMG_1.heic", kind: .image, age: 10 * 86_400)
        let all = FlixSmartFilter(name: "Trips", match: .all, rules: [.kind(.image), .withinDays(7)])
        let any = FlixSmartFilter(name: "Trips", match: .any, rules: [.kind(.image), .withinDays(7)])
        #expect(!all.matches(photo, now: now))
        #expect(any.matches(photo, now: now))
        #expect(!FlixSmartFilter(name: "Empty", rules: []).matches(photo, now: now))
    }

    @Test func aSemanticAnswerOverridesWordMatching() {
        let photo = item("/Pictures/IMG_4821.heic", kind: .image)
        let filter = FlixSmartFilter(name: "Trips", rules: [.about("travel")])
        #expect(!filter.matches(photo, now: now))
        #expect(filter.matches(photo, now: now) { topic, _ in topic == "travel" })
        #expect(!FlixSmartFilter(name: "X", rules: [.about("IMG")]).matches(photo, now: now) { _, _ in false })
    }

    @Test func smartFiltersRoundTripThroughJSON() throws {
        let filter = FlixSmartFilter(name: "Bills", emoji: "🧾", match: .any,
                                     rules: [.nameContains("invoice"), .kind(.document), .withinDays(30), .flagged,
                                             .about("bills and taxes")])
        let decoded = try JSONDecoder().decode(FlixSmartFilter.self, from: JSONEncoder().encode(filter))
        #expect(decoded == filter)
    }

    @Test func sidebarFiltersSelectTheirItems() {
        let folder = FlixFavorite(kind: .folder, path: "/Users/x/Documents/Clients", name: "Clients")
        let inside = item("/Users/x/Documents/Clients/Oak/spec.pdf")
        let outside = item("/Users/x/Documents/ClientsOld/spec.pdf")
        let check: (FlixFilter, FlixItem) -> Bool = {
            $0.matches($1, smartFilters: [], favorites: [folder], threadMembers: nil, now: self.now)
        }
        #expect(check(.favorite(folder.id), inside))
        #expect(!check(.favorite(folder.id), outside))
        #expect(check(.kind(.folders), item("/a/b", kind: .folder)))
        #expect(check(.activity(.flagged), item("/a/c", flagged: true)))
        #expect(!check(.activity(.flagged), item("/a/d")))
        #expect(FlixFilter.thread("t").matches(inside, smartFilters: [], favorites: [], threadMembers: [inside.id], now: now))
    }

    // MARK: Time sections

    @Test func timeSectionsFollowTheCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 21, minute: 20)))
        let group = { (date: Date) in FlixTimeGroup.group(for: date, now: evening, calendar: calendar) }
        #expect(group(evening.addingTimeInterval(-2 * 60)) == .justNow)
        #expect(group(evening.addingTimeInterval(60)) == .justNow)
        #expect(group(evening.addingTimeInterval(-11 * 60)) == .today)
        #expect(group(try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 0, minute: 5)))) == .today)
        #expect(group(try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 23, minute: 59)))) == .yesterday)
        #expect(group(try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12)))) == .earlier)
    }

    @Test func justAfterMidnightTheLastMinutesStayJustNow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 0, minute: 3)))
        #expect(FlixTimeGroup.group(for: midnight.addingTimeInterval(-6 * 60), now: midnight, calendar: calendar) == .justNow)
        #expect(FlixTimeGroup.group(for: midnight.addingTimeInterval(-20 * 60), now: midnight, calendar: calendar) == .yesterday)
    }
}
