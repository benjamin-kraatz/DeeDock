// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// What the embedding runtime reports about its model; part of the index fingerprint.
nonisolated struct WorkerInfo: Codable, Sendable {
    let model: String
    let revision: String
    let runtime: String
    let dtype: String
    let dim: Int
    let textOnly: Bool
    /// The time from the start of the load to a warm model, once it's loaded.
    let loadSeconds: Double?

    /// Vectors from different models, revisions, runtimes or precisions must never share an index.
    var vectorSource: String { "\(model)@\(revision.prefix(7)) \(runtime) \(dtype)" }
}
