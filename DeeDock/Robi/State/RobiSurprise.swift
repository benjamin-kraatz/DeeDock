import Foundation

/// Robi startled for a moment: a picked region just flew into its face.
///
/// Set on `RobiEyes` by the controller when the flight lands and cleared `duration` later. The
/// face draws the whole reaction from `start`, like `RobiDizzy`, so nothing else has to be
/// scheduled for it. A new pick while one is showing replaces it, and the reaction starts over.
nonisolated struct RobiSurprise: Equatable, Sendable {
    /// When the piece landed. The face animates from here for `duration`.
    let start: Date

    /// Wide eyes and a round mouth, then back to the prompting face.
    static let duration: TimeInterval = 0.55
}
