import Foundation
import Testing
@testable import DeeDock

/// The developer click log (DEE-166): off unless `~/.dokk/controller` exists, and its lines read back.
@MainActor
struct LookoutClickLogTests {
    @Test func itExistsOnlyWithTheControllerFile() throws {
        let home = LookoutTestFolder()
        let paths = LookoutPaths(base: home.url.appending(path: "Lookout", directoryHint: .isDirectory))
        #expect(LookoutClickLog.ifEnabled(paths: paths, home: home.url) == nil)
        try home.write(".dokk/controller", Data())
        let log = try #require(LookoutClickLog.ifEnabled(paths: paths, home: home.url))
        #expect(log.file.path.hasPrefix(paths.learning.path))
    }

    @Test func aRecordedSearchReadsBack() async throws {
        let folder = LookoutTestFolder()
        let log = LookoutClickLog(file: folder.url.appending(path: "clicks.jsonl"))
        let index = try LookoutSearchIndex()
        try index.add("bills/RE-24-0815.pdf", kind: .pdf, text: "Rechnung RE-24-0815")
        let results = try index.searcher().search("RE-24-0815", queryVector: nil)
        log.record(LookoutClickRecord(
            event: "open", query: "RE-24-0815", scope: .thisMac, phase: .done, results: results,
            names: [URL(fileURLWithPath: "/tmp/a.pdf")], weakExpanded: false,
            opened: .init(source: "lookout", path: index.path("bills/RE-24-0815.pdf"), rank: 1, lookoutRank: 1)))

        // The write happens on the log's queue; wait for the line.
        var text = ""
        for _ in 0..<100 where text.isEmpty {
            text = (try? String(contentsOf: log.file, encoding: .utf8)) ?? ""
            if text.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(LookoutClickRecord.self, from: Data(text.utf8))
        #expect(record.query == "RE-24-0815" && record.isLookup && record.opened?.lookoutRank == 1)
        #expect(record.lookout.map(\.path) == [index.path("bills/RE-24-0815.pdf")])
        #expect(record.lookout[0].features.count == LookoutRerankFeatures.names.count)
    }
}
