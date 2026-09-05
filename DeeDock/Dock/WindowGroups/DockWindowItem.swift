import AppKit

/// Metadata from one ScreenCaptureKit enumeration. Bounds use global Quartz points.
nonisolated struct DockWindowSnapshot: Equatable, Identifiable, Sendable {
    let id: UInt32
    let processIdentifier: pid_t
    let applicationID: String
    let displayID: UInt32
    let title: String
    let frame: CGRect
}

/// Window presentation retains its owning application's section and artwork.
struct DockWindowItem {
    let window: DockWindowSnapshot
    let app: DockItem
    var title: String {
        window.title.isEmpty ? String(localized: .applicationMenuUntitledWindow) : window.title
    }
}

/// Explicit disclosure avoids resizing the Dock underneath a passing pointer.
struct DockWindowGroup {
    let app: DockItem
    let count: Int
    let expanded: Bool
    var title: LocalizedStringResource {
        expanded ? .windowGroupsCollapse(app.reference.name) : .windowGroupsExpand(app.reference.name)
    }
}
