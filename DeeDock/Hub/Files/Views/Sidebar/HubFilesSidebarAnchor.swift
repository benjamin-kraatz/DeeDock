import AppKit
import SwiftUI

/// Which sidebar frame an anchor reports.
enum HubFilesSidebarAnchorRole: Equatable {
    /// A Favorites row; its frame feeds the drop layout and aims flights.
    case row(HubFilesSidebarEntryID)
    /// The Favorites section from its header down: the top of the drop area.
    case favorites
    /// The whole sidebar column: dragging a row past it removes the row.
    case sidebar
    /// The open insertion slot: where a dropped drag image settles.
    case slot
    /// The end slot.
    case endSlot
}

/// An invisible view whose screen frame the sidebar model reads when a drag starts.
///
/// Hit testing and drop routing use AppKit screen coordinates (`NSDraggingInfo` and event
/// locations), so frames come from real views rather than SwiftUI geometry readers: that keeps
/// both sides in one coordinate space, including while the sidebar is scrolled. Place it as a
/// `.background` so it never takes a click.
struct HubFilesSidebarAnchor: NSViewRepresentable {
    let role: HubFilesSidebarAnchorRole
    let sidebar: HubFilesSidebarModel

    func makeNSView(context: Context) -> HubFilesSidebarAnchorView { HubFilesSidebarAnchorView() }

    func updateNSView(_ view: HubFilesSidebarAnchorView, context: Context) {
        guard view.role != role || view.sidebar !== sidebar else { return }
        view.unregister()
        view.role = role
        view.sidebar = sidebar
        view.register()
    }

    static func dismantleNSView(_ view: HubFilesSidebarAnchorView, coordinator: ()) { view.unregister() }
}

final class HubFilesSidebarAnchorView: NSView {
    var role: HubFilesSidebarAnchorRole?
    weak var sidebar: HubFilesSidebarModel?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    func register() {
        guard let sidebar, let role else { return }
        switch role {
        case .row(let id): sidebar.rowViews[id] = HubFilesWeakView(view: self)
        case .favorites: sidebar.favoritesView = self
        case .sidebar: sidebar.sidebarView = self
        case .slot: sidebar.slotView = self
        case .endSlot: sidebar.endSlotView = self
        }
    }

    /// Clears the registration only if it still points here: a row that moved may already have
    /// a newer view registered under the same identity.
    func unregister() {
        guard let sidebar, let role else { return }
        switch role {
        case .row(let id): if sidebar.rowViews[id]?.view === self { sidebar.rowViews[id] = nil }
        case .favorites: if sidebar.favoritesView === self { sidebar.favoritesView = nil }
        case .sidebar: if sidebar.sidebarView === self { sidebar.sidebarView = nil }
        case .slot: if sidebar.slotView === self { sidebar.slotView = nil }
        case .endSlot: if sidebar.endSlotView === self { sidebar.endSlotView = nil }
        }
    }
}
