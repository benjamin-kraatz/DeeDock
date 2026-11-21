import Foundation
import os

/// A local log of Lookout searches and what was opened from them, for training and checking the reranker
/// (`LookoutBench rerank --clicks`, `LookoutBench clicks`). DEE-166.
///
/// It exists only on a Mac where `~/.dokk/controller` exists when DOKK starts: a developer switch with no UI, so
/// nobody turns it on by accident. Everything stays in `Learning/clicks.jsonl` in Lookout's folder; nothing is sent
/// anywhere, and analytics never see it.
///
/// Each line is one `LookoutClickRecord`: a search that ended in an open (a Lookout hit or a Spotlight name result)
/// or ended without one. It keeps the query, every hit Lookout showed with the reranker's features, Spotlight's
/// names, and what was opened, so a gap shows: a file opened from the names that Lookout ranked low or didn't have.
///
/// Encoding happens on the main actor (a search's hits, a few kilobytes); writing happens on a serial queue, so the
/// main actor never waits for the disk. A file past `maximumBytes` is renamed with its date and a new one starts.
final class LookoutClickLog: Sendable {
    /// Past this a log file is set aside and a new one begun.
    static let maximumBytes: UInt64 = 50 << 20

    let file: URL
    private let queue = DispatchQueue(label: "Lookout.ClickLog", qos: .utility)

    init(file: URL) {
        self.file = file
    }

    /// The log, when `~/.dokk/controller` exists; nil otherwise. Checked once, when the engine is made.
    static func ifEnabled(paths: LookoutPaths, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> LookoutClickLog? {
        let controller = home.appending(path: ".dokk/controller", directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: controller.path) else { return nil }
        return LookoutClickLog(file: paths.learning.appending(path: "clicks.jsonl", directoryHint: .notDirectory))
    }

    /// Appends `entry` as one line.
    @MainActor func record(_ entry: LookoutClickRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        let file = file
        queue.async {
            do {
                try Self.append(line, to: file)
            } catch {
                LookoutLog.logger.error("Can't write the Lookout click log: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func append(_ line: Data, to file: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? manager.attributesOfItem(atPath: file.path)[.size] as? UInt64, size > maximumBytes {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try manager.moveItem(at: file, to: file.deletingPathExtension().appendingPathExtension("\(stamp).jsonl"))
        }
        if !manager.fileExists(atPath: file.path) { manager.createFile(atPath: file.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}

extension LookoutClickRecord {
    /// A record of the search `results` show for `query`.
    @MainActor init(event: String, query: String, scope: HubFileSearch.Scope, phase: LookoutSearch.Phase,
                    results: LookoutResultSet, names: [URL], weakExpanded: Bool,
                    opened: LookoutClickRecord.Opened?, now: Date = Date()) {
        let hits = results.all
        let features = LookoutRerankFeatures.rows(query: query, hits: hits, isLookup: results.isLookup, now: now)
        let tuning = LookoutRanking.Tuning()
        let info = Bundle.main.infoDictionary
        at = now
        self.event = event
        app = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        self.query = query
        self.scope = scope.lookoutFolder ?? "thisMac"
        self.phase = "\(phase)"
        usedMeaning = results.usedMeaning
        isLookup = results.isLookup
        terms = results.terms
        dateHint = DateHint.parse(query, now: now)?.interval
        kindHints = Searcher.kindHints(query).map(\.rawValue).sorted()
        ranking = [
            "zGate": tuning.zGate, "wordWeight": tuning.wordWeight, "coverageExponent": tuning.coverageExponent,
            "wordGate": tuning.wordGate, "idfExponent": tuning.idfExponent, "kindHintBonus": tuning.kindHintBonus,
            "nameWeight": tuning.nameWeight, "dateBonus": tuning.dateBonus, "strongRatio": tuning.strongRatio,
            "folderBonusCap": tuning.folderBonusCap,
        ]
        featureVersion = LookoutRerankFeatures.version
        lookout = hits.enumerated().map { index, hit in
            LookoutClickRecord.Hit(
                rank: index + 1, section: index < results.strong.count ? "strong" : "weak", path: hit.path,
                kind: hit.kind?.rawValue, isFolder: hit.isFolder, score: hit.score, z: hit.z, cosine: hit.cosine,
                coverage: hit.coverage, keywordRank: hit.keywordRank, match: "\(hit.match)",
                segment: hit.segment?.rawValue, page: hit.page, hasSnippet: hit.snippet != nil,
                features: features[index])
        }
        self.names = names.prefix(LookoutClickRecord.nameLimit).map(\.path)
        self.weakExpanded = weakExpanded
        self.opened = opened
    }
}
