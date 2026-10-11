// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// What produced a segment's vector. Scores are normalized per modality because text vectors score higher than
/// image vectors for the same topic (measured: 0.75–0.86 vs 0.67–0.78). `none` marks a segment without a vector.
nonisolated enum Modality: String, Sendable, CaseIterable {
    case none, text, image
}
