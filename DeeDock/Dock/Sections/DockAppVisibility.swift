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
    case app(String), folder(UUID), group(DockAppGroup), trash
    var hitID: String {
        switch self {
        case .app(let id): "app:\(id)"
        case .folder(let id): "folder:\(id.uuidString)"
        case .group(let group): "group:\(group.rawValue)"
        case .trash: "trash"
        }
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
    static func entries(items: [DockItem], folders: [FolderDockItem] = [], pins: [DockPin]? = nil,
                        visibility: DockAppVisibility, expanded: Bool, trash: TrashDockItem? = nil) -> [DockRenderSlot] {
        let pinned: [DockRenderSlot]
        if let pins {
            let applications = Dictionary(uniqueKeysWithValues: items.filter(\.isFavorite).map { ($0.reference.id, $0) })
            let folderItems = Dictionary(uniqueKeysWithValues: folders.map { ($0.reference.id, $0) })
            pinned = pins.compactMap { pin in
                switch pin {
                case .application(let reference): applications[reference.id].map(DockRenderSlot.app)
                case .folder(let reference): folderItems[reference.id].map(DockRenderSlot.folder)
                }
            }
        } else {
            pinned = items.filter(\.isFavorite).map(DockRenderSlot.app)
        }
        let running = items.filter { !$0.isFavorite }.map(DockRenderSlot.app)
        let applications = [DockAppGroup.pinned, .running].flatMap { group -> [DockRenderSlot] in
            let entries = group == .pinned ? pinned : running
            if visibility.hiddenGroup == group { return [] }
            if visibility.collapsedGroup == group {
                return [.group(DockGroupControl(group: group, count: entries.count, expanded: expanded))]
                    + (expanded ? entries : [])
            }
            return entries
        }
        return applications + (trash.map { [.trash($0)] } ?? [])
    }

    /// Retains identity, then the disappearing app's group control, then the nearest surviving entry.
    static func repairedSelection(_ selection: DockEntryID?, previous: [DockRenderSlot], current: [DockRenderSlot]) -> DockEntryID? {
        guard let selection else { return nil }
        if current.contains(where: { $0.target == selection }) { return selection }
        let oldIndex = previous.firstIndex { $0.target == selection } ?? 0
        if let old = previous.first(where: { $0.target == selection }), let appGroup = old.appGroup {
            let group = DockEntryID.group(appGroup)
            if current.contains(where: { $0.target == group }) { return group }
        }
        return current.isEmpty ? nil : current[min(oldIndex, current.count - 1)].target
    }
}
