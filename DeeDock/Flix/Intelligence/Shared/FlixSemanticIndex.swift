import Foundation

/// Flix Files' window onto Lookout: whole-file vectors, text embeddings, and Lookout's own content
/// search, each answering only while Lookout runs.
///
/// Lookout is opt-in and may be off, not set up, or still reading; every method then returns
/// nothing, and callers fall back to names, folders, and time. Nothing here starts Lookout or reads
/// a file: vectors come from Lookout's index, which only holds what the person chose to index.
///
/// Vectors are cached by path, so the 2-second history passes don't read the index again for paths
/// they already asked about; "no vector" answers are forgotten whenever Lookout reports new vectors
/// (`LookoutIndexStatus.vectorsChangedAt`). Misses are fetched in chunks. Main actor; the reads
/// themselves run in Lookout's reader actor.
@MainActor
final class FlixSemanticIndex {
    private let lookout: LookoutEngine?
    /// Nil values remember paths the index holds no vector for.
    private var vectors: [String: LookoutFileVector?] = [:]
    private var version: Date?
    private static let cacheLimit = 8_000
    private static let chunk = 300

    init(lookout: LookoutEngine?) {
        self.lookout = lookout
    }

    /// Lookout runs and can answer.
    var isAvailable: Bool { lookout?.isRunning == true }

    /// The stored whole-file vectors of `paths`; paths without one are left out.
    func vectors(for paths: [String]) async -> [String: LookoutFileVector] {
        guard let lookout, isAvailable, !paths.isEmpty else { return [:] }
        // While Lookout indexes, its vectors change every batch. Only the "no vector yet" answers are
        // dropped then, so newly read files show up without reading every cached vector again; a
        // file read again keeps its earlier vector until the cache is reset or overflows.
        let current = lookout.indexStatus?.vectorsChangedAt
        if vectors.count > Self.cacheLimit {
            vectors = [:]
        } else if current != version {
            vectors = vectors.filter { $0.value != nil }
        }
        version = current
        let missing = Array(Set(paths.filter { vectors[$0] == nil }))
        for start in stride(from: 0, to: missing.count, by: Self.chunk) {
            guard !Task.isCancelled else { break }
            let chunk = Array(missing[start..<min(start + Self.chunk, missing.count)])
            let found = await lookout.storedVectors(forPaths: chunk)
            for path in chunk { vectors[path] = .some(found[path]) }
        }
        var result: [String: LookoutFileVector] = [:]
        for path in paths { if let vector = vectors[path] ?? nil { result[path] = vector } }
        return result
    }

    /// `text` as a query vector, comparable with file vectors. Nil without Lookout or on failure.
    func embed(_ text: String) async -> [Float]? {
        guard let lookout, isAvailable else { return nil }
        return try? await lookout.embed(text: text)
    }

    /// Lookout's ranked content search for `text`: each matching path and whether it matched by
    /// meaning, by words, or both. Nil without Lookout or an index.
    func contentMatches(_ text: String, limit: Int = 80) async -> [String: LookoutHit.Match]? {
        guard let lookout, isAvailable, let results = await lookout.contentMatches(for: text, limit: limit) else {
            return nil
        }
        var matches: [String: LookoutHit.Match] = [:]
        for hit in results.all where !hit.isFolder { matches[FlixPaths.standardized(hit.path)] = hit.match }
        return matches
    }
}
