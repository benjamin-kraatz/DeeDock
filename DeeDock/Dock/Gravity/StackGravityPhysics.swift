import CoreGraphics
import Foundation

/// Soft attraction of nearby dock icons toward pinned folder stacks.
///
/// Offsets are presentation-only. Resting centers, hit testing, and magnification stay on the
/// unpulled layout so icons do not chase the pointer. Snap decisions use the same wells and a
/// separate radius so a release can commit a pin next to a stack.
nonisolated enum StackGravityPhysics {
    /// Largest along-axis drift, as a fraction of one resting slot, at full strength.
    static let maxPullFraction: CGFloat = 0.35
    /// Distance, in slots, at which pull falls to zero.
    static let pullRadiusSlots: CGFloat = 2.75
    /// Distance, in slots, that can snap a released pin beside a stack at full strength.
    static let snapRadiusSlots: CGFloat = 1.65
    /// Lowest snap radius scale so a faint setting still has a usable well.
    static let minimumSnapStrength: CGFloat = 0.55
    /// Focus mute keeps a hint of pull without the full idle motion.
    static let focusMuteFactor: CGFloat = 0.25

    /// Inputs shared by pull and snap. Strength is already Focus- and enable-adjusted.
    struct Configuration: Equatable, Sendable {
        var strength: CGFloat
        var iconSize: CGFloat
        var itemSpacing: CGFloat

        var slot: CGFloat { max(1, iconSize + itemSpacing) }
        var maxPull: CGFloat { slot * maxPullFraction * strength }
        var pullRadius: CGFloat { slot * pullRadiusSlots }
        var snapRadius: CGFloat { slot * snapRadiusSlots * max(minimumSnapStrength, strength) }
        /// Keep pulled icons from covering a neighbor. Gravity may close the configured gap.
        var minimumSeparation: CGFloat { max(4, iconSize * 0.62) }
    }

    /// A release that should land beside a stack instead of at the pointer's raw insertion.
    struct Snap: Equatable, Sendable {
        /// Insertion index in the persisted pin list.
        var pinIndex: Int
        /// Pin-list index of the attracting folder stack.
        var wellPinIndex: Int
    }

    /// Pin-list indices of folder stacks. Downloads lives in the utility section, not here.
    static func wellPinIndices(in pins: [DockPin]) -> Set<Int> {
        Set(pins.enumerated().compactMap { index, pin in
            pin.folder == nil ? nil : index
        })
    }

    /// Along-axis deltas toward nearby wells. Well items stay at their resting centers.
    static func pullOffsets(
        centers: [CGFloat],
        wellIndices: Set<Int>,
        configuration: Configuration
    ) -> [CGFloat] {
        let count = centers.count
        guard count > 0 else { return [] }
        guard configuration.strength > 0, configuration.maxPull > 0, !wellIndices.isEmpty else {
            return Array(repeating: 0, count: count)
        }
        var proposed = centers
        for index in centers.indices where !wellIndices.contains(index) {
            guard let well = nearestWell(to: centers[index], centers: centers, wells: wellIndices) else { continue }
            let delta = centers[well] - centers[index]
            let distance = abs(delta)
            guard distance > 0, distance < configuration.pullRadius else { continue }
            let influence = 1 - distance / configuration.pullRadius
            proposed[index] = centers[index] + configuration.maxPull * influence * influence * (delta > 0 ? 1 : -1)
        }
        for well in wellIndices where well < count {
            proposed[well] = centers[well]
        }
        enforceOrder(proposed: &proposed, wells: wellIndices, configuration: configuration)
        return zip(proposed, centers).map { $0 - $1 }
    }

    /// Centers after applying ``pullOffsets(centers:wellIndices:configuration:)``.
    static func pulledCenters(
        centers: [CGFloat],
        wellIndices: Set<Int>,
        configuration: Configuration
    ) -> [CGFloat] {
        zip(centers, pullOffsets(centers: centers, wellIndices: wellIndices, configuration: configuration)).map(+)
    }

    /// Pin insertion beside the nearest stack when `along` sits inside that well.
    ///
    /// Returns `nil` when strength is zero, no well is in range, or `ignoredPinIndex` is the well
    /// itself. The pointer side of the stack chooses before versus after.
    static func snap(
        along: CGFloat,
        pinCenters: [CGFloat],
        wellPinIndices: Set<Int>,
        configuration: Configuration,
        ignoredPinIndex: Int? = nil
    ) -> Snap? {
        guard configuration.strength > 0, configuration.snapRadius > 0, !wellPinIndices.isEmpty else { return nil }
        var nearest: (index: Int, distance: CGFloat)?
        for well in wellPinIndices {
            guard well < pinCenters.count, well != ignoredPinIndex else { continue }
            let distance = abs(along - pinCenters[well])
            if distance <= configuration.snapRadius, nearest.map({ distance < $0.distance }) ?? true {
                nearest = (well, distance)
            }
        }
        guard let well = nearest?.index else { return nil }
        let pinIndex = along < pinCenters[well] ? well : well + 1
        return Snap(pinIndex: pinIndex, wellPinIndex: well)
    }

    private static func nearestWell(to position: CGFloat, centers: [CGFloat], wells: Set<Int>) -> Int? {
        wells.filter { $0 < centers.count }.min { lhs, rhs in
            abs(centers[lhs] - position) < abs(centers[rhs] - position)
        }
    }

    /// Preserves item order and keeps wells unmoved after the soft pull.
    private static func enforceOrder(
        proposed: inout [CGFloat],
        wells: Set<Int>,
        configuration: Configuration
    ) {
        let gap = configuration.minimumSeparation
        guard proposed.count > 1 else { return }
        for index in 1..<proposed.count {
            if wells.contains(index) { continue }
            proposed[index] = max(proposed[index], proposed[index - 1] + gap)
        }
        for index in stride(from: proposed.count - 2, through: 0, by: -1) {
            if wells.contains(index) { continue }
            proposed[index] = min(proposed[index], proposed[index + 1] - gap)
        }
        for well in wells where well < proposed.count {
            if well > 0 { proposed[well - 1] = min(proposed[well - 1], proposed[well] - gap) }
            if well + 1 < proposed.count {
                proposed[well + 1] = max(proposed[well + 1], proposed[well] + gap)
            }
        }
    }
}
