import CoreGraphics

/// Whether a pointer that has left the cards should keep the enlarged preview.
///
/// Leaving a card used to dismiss the stage after a short grace, which made the picture impossible
/// to reach. The rule now: inside the hero block the stage is held and shows its toolbar; inside the
/// corridor between the Peek panel and the hero (their bounding box) the stage waits a little longer
/// for the pointer to arrive; anywhere else it dismisses as before, so moving away still closes.
nonisolated enum WindowPeekEnlargeHold {
    enum Retention: Equatable, Sendable {
        case hero, corridor, none
    }

    /// How long the pointer may spend in the corridor before the stage gives up on it.
    static let corridorGrace: Duration = .milliseconds(650)

    /// - Parameters:
    ///   - pointer: The pointer in AppKit screen coordinates.
    ///   - hero: The hero block (image, placard, and toolbar) in the same coordinates.
    ///   - peek: The Peek panel's frame.
    static func retention(pointer: CGPoint, hero: CGRect, peek: CGRect) -> Retention {
        if hero.contains(pointer) { return .hero }
        if hero.union(peek).contains(pointer) { return .corridor }
        return .none
    }
}
