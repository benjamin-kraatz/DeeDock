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
