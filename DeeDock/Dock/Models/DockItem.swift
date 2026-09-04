import AppKit

/// A rendered application snapshot whose icon is already cached by the workspace service.
struct DockItem: Identifiable {
    let reference: ApplicationReference
    let icon: NSImage
    /// Whether this item belongs to the persisted pinned section.
    let isFavorite: Bool
    /// True when at least one regular application process matches this identity.
    let isRunning: Bool
    /// Whether the application bundle can currently be resolved for opening.
    let isAvailable: Bool
    var id: String { reference.id }
}

/// A rendered folder pin whose icon and availability were resolved for this panel refresh.
struct FolderDockItem: Identifiable {
    let reference: FolderReference
    let icon: NSImage
    let isAvailable: Bool
    var id: String { "folder:\(reference.id.uuidString)" }
}

/// A snapshot of the system Trash used by every display dock.
struct TrashDockItem: Identifiable {
    enum State: Equatable {
        case empty, full, unknown, unavailable
    }

    let state: State
    let icon: NSImage
    var id: String { "system-trash" }
}

/// A snapshot of the shared Shelf used by every display dock.
struct ShelfDockItem: Identifiable {
    /// Drives the badge. Zero renders the empty tray without a badge.
    let count: Int
    let icon: NSImage
    var id: String { "shelf" }
    var isEmpty: Bool { count == 0 }
}

/// A snapshot of the shared Session Capsules collection used by every display dock.
struct CapsuleDockItem: Identifiable {
    let count: Int
    let icon: NSImage
    var id: String { "session-capsules" }
}

/// One saved checkpoint projected as a temporary, title-bearing Dock item.
struct SessionCapsuleDockItem: Identifiable {
    let capsuleID: UUID
    let title: String
    let icon: NSImage
    /// Distinct applications the capsule holds, capped at what the tile badge can show legibly.
    var applicationIcons: [NSImage] = []
    var id: String { "session-capsule:\(capsuleID.uuidString)" }
}
