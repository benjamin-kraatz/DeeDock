import Foundation
import Testing
@testable import DeeDock

/// Merging a batch gives the same history as merging its events one by one, and download pages
/// reach a file row only through the link tracker's verified check.
struct FlixHistoryBatchTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ path: String, _ activity: FlixActivity = .opened, at offset: TimeInterval,
                       kind: FlixItemKind = .document, size: Int64? = nil) -> FlixActivityEvent {
        FlixActivityEvent(path: path, name: (path as NSString).lastPathComponent, kind: kind, activity: activity,
                          date: t0.addingTimeInterval(offset), sourceHost: nil, byteSize: size)
    }

    /// What two histories must agree on. Identifiers of items created during the merge are random,
    /// so they are left out; identifiers of items that existed before must match.
    private struct Row: Equatable {
        var key: String, name: String, kind: FlixItemKind, activity: FlixActivity, date: Date, firstSeen: Date
        var host: String?, size: Int64?, flagged: Bool, identity: FlixFileIdentity?
    }

    private func rows(_ document: FlixHistoryDocument) -> [Row] {
        document.items.map {
            Row(key: $0.key, name: $0.name, kind: $0.kind, activity: $0.activity, date: $0.date, firstSeen: $0.firstSeen,
                host: $0.sourceHost, size: $0.byteSize, flagged: $0.isFlagged, identity: $0.fileIdentity)
        }
    }

    private func expectSameMerge(starting document: FlixHistoryDocument, with events: [FlixActivityEvent]) {
        var sequential = document
        var sequentialChanged = false
        for event in events where sequential.record(event) { sequentialChanged = true }
        var batched = document
        let batchChanged = batched.record(batch: events)
        #expect(batchChanged == sequentialChanged)
        #expect(rows(batched) == rows(sequential))
        #expect(batched.removed == sequential.removed)
        #expect(batched.clearedAt == sequential.clearedAt)
        let existing = Set(document.items.map(\.id))
        #expect(batched.items.map(\.id).filter(existing.contains) == sequential.items.map(\.id).filter(existing.contains))
    }

    @Test func aBatchMergesLikeItsEventsInOrder() {
        var start = FlixHistoryDocument.cleared(at: t0)
        start.record(event("/w/flagged.pdf", at: 5))
        start.setFlagged(true, for: [start.items[0].id])
        start.record(event("/w/removed.pdf", at: 6))
        start.remove([start.items.first { $0.name == "removed.pdf" }!.id], at: t0.addingTimeInterval(20))
        start.record(event("/d/Report.pdf.crdownload", .downloaded, at: 7))

        var events: [FlixActivityEvent] = [
            event("/w/old.pdf", at: -5),                          // before the clear: dropped
            event("/w/removed.pdf", at: 15),                      // older than its removal: dropped
            event("/w/removed.pdf", at: 25),                      // newer: comes back
            event("/d/Report.pdf", .downloaded, at: 30),          // replaces the partial download
            event("/w/flagged.pdf", .saved, at: 31, size: 9),     // newer: moves up, keeps the flag
            event("/w/flagged.pdf", .opened, at: 2),              // older: only fills in
            event("/w/same.pdf", .created, at: 40),
            event("/w/same.pdf", .downloaded, at: 40),            // same moment: a download wins
            event("/w/tie-b.pdf", at: 50), event("/w/tie-a.pdf", at: 50),
        ]
        // More noise than the noise cap keeps.
        events += (0..<(FlixHistoryDocument.noiseCapacity + 15)).map { index in
            event("/w/node_modules/pkg/f\(index).js", .created, at: 60 + Double(index))
        }
        expectSameMerge(starting: start, with: events)
    }

    @Test func aBatchEnforcesTheCapacityOnce() {
        var start = FlixHistoryDocument()
        start.record(event("/w/keep.pdf", at: 0))
        start.setFlagged(true, for: [start.items[0].id])
        let events = (0..<(FlixHistoryDocument.capacity + 40)).map { event("/w/f\($0).pdf", at: 10 + Double($0)) }
        // Sequential merging of this many events is equivalent but slow; the rules it shares with
        // the batch are covered above. Here: the cap holds, flagged items are spared, the oldest go.
        var batched = start
        let changed = batched.record(batch: events)
        #expect(changed)
        #expect(batched.items.count == FlixHistoryDocument.capacity)
        #expect(batched.items.contains { $0.isFlagged && $0.name == "keep.pdf" })
        #expect(batched.items.first?.name == "f\(FlixHistoryDocument.capacity + 39).pdf")
        #expect(!batched.items.contains { $0.name == "f0.pdf" })
    }

    @Test func anEmptyOrRedundantBatchChangesNothing() {
        var document = FlixHistoryDocument()
        document.record(event("/w/a.pdf", at: 10))
        let empty = document.record(batch: [])
        let redundant = document.record(batch: [event("/w/a.pdf", at: 10), event("/w/a.pdf", at: 1)])
        #expect(!empty && !redundant)
    }

    // MARK: Download pages

    @Test func eventsNeverStoreAPageAndVerifiedPagesSurviveThePolicy() {
        var settings = FlixSettings()
        settings.tracksLinks = true
        var document = FlixHistoryDocument()
        // As the sources build it: the page goes through the initializer, which derives the host.
        let download = FlixActivityEvent(path: "/d/invoice.pdf", name: "invoice.pdf", kind: .document,
                                         activity: .downloaded, date: t0,
                                         sourcePage: URL(string: "https://billing.example.com/invoices"))
        document.record(batch: [download, event("/d/other.pdf", .downloaded, at: 1)])
        let invoice = document.items.first { $0.name == "invoice.pdf" }
        #expect(invoice?.sourcePage == nil && invoice?.sourceHost == "billing.example.com")

        let attached = document.attachVerifiedSource(URL(string: "https://billing.example.com/invoices")!,
                                                     toPath: "/d/invoice.pdf")
        let unchanged = !document.applySourcePolicy(settings)
        #expect(attached && unchanged)
        let verified = document.items.first { $0.name == "invoice.pdf" }
        #expect(verified?.sourcePage?.absoluteString == "https://billing.example.com/invoices")
        #expect(verified?.sourcePageIsVerified == true)

        // Web links off: the page goes, the host stays, and the marker goes with the page.
        settings.tracksLinks = false
        let strippedAny = document.applySourcePolicy(settings)
        #expect(strippedAny)
        let stripped = document.items.first { $0.name == "invoice.pdf" }
        #expect(stripped?.sourcePage == nil && stripped?.sourcePageIsVerified == nil)
        #expect(stripped?.sourceHost == "billing.example.com")
    }

    @Test func pagesStoredWithoutVerificationAreScrubbedToTheirHost() throws {
        // Written by an earlier version: a full page without the verified marker.
        let json = #"{"items":[{"id":"\#(UUID().uuidString)","path":"/d/f.pdf","name":"f.pdf","kind":"document","activity":"downloaded","date":0,"firstSeen":0,"sourcePage":"https://portal.example.com/statements","sourceHost":"portal.example.com","isFlagged":false}]}"#
        var document = try JSONDecoder().decode(FlixHistoryDocument.self, from: Data(json.utf8))
        var settings = FlixSettings()
        settings.tracksLinks = true
        let scrubbed = document.applySourcePolicy(settings)
        #expect(scrubbed)
        #expect(document.items[0].sourcePage == nil)
        #expect(document.items[0].sourceHost == "portal.example.com")
    }
}
