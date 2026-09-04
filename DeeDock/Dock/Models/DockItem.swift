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
