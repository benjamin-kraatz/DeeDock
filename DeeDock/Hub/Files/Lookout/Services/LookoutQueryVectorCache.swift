// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// Recent query vectors by text: retyping or going back to an earlier query costs nothing. The oldest entry goes
/// first once `limit` is reached. Vectors stay valid across query-service relaunches (same model).
nonisolated struct LookoutQueryVectorCache {
    let limit: Int
    private var vectors: [String: [Float]] = [:]
    private var order: [String] = []

    init(limit: Int) {
        self.limit = limit
    }

    subscript(text: String) -> [Float]? {
        get { vectors[text] }
        set {
            guard let newValue else { return }
            if vectors.updateValue(newValue, forKey: text) == nil { order.append(text) }
            if order.count > limit { vectors[order.removeFirst()] = nil }
        }
    }

    mutating func removeAll() {
        vectors = [:]
        order = []
    }
}
