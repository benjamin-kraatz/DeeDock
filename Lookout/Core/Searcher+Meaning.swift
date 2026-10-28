// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Accelerate

/// Meaning scores: every stored vector against the query, put on this query's own scale.
nonisolated extension Searcher {
    /// This query's meaning scores: each vector's cosine similarity minus the average of its modality (text and image
    /// vectors can sit at slightly different levels for the same query), in standard deviations of all of them
    /// together. Within a modality that's the model's own order. Scaling each modality by its own deviation instead
    /// inflated the narrow ones and buried PDF pages under pictures (2026-10-08, on DigUp's three evals: 91 → 94 of
    /// 105 queries with the right answer first).
    ///
    /// The scale (the averages and the deviation) comes from the vectors in `setsScale` (all by default): `search`
    /// leaves out the later pages of long files, which are scored on it but don't move it. A book's hundreds of pages
    /// pulled the text average down for every query, and documents rose over screenshots everywhere (2026-10-09:
    /// real eval 24 → 22 of 26 first; 24 with the scale kept).
    static func meaning(_ scores: [Float], _ modality: [Modality], setsScale: [Bool]? = nil) -> [Double] {
        let means = modalityMeans(scores, modality, setsScale: setsScale)
        let centered = zip(scores, modality).map { Double($0) - means[$1, default: 0] }
        var count = 0.0, sum = 0.0
        for row in centered.indices where setsScale?[row] ?? true {
            count += 1
            sum += centered[row]
        }
        let mean = sum / max(count, 1)
        var squares = 0.0
        for row in centered.indices where setsScale?[row] ?? true {
            squares += (centered[row] - mean) * (centered[row] - mean)
        }
        let deviation = max((squares / max(count, 1)).squareRoot(), 0.02)
        return centered.map { ($0 - mean) / deviation }
    }

    /// A picture's and typed words' meaning scores as one query's: their weighted sum, put on its own scale again.
    ///
    /// Each side is already on its own query's scale (`meaning`), so neither drowns the other by its raw cosines: a
    /// picture's cosines to pictures run far above a sentence's. Summing them narrows the spread (the two disagree
    /// on most files), so the sum is standardized once more and `LookoutRanking.zGate` keeps its meaning. The scale
    /// comes from the rows in `setsScale`, as in `meaning`.
    ///
    /// A plain weighted sum of the two vectors ranked as well at its best weight, but that weight depends on how far
    /// apart the two sit in this index; the scores' sum doesn't (2026-10-28, DEE-126: MRR 0.763 vs 0.754 on 67 cases).
    ///
    /// - Parameter weight: How much the words count, 0…1 (`LookoutRanking.pictureWordsWeight`).
    static func blend(_ picture: [Double], _ words: [Double], weight: Double, setsScale: [Bool]? = nil) -> [Double] {
        let weight = min(max(weight, 0), 1)
        let blended = zip(picture, words).map { (1 - weight) * $0 + weight * $1 }
        var count = 0.0, sum = 0.0
        for row in blended.indices where setsScale?[row] ?? true {
            count += 1
            sum += blended[row]
        }
        let mean = sum / max(count, 1)
        var squares = 0.0
        for row in blended.indices where setsScale?[row] ?? true {
            squares += (blended[row] - mean) * (blended[row] - mean)
        }
        let deviation = max((squares / max(count, 1)).squareRoot(), 0.02)
        return blended.map { ($0 - mean) / deviation }
    }

    /// The average score of each modality for this query. Small groups (< 20 vectors) take the average of all.
    static func modalityMeans(_ scores: [Float], _ modality: [Modality], setsScale: [Bool]? = nil) -> [Modality: Double] {
        var sum: [Modality: Double] = [:], count: [Modality: Int] = [:]
        for row in scores.indices where setsScale?[row] ?? true {
            sum[modality[row], default: 0] += Double(scores[row])
            count[modality[row], default: 0] += 1
        }
        let all = sum.values.reduce(0, +) / Double(max(count.values.reduce(0, +), 1))
        var out: [Modality: Double] = [:]
        for modality in Modality.allCases {
            if let n = count[modality], n >= 20 {
                out[modality] = sum[modality]! / Double(n)
            } else {
                out[modality] = all
            }
        }
        return out
    }

    /// Cosine similarity of `query` with every stored vector (all are L2-normalized): a matrix-vector product, done a
    /// block of rows at a time, each block turned into float32 first.
    func score(_ query: [Float]) -> [Float] {
        let rows = vectorCount
        var scores = [Float](repeating: 0, count: rows)
        guard let matrix, rows > 0 else { return scores }
        query.withUnsafeBufferPointer { query in
            scores.withUnsafeMutableBufferPointer { scores in
                var row = 0
                while row < rows {
                    let count = min(VectorStorage.blockRows, rows - row)
                    Vectors.floats(fromHalf: matrix.halves + row * Vectors.dimension, count: count * Vectors.dimension,
                                   to: matrix.block)
                    // (count × 768) · (768 × 1)
                    vDSP_mmul(matrix.block, 1, query.baseAddress!, 1, scores.baseAddress! + row, 1,
                              vDSP_Length(count), 1, vDSP_Length(Vectors.dimension))
                    row += count
                }
            }
        }
        return scores
    }
}
