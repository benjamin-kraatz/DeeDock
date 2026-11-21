import Foundation

/// One known-item search case for `LookoutBench eval`: a query and the files that answer it.
///
/// Cases are stored one JSON object per line (JSONL), so generators can append to a file and resume where they
/// stopped. `queries` writes them from the index; hand-written sets use the same fields.
struct EvalCase: Codable, Hashable {
    /// What the person types.
    var q: String
    /// The files that answer the query, as absolute paths (`~` allowed). The case's rank is that of its best answer.
    var expect: [String]
    /// `de` or `en`.
    var lang: String
    /// What kind of query it is (`EvalCase.Style`'s raw values, or a hand-written set's own tags).
    var style: String
    /// Who wrote it: `fm` (Apple's on-device model), `digup` (DigUp's hand-written evals) or `claude` (the hard set).
    var source: String
    /// `tune` or `held`: every case of one file lands on the same side, so the held-out half never shares a file
    /// with the half the weights are fitted on.
    var split: String
    /// The share of the query's content words that appear in its file's name or text (`Searcher.terms`), 0…1. High
    /// means the query copies the file; low means it paraphrases it.
    var overlap: Double?
    /// The day relative dates in the query ("letzten März") were written against, as yyyy-MM-dd.
    var asOf: String?

    /// The query styles `queries` asks for.
    enum Style: String, CaseIterable {
        /// A vague memory of what's in the file.
        case vague
        /// Names the kind of file ("Screenshot", "PDF", "Foto") and what it shows.
        case kind
        /// One exact detail: a name, an amount, a number, a code.
        case detail
        /// When the file is from, in words ("vom letzten Sommer", "aus 2024").
        case date
    }

    /// The side of the split for a file: a stable hash of its path, half and half.
    static func split(for path: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash % 2 == 0 ? "tune" : "held"
    }

    /// Reads every case from JSONL files; blank lines and lines starting with `#` are skipped.
    ///
    /// - Throws: `BenchFailure` naming the file and line that doesn't decode.
    static func load(_ files: [URL]) throws -> [EvalCase] {
        let decoder = JSONDecoder()
        var cases: [EvalCase] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
            for (number, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                do {
                    cases.append(try decoder.decode(EvalCase.self, from: Data(trimmed.utf8)))
                } catch {
                    throw BenchFailure("\(file.lastPathComponent):\(number + 1): \(error)")
                }
            }
        }
        return cases
    }

    /// One JSONL line.
    func line() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

/// Appends lines to a file, creating it first, and flushes each one: a generator stopped halfway keeps what it wrote.
final class LineWriter {
    private let handle: FileHandle

    init(_ file: URL) throws {
        if !FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
    }

    func write(_ line: String) throws {
        try handle.write(contentsOf: Data((line + "\n").utf8))
    }

    deinit { try? handle.close() }
}
