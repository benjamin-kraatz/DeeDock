import Foundation

/// What Flix Files learned from reading one file: its caption, a better name, and key facts.
///
/// Cached by path and invalidated by ``stamp`` (modification date and size), so a file is read and
/// sent to Apple Intelligence once per version, not on every history pass.
nonisolated struct FlixAnalysisRecord: Codable, Equatable, Sendable {
    /// Bump to analyze every file again after the analysis changes.
    /// 2: no facts from data and code files; key words as whole words; model facts need the text.
    /// 3: the auto-debit fact.
    static let currentVersion = 3

    var version = FlixAnalysisRecord.currentVersion
    var stamp: FlixFileStamp
    /// A one-line description, only for files whose names say nothing.
    var caption: String?
    /// A safe file name (extension kept) offered as "✦ Rename"; nil when the current name is fine.
    var suggestedName: String?
    var facts: [FlixFactValue] = []
    /// Apple Intelligence took part. A record made without it is redone once the model is ready.
    var usedAppleIntelligence = false
    /// The model was asked but returned nothing (unavailable, refused, timed out). Not retried for
    /// a day.
    var modelFailed = false
    var analyzedAt: Date

    /// The document's total, for "over €1,000" searches.
    var total: Double? {
        facts.lazy.compactMap { if case .amount(let value, _) = $0 { value } else { nil } }.first
    }
}

/// The analysis cache on disk: `analysis.json` in Flix Files' Application Support folder, written
/// behind the same debounce as the history (`FlixJSONFile`). Holds at most ``limit`` records; the
/// least recently analyzed go first. An unreadable file is moved aside and the cache starts empty.
/// Main actor.
@MainActor
final class FlixAnalysisStore {
    nonisolated struct Document: Codable, Sendable {
        var records: [String: FlixAnalysisRecord] = [:]
    }

    static let limit = 3_000
    private(set) var records: [String: FlixAnalysisRecord] = [:]
    private let file: FlixJSONFile<Document>?

    /// - Parameter folder: Where `analysis.json` lives; nil keeps the cache in memory (tests, previews).
    init(folder: URL?) {
        file = folder.map { FlixJSONFile(url: $0.appending(path: "analysis.json"), delay: .seconds(2)) }
    }

    func load() {
        guard let file else { return }
        do {
            records = try file.load()?.records.filter { $0.value.version == FlixAnalysisRecord.currentVersion } ?? [:]
        } catch {
            file.quarantine()
            records = [:]
        }
    }

    subscript(path: String) -> FlixAnalysisRecord? { records[path] }

    func set(_ record: FlixAnalysisRecord, for path: String) {
        records[path] = record
        if records.count > Self.limit {
            let excess = records.count - Self.limit
            for key in records.sorted(by: { $0.value.analyzedAt < $1.value.analyzedAt }).prefix(excess).map(\.key) {
                records[key] = nil
            }
        }
        save()
    }

    /// A file was renamed or moved by Flix Files: its analysis follows it, minus the rename
    /// suggestion when the new name already says enough.
    func move(from old: String, to new: String, newName: String) {
        guard var record = records.removeValue(forKey: old) else { return }
        if !FlixFileNaming.isCryptic(newName) {
            record.suggestedName = nil
            record.caption = nil
        }
        records[new] = record
        save()
    }

    /// Drops records of files no longer in the history.
    func prune(keeping paths: Set<String>) {
        let before = records.count
        records = records.filter { paths.contains($0.key) }
        if records.count != before { save() }
    }

    func flush() { file?.flush() }

    private func save() { file?.schedule(Document(records: records)) }
}
