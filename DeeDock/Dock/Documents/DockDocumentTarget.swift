import AppKit

/// Document targeting shares the dock's visible identities and clipped content-space frames.
enum DockDocumentTarget {
    static func app(at point: CGPoint, entries: [DockRenderSlot], frames: [String: CGRect],
                    mask: CGRect, exposed: Bool) -> DockItem? {
        guard exposed, mask.contains(point) else { return nil }
        return entries.compactMap(\.item).first { item in
            item.isAvailable && frames[DockEntryID.app(item.id).hitID]?.contains(point) == true
        }
    }

    static func operation(allowed: NSDragOperation) -> NSDragOperation {
        if allowed.contains(.generic) { return .generic }
        if allowed.contains(.copy) { return .copy }
        return []
    }
}

/// Native spring callbacks can repeat; one target visit issues at most one activation.
struct DockSpringTarget {
    private(set) var target: String?
    private var activated = false

    @discardableResult mutating func update(_ target: String?) -> Bool {
        guard self.target != target else { return false }
        self.target = target
        activated = false
        return true
    }

    mutating func activate() -> Bool {
        guard target != nil, !activated else { return false }
        activated = true
        return true
    }
}

/// The trailing utility tiles an external drag can be dropped on.
enum DockUtilityDropTarget {
    case shelf, trash

    /// Trash reads differently for a reference the user is discarding than for real files.
    func message(removingFromShelf: Bool) -> LocalizedStringResource {
        switch self {
        case .shelf: .dragAddToShelf
        case .trash: removingFromShelf ? .dragRemoveFromShelf : .dragMoveToTrash
        }
    }
}
