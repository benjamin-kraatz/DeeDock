import SwiftUI

/// Timings and curves shared by the orb, the panel and the windows, so the delete sequence
/// lines up: rows are pulled into the orb, the panel shrinks back into it, then the orb
/// evaporates and the capsule appears.
nonisolated enum VaporMotion {
    /// How long one row takes to fly into the orb.
    static let rowPullDuration: Double = 0.38
    /// The delay between neighbouring rows starting to fly.
    static let rowPullStagger: Double = 0.04

    /// The latest a row may start flying. The Undo window opens when staging finishes, and the
    /// capsule waits for the sequence, so a long list must not eat into those 5 seconds.
    static let rowPullMaxDelay: Double = 0.4

    /// When row `index` starts flying into the orb.
    static func rowPullDelay(index: Int) -> Double { min(Double(index) * rowPullStagger, rowPullMaxDelay) }

    /// When the panel starts shrinking after a delete pulled `rows` rows into the orb.
    static func panelCloseDelay(rows: Int) -> Double { 0.3 + rowPullDelay(index: rows) }

    /// When the orb starts evaporating after a delete, so it follows the rows and the panel.
    static func evaporateDelay(rows: Int, fromPanel: Bool) -> Double {
        fromPanel ? panelCloseDelay(rows: rows) + 0.2 : 0
    }

    /// The panel growing out of the orb: a spring with a little overshoot.
    static let panelOpen = Animation.spring(response: 0.5, dampingFraction: 0.72)
    /// The panel shrinking back into the orb.
    static let panelClose = Animation.timingCurve(0.5, 0, 0.8, 0.3, duration: 0.28)
    /// How long the panel window waits for its shrink before ordering out.
    static let panelCloseDuration: Double = 0.3
    /// A row flying into the orb: slow start, fast finish.
    static let rowPull = Animation.timingCurve(0.55, 0, 0.75, 0.2, duration: rowPullDuration)
    /// Rows sliding in from the side as folders arrive.
    static let rowEnter = Animation.spring(response: 0.42, dampingFraction: 0.7)
    /// Bubbles springing out of the orb; staggered per bubble.
    static let bubbleEnter = Animation.spring(response: 0.55, dampingFraction: 0.62)
    static let bubbleStagger: Double = 0.055
    /// Bubbles and their capsule gliding to new places when the arc changes.
    static let bubbleGlide = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// A clicked bubble diving into the orb (slow start, fast finish), and when its folder is
    /// added: just before the bubble vanishes behind the glass, so the folder drops out of it.
    static let bubbleEat = Animation.timingCurve(0.5, 0, 0.75, 0.2, duration: 0.34)
    static let bubbleEatDelay: Double = 0.3
    /// Add All eats the bubbles one after another.
    static let addAllStagger: Double = 0.09
    /// A size counting up once it's measured.
    static let countUp = Animation.timingCurve(0.33, 1, 0.68, 1, duration: 0.65)
    /// Capsules popping in above the orb.
    static let capsuleEnter = Animation.spring(response: 0.35, dampingFraction: 0.68)

    /// The orb condensing when Vapor turns on: a scale spring that overshoots a little.
    static let orbEnter = Animation.spring(response: 0.42, dampingFraction: 0.58)
    /// The small swell before the orb shrinks away, and the shrink itself.
    static let orbExitSwell: Double = 0.08
    static let orbExitShrink: Double = 0.24
    /// The plain fade that replaces both under Reduce Motion.
    static let orbFade: Double = 0.2
    /// How long the particles take to gather into the orb.
    static let orbCondense: Double = 0.65

    /// How long the orb takes to leave, so its windows can be closed afterwards.
    static func orbExitDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? orbFade : orbExitSwell + orbExitShrink
    }
}
