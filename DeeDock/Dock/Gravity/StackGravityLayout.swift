import CoreGraphics
import Foundation

/// Maps dock slots and pin lists onto ``StackGravityPhysics`` without changing resting geometry.
enum StackGravityLayout {
    /// Folder-stack slots that attract neighbors. Downloads is a utility, not a well.
    static func wellIndices(in slots: [DockRenderSlot]) -> Set<Int> {
        Set(slots.enumerated().compactMap { index, slot in
            guard let folder = slot.folder, !folder.isDownloads else { return nil }
            return index
        })
    }

    /// Magnified centers with a soft pull toward nearby stacks.
    static func pulledCenters(
        layout: DockGeometry.Layout,
        sizes: [CGFloat],
        slots: [DockRenderSlot],
        strength: CGFloat,
        reduceMotion: Bool
    ) -> [CGFloat] {
        let base = layout.centers(sizes: sizes)
        guard strength > 0, !reduceMotion else { return base }
        let wells = wellIndices(in: slots)
        guard !wells.isEmpty else { return base }
        return StackGravityPhysics.pulledCenters(
            centers: base,
            wellIndices: wells,
            configuration: configuration(layout: layout, strength: strength)
        )
    }

    /// Insertion beside a stack when the pointer is inside that well.
    static func snappedInsertion(
        proposed: Int,
        along: CGFloat,
        pins: [DockPin],
        layout: DockGeometry.Layout,
        strength: CGFloat,
        movingPinID: String? = nil
    ) -> (index: Int, snap: StackGravityPhysics.Snap)? {
        guard strength > 0 else { return nil }
        let pinCenters = layout.restingCenters.prefix(pins.count).map { $0 }
        guard pinCenters.count == pins.count else { return nil }
        let ignored = movingPinID.flatMap { id in pins.firstIndex { $0.id == id } }
        guard let snap = StackGravityPhysics.snap(
            along: along,
            pinCenters: Array(pinCenters),
            wellPinIndices: StackGravityPhysics.wellPinIndices(in: pins),
            configuration: configuration(layout: layout, strength: strength),
            ignoredPinIndex: ignored
        ) else { return nil }
        return (snap.pinIndex, snap)
    }

    static func configuration(layout: DockGeometry.Layout, strength: CGFloat) -> StackGravityPhysics.Configuration {
        StackGravityPhysics.Configuration(
            strength: strength,
            iconSize: layout.iconSize,
            itemSpacing: layout.itemSpacing
        )
    }
}
