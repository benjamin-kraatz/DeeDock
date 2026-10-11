// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// Why an embedding runtime can't run at all, as opposed to one input it can't embed (`Embedding.error`).
nonisolated enum WorkerError: Error, CustomStringConvertible {
    case notFound(String), failed(String), died(String)

    var description: String {
        switch self {
        case .notFound(let why): "worker not found: \(why)"
        case .failed(let why): "worker error: \(why)"
        case .died(let why): "worker stopped: \(why)"
        }
    }
}
