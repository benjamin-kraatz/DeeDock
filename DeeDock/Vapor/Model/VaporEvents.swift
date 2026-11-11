import CoreGraphics
import Foundation

/// The capsule above the orb after a delete.
nonisolated struct VaporStatus: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// "Deleted 3 folders" with a countdown ring and Undo. `failed` folders couldn't be staged
        /// and stayed in the orb.
        case deleted(count: Int, failed: Int, deadline: Date)
        /// "✓ Freed 1.8 GB", shown briefly after the undo window. `failed` carries over.
        case freed(bytes: Int64, count: Int, failed: Int)
        /// Nothing could be staged: "Couldn't delete 3 folders".
        case failed(count: Int)
        /// Undo couldn't put some folders back because something now sits at their path.
        case notRestored(count: Int)
    }

    var kind: Kind
    /// Changes with every new capsule, so a view can restart its transition.
    var token = UUID()
}

/// A one-shot event the orb animates. Views react to a change of `token`.
nonisolated struct VaporEvent<Payload: Equatable & Sendable>: Equatable, Sendable {
    let payload: Payload
    let token: UUID

    init(_ payload: Payload) {
        self.payload = payload
        token = UUID()
    }
}

/// Where folders came from, for analytics and for the pop-in animation.
nonisolated enum VaporAddSource: String, Sendable {
    case drop, suggestion
    case addAll = "add_all"
    /// Restored by Undo or at launch. Not reported to analytics.
    case restore
}

/// Payload for "folders were added": their ids and source. Drives the pop-in and squash.
nonisolated struct VaporAddition: Equatable, Sendable {
    let folderIDs: [UUID]
    let source: VaporAddSource
}

/// Payload for "delete started": the folders being pulled into the orb and evaporated.
nonisolated struct VaporDeletion: Equatable, Sendable {
    /// The folders as they were when the hold completed. The panel keeps showing these rows
    /// while they fly into the orb, even after staging has removed them from the controller.
    let folders: [VaporFolder]
    /// The panel was open, so rows are pulled into the orb first and the orb evaporates after them.
    let fromPanel: Bool

    var folderIDs: [UUID] { folders.map(\.id) }
}

/// The orb's motion while it's being dragged, for the slosh. Points per second (and per
/// second squared) in SwiftUI's y-down axes, so views can use it directly.
nonisolated struct VaporOrbMotion: Equatable, Sendable {
    var isDragging = false
    var velocity: CGVector = .zero
    var acceleration: CGVector = .zero

    static let still = VaporOrbMotion()
}

/// The state of an in-flight drag of files over Vapor's windows.
nonisolated struct VaporDropHover: Equatable, Sendable {
    /// Proximity to the orb, for the lean and glow. `.none` when no file drag is near.
    var proximity: VaporDropProximity = .none
    /// The drag is over the open panel, which highlights its drop zone.
    var isOverPanel = false

    static let none = VaporDropHover()
}

/// The content of the capsule above the orb.
nonisolated enum VaporCallout: Equatable, Sendable {
    case refusal(VaporRefusal)
    case status(VaporStatus)
    case dropToAdd
    /// "Drop folders here", "3 folders · 1.8 GB" or "3 folders · calculating…".
    case tooltip(VaporTotals)
}
