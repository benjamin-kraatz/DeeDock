import Foundation
import Testing
@testable import DeeDock

/// Plain-words search without a model: English and German sentences become activity, kind, time,
/// amount, place, site, and a topic, and those become tokens and matches.
struct FlixQueryParserTests {
    @Test func englishSentenceWithActivityTimeAndTopic() {
        let query = FlixQueryParser.parse("contract Mike sent last week")
        #expect(query.activity == .downloaded)
        #expect(query.days == 7)
        #expect(query.timePhrase == .week)
        #expect(query.topic == "contract Mike")
        #expect(query.kinds.isEmpty)
    }

    @Test func amountsLeaveTheTopic() {
        let query = FlixQueryParser.parse("invoices over €1,000")
        #expect(query.minimumAmount == 1_000)
        #expect(query.currency == "EUR")
        #expect(query.topic == "invoices")
    }

    @Test func kindsBecomeKindsNotTopic() {
        let screenshot = FlixQueryParser.parse("screenshot with the build error")
        #expect(screenshot.kinds == [.screenshot])
        #expect(screenshot.topic == "build error")

        let photos = FlixQueryParser.parse("photos from yesterday")
        #expect(photos.kinds == [.image])
        #expect(photos.days == 2)
        #expect(photos.topic == nil)
    }

    @Test func placesExtensionsAndSites() {
        let query = FlixQueryParser.parse("PDFs in Downloads from today")
        #expect(query.folder == "Downloads")
        #expect(query.extensions == ["pdf"])
        #expect(query.days == 1)
        #expect(query.topic == nil)

        let site = FlixQueryParser.parse("zip from github.com")
        #expect(site.site == "github.com")
        #expect(site.extensions == ["zip"])
    }

    @Test func germanSentences() {
        let invoices = FlixQueryParser.parse("Rechnungen über 1.000 €")
        #expect(invoices.minimumAmount == 1_000)
        #expect(invoices.currency == "EUR")
        #expect(invoices.topic == "Rechnungen")

        let contract = FlixQueryParser.parse("Vertrag, den Mike letzte Woche geschickt hat")
        #expect(contract.activity == .downloaded)
        #expect(contract.days == 7)
        #expect(contract.topic == "Vertrag Mike")

        let photos = FlixQueryParser.parse("Fotos von gestern")
        #expect(photos.kinds == [.image])
        #expect(photos.days == 2)
        #expect(photos.topic == nil)
    }

    @Test func typedCasingSurvivesForTheTopic() {
        #expect(FlixQueryParser.cased("oak ash", in: "everything for Oak & Ash") == "Oak & Ash")
    }

    // MARK: Matching

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ name: String, folder: String = "/Users/test/Downloads", kind: FlixItemKind = .document) -> FlixItem {
        FlixItem(path: folder + "/" + name, name: name, kind: kind, activity: .downloaded, date: now.addingTimeInterval(-3_600))
    }

    @Test func amountAndTopicNarrowTogether() {
        let november = item("Invoice-2026-11.pdf"), october = item("Invoice-2026-10.pdf"), contract = item("Signed contract.pdf")
        let context = FlixSearchMatcher.Context(totals: [november.id: 1_240, october.id: 900])
        let matches = FlixSearchMatcher.matches([.about("invoices"), .amountOver(1_000)],
                                                in: [november, october, contract], context: context, now: now)
        #expect(matches == [november.id: .name])
    }

    @Test func captionsAndLookoutMatchByMeaning() {
        let quote = item("document (3).pdf"), photo = item("IMG_4821.jpg", kind: .image), other = item("notes.txt")
        let context = FlixSearchMatcher.Context(captions: [quote.id: "Oak & Ash packaging quote, 3 options"],
                                                meaningPaths: [photo.path!])
        let matches = FlixSearchMatcher.matches([.about("packaging quote")], in: [quote, photo, other],
                                                context: context, now: now)
        #expect(matches[quote.id] == .meaning)
        #expect(matches[photo.id] == .meaning)
        #expect(matches[other.id] == nil)
    }

    @Test func structuralRulesStillApply() {
        let old = FlixItem(path: "/Users/test/Downloads/report.pdf", name: "report.pdf", kind: .document,
                           activity: .downloaded, date: now.addingTimeInterval(-10 * 86_400))
        let fresh = item("report.pdf", folder: "/Users/test/Documents")
        let matches = FlixSearchMatcher.matches([.withinDays(7), .about("report")], in: [old, fresh],
                                                context: .init(), now: now)
        #expect(matches == [fresh.id: .name])
    }
}
