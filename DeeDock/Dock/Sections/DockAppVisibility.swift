import Foundation

/// A single choice prevents shared defaults and display overrides from hiding both groups.
enum DockAppVisibility: String, Codable, CaseIterable {
    case showAll, hideRunning, collapseRunning, hidePinned, collapsePinned

    var collapsedGroup: DockAppGroup? {
        switch self { case .collapsePinned: .pinned; case .collapseRunning: .running; default: nil }
    }
    var hiddenGroup: DockAppGroup? {
        switch self { case .hidePinned: .pinned; case .hideRunning: .running; default: nil }
    }
    var title: LocalizedStringResource {
        switch self {
        case .showAll: .visibilityShowAll
        case .hideRunning: .visibilityHideRunning
        case .collapseRunning: .visibilityCollapseRunning
        case .hidePinned: .visibilityHidePinned
        case .collapsePinned: .visibilityCollapsePinned
        }
    }
}

/// Pinned applications retain their group while running.
enum DockAppGroup: String, Hashable { case pinned, running }

/// Navigation identity cannot confuse a section control with a real application.
enum DockEntryID: Hashable {
    case app(String), group(DockAppGroup)
    var hitID: String {
        switch self { case .app(let id): "app:\(id)"; case .group(let group): "group:\(group.rawValue)" }
    }
}

/// A visible section button snapshot, including its localized action and current count.
struct DockGroupControl {
    let group: DockAppGroup
    let count: Int
    let expanded: Bool
    var title: LocalizedStringResource {
        switch (group, expanded) {
        case (.pinned, false): .sectionShowPinned(count: count)
        case (.pinned, true): .sectionHidePinned(count: count)
        case (.running, false): .sectionShowRunning(count: count)
        case (.running, true): .sectionHideRunning(count: count)
        }
    }
    var symbol: String { group == .pinned ? "pin.fill" : "square.stack.3d.up.fill" }
}

/// Projects catalog snapshots without changing pins, running order, or resource ownership.
enum DockSectionProjection {
    static func entries(items: [DockItem], visibility: DockAppVisibility, expanded: Bool) -> [DockRenderSlot] {
        [DockAppGroup.pinned, .running].flatMap { group -> [DockRenderSlot] in
            let apps = items.filter { $0.isFavorite == (group == .pinned) }
            if visibility.hiddenGroup == group { return [] }
            if visibility.collapsedGroup == group {
                return [.group(DockGroupControl(group: group, count: apps.count, expanded: expanded))]
                    + (expanded ? apps.map(DockRenderSlot.app) : [])
            }
            return apps.map(DockRenderSlot.app)
        }
    }

    /// Retains identity, then the disappearing app's group control, then the nearest surviving entry.
    static func repairedSelection(_ selection: DockEntryID?, previous: [DockRenderSlot], current: [DockRenderSlot]) -> DockEntryID? {
        guard let selection else { return nil }
        if current.contains(where: { $0.target == selection }) { return selection }
        let oldIndex = previous.firstIndex { $0.target == selection } ?? 0
        if let old = previous.first(where: { $0.target == selection }) {
            let group = DockEntryID.group(old.isPinned ? .pinned : .running)
            if current.contains(where: { $0.target == group }) { return group }
        }
        return current.isEmpty ? nil : current[min(oldIndex, current.count - 1)].target
    }
}
