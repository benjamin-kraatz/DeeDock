import Foundation
@testable import DeeDock

/// A temporary index with synthetic vectors, for ranking tests. The query is the unit vector on axis 0; every segment
/// vector is a unit vector with a chosen cosine to it (`cosine × e₀ + √(1 − cosine²) × eⱼ`, a fresh axis j each), so a
/// test sets how far a file stands out in meaning.
///
/// `background` adds a spread of unrelated files (cosines evenly spread over ±0.06), which gives the per-query scale
/// (`Searcher.meaning`) a distribution: a file at 0.5 then stands far above the z gate, one at 0.06 below it.
final class LookoutSearchIndex {
    let folder = LookoutTestFolder()
    let store: IndexStore
    private var nextAxis = 1
    private var nextInode: UInt64 = 1

    init() throws {
        store = try IndexStore(directory: folder.url.appendingPathComponent("index"))
    }

    /// The query vector all tests search with.
    static let query: [Float] = (0..<Vectors.dimension).map { $0 == 0 ? 1 : 0 }

    /// The absolute path of `relative` inside the test folder (nothing is written there).
    func path(_ relative: String) -> String { folder.path + "/" + relative }

    /// Adds a done file with one segment.
    ///
    /// - Parameters:
    ///   - cosine: The segment vector's cosine to `query`; nil for a segment with words only.
    ///   - text: Words for keyword search in that segment.
    @discardableResult
    func add(_ relative: String, kind: FileKind = .doc, cosine: Double? = nil, text: String? = nil,
             segment: SegmentKind = .chunk, loc: Double? = 1, excerpt: String? = nil) throws -> Int64 {
        let id = try store.insert(Candidate(path: path(relative), kind: kind, size: 100, mtime: 1, inode: nextInode,
                                            device: 1, lastUsed: nil))
        nextInode += 1
        let modality: Modality = segment == .image || segment == .pageImage ? .image : .text
        try store.addSegment(file: id, kind: segment, modality: modality, loc: loc, excerpt: excerpt, text: text,
                             vector: cosine.map(vector))
        try store.finish(id, state: "done")
        return id
    }

    /// Adds another segment to file `id` (a PDF's further pages).
    func segment(of id: Int64, kind: SegmentKind = .page, cosine: Double? = nil, text: String? = nil, loc: Double? = nil,
                 excerpt: String? = nil) throws {
        let modality: Modality = kind == .image || kind == .pageImage ? .image : .text
        try store.addSegment(file: id, kind: kind, modality: modality, loc: loc, excerpt: excerpt, text: text,
                             vector: cosine.map(vector))
    }

    /// Adds `count` unrelated text files under `background/`.
    func background(_ count: Int = 60) throws {
        for index in 0..<count {
            let cosine = -0.06 + 0.12 * Double(index) / Double(max(count - 1, 1))
            try add("background/b\(index).txt", cosine: cosine)
        }
    }

    func searcher(loadVectors: Bool = true) throws -> Searcher {
        try Searcher(store: store, loadVectors: loadVectors)
    }

    private func vector(_ cosine: Double) -> [Float] {
        precondition(nextAxis < Vectors.dimension, "out of axes")
        var vector = [Float](repeating: 0, count: Vectors.dimension)
        vector[0] = Float(cosine)
        vector[nextAxis] = Float((1 - cosine * cosine).squareRoot())
        nextAxis += 1
        return vector
    }
}
