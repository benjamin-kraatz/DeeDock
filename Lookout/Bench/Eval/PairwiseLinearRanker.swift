import Foundation

/// A linear reranker learned from pairs (RankNet with a linear scorer): for every query, each hit that answers it
/// should score above each hit that doesn't. Features are standardized on the training rows, so the learned weights
/// read as "how much one standard deviation of this feature moves a hit".
///
/// Pairwise rather than pointwise because the task is an order within one query; a pointwise model has to learn
/// that "z = 3" means different things for different queries, and on generated queries it overfit that (DEE-166).
struct PairwiseLinearRanker {
    private(set) var weights: [Double]
    private let means: [Double]
    private let deviations: [Double]

    /// Trains on `queries`: each a list of feature rows and which rows answer it.
    ///
    /// - Parameters:
    ///   - epochs: Passes over all pairs.
    ///   - rate: The step size.
    ///   - l2: How strongly weights are pulled back to zero.
    init(queries: [(features: [[Double]], labels: [Bool])], epochs: Int = 30, rate: Double = 0.05, l2: Double = 1e-4) {
        let rows = queries.flatMap(\.features)
        let width = rows.first?.count ?? 0
        let count = Double(max(rows.count, 1))
        means = (0..<width).map { column in rows.reduce(0) { $0 + $1[column] } / count }
        deviations = (0..<width).map { [means] column in
            let variance = rows.reduce(0) { $0 + pow($1[column] - means[column], 2) } / count
            return max(variance.squareRoot(), 1e-6)
        }
        weights = Array(repeating: 0, count: width)

        let standardized = queries.map { query in (query.features.map(standardize), query.labels) }
        var random = SeededRandom(seed: 7)
        for _ in 0..<epochs {
            for (features, labels) in standardized.shuffled(using: &random) {
                let positives = labels.indices.filter { labels[$0] }
                guard !positives.isEmpty, positives.count < labels.count else { continue }
                var gradient = Array(repeating: 0.0, count: width)
                var pairs = 0.0
                for positive in positives {
                    for negative in labels.indices where !labels[negative] {
                        let margin = dot(features[positive]) - dot(features[negative])
                        // d/dw of log(1 + e^(−margin)) is −σ(−margin) × (x⁺ − x⁻).
                        let pull = 1 / (1 + exp(margin))
                        for column in 0..<width {
                            gradient[column] += pull * (features[positive][column] - features[negative][column])
                        }
                        pairs += 1
                    }
                }
                for column in 0..<width {
                    weights[column] += rate * (gradient[column] / pairs - l2 * weights[column])
                }
            }
        }
    }

    /// A hit's score; only its order among the query's other hits means anything.
    func score(_ features: [Double]) -> Double {
        dot(standardize(features))
    }

    private func standardize(_ row: [Double]) -> [Double] {
        zip(row, zip(means, deviations)).map { ($0 - $1.0) / $1.1 }
    }

    private func dot(_ row: [Double]) -> Double {
        zip(row, weights).reduce(0) { $0 + $1.0 * $1.1 }
    }
}

extension SeededRandom: RandomNumberGenerator {}
