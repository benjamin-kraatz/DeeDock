/// A small seeded generator (SplitMix64), so the pile tumbles the same way in tests, previews
/// and snapshots for the same seed. Not for anything security-related.
nonisolated struct VaporSeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniform value in `-1…1`.
    mutating func signed() -> Double { Double.random(in: -1...1, using: &self) }

    /// A uniform value in `range`.
    mutating func value(in range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }
}
