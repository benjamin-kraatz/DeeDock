import Foundation

/// Adds children only to apps already admitted by the display and section policies.
enum DockWindowProjection {
    static func entries(_ base: [DockRenderSlot], windows: [DockWindowSnapshot],
                        enabled: Bool, keepExpanded: Bool, expandedApps: Set<String>) -> [DockRenderSlot] {
        guard enabled else { return base }
        let byApp = Dictionary(grouping: windows, by: \.applicationID)
        return base.flatMap { entry -> [DockRenderSlot] in
            guard let app = entry.item, let windows = byApp[app.id], !windows.isEmpty else { return [entry] }
            let expanded = keepExpanded || expandedApps.contains(app.id)
            let group = DockWindowGroup(app: app, count: windows.count, expanded: expanded)
            return [entry, .windowGroup(group)] + (expanded ? windows.map { .window(DockWindowItem(window: $0, app: app)) } : [])
        }
    }
}
