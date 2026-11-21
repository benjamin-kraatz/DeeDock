import Accelerate
import Foundation

/// The vector math every Flix Files feature that compares by meaning shares: cosine similarity,
/// centroids, and a ranking that keeps only candidates that stand out.
///
/// Vectors are Lookout's: 768 L2-normalized floats (`LookoutFileVector` for files,
/// `FlixSemanticIndex.embed(_:)` for text). Text and picture vectors score on different scales, so
/// callers compare like with like (``isComparable(_:_:)``).
///
/// The thresholds are first guesses, not measurements: Lookout's own search gates on per-query
/// z-scores, and Flix's file-to-file comparisons have no labelled set yet. They live here so tuning
/// one is a one-line change. `docs/FLIX.md` lists the hands-on checks.
///
/// Hook for phase B1's Fits matcher (`FlixFitScoring`, keyword scoring today): a Lookout-backed
/// scorer embeds the window's wanted phrase once (`FlixSemanticIndex.embed(_:)`), reads the
/// candidates' file vectors (`FlixSemanticIndex.vectors(for:)`, cached), and ranks them with
/// ``ranked(_:against:floor:minimumZ:limit:)``. Text-to-file scores run lower than file-to-file
/// ones, so such a scorer should pass its own `floor` (Lookout's z-gate idea: rely on `minimumZ`)
/// and blend the result with the keyword score rather than replace it, keeping the keyword path
/// when Lookout is off.
nonisolated enum FlixSemanticScoring {
    /// Two text-averaged files this close are about the same work (Threads, version families).
    static let relatedText: Float = 0.72
    /// The same for two picture-averaged files, whose scores run higher.
    static let relatedPictures: Float = 0.82
    /// A download fits a folder when it is at least this close to the folder's centroid.
    static let folderFit: Float = 0.62
    /// How far the best folder must lead the runner-up, so a coin toss suggests nothing.
    static let folderMargin: Float = 0.03
    /// More like this keeps candidates at least this close to the source…
    static let similarFloor: Float = 0.55
    /// …that also stand this many standard deviations above the candidates' mean.
    static let similarMinimumZ: Float = 0.8

    /// The cosine similarity of two normalized vectors: their dot product. Zero for mismatched or
    /// empty vectors.
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        return vDSP.dot(a, b)
    }

    /// Whether two file vectors can be compared: both text-averaged or both picture-averaged.
    static func isComparable(_ a: LookoutFileVector, _ b: LookoutFileVector) -> Bool {
        a.isPicture == b.isPicture
    }

    /// Whether two files are about the same thing, by the threshold for their modality.
    static func areRelated(_ a: LookoutFileVector, _ b: LookoutFileVector) -> Bool {
        guard isComparable(a, b) else { return false }
        return cosine(a.vector, b.vector) >= (a.isPicture ? relatedPictures : relatedText)
    }

    /// The normalized mean of `vectors`, or nil when there are none.
    static func centroid(_ vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first, !first.isEmpty else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors where vector.count == sum.count { sum = vDSP.add(sum, vector) }
        let norm = vDSP.sumOfSquares(sum).squareRoot()
        guard norm > 0 else { return nil }
        return vDSP.divide(sum, norm)
    }

    /// Candidates ranked by similarity to `source`, best first, keeping those at least `floor`
    /// close that also stand `minimumZ` standard deviations above the candidates' mean. With fewer
    /// than four candidates the z-score says little, so only the floor applies.
    static func ranked<ID: Hashable>(_ source: [Float], against candidates: [(id: ID, vector: [Float])],
                                     floor: Float = similarFloor, minimumZ: Float = similarMinimumZ,
                                     limit: Int = 12) -> [(id: ID, score: Float)] {
        let scored = candidates.map { (id: $0.id, score: cosine(source, $0.vector)) }
        guard !scored.isEmpty else { return [] }
        let scores = scored.map(\.score)
        let mean = vDSP.mean(scores)
        let deviation = (vDSP.meanSquare(vDSP.add(-mean, scores))).squareRoot()
        let usesZ = scored.count >= 4 && deviation > 0
        return scored
            .filter { $0.score >= floor && (!usesZ || ($0.score - mean) / deviation >= minimumZ) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}
