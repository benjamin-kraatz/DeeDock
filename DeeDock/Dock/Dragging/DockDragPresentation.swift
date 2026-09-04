import AppKit

/// A temporary insertion proposal; it never changes the store or writes preferences.
struct DockDragProposal: Equatable {
    let pins: [DockPin]
    let index: Int
}

/// A stable render identity for either an application or one place in a multi-app insertion gap.
enum DockRenderSlot: Identifiable {
    case action(ActionDockItem)
    case app(DockItem)
    case folder(FolderDockItem)
    case group(DockGroupControl)
    case sessionCapsule(SessionCapsuleDockItem)
    case sessionCapsules(CapsuleDockItem)
    case shelf(ShelfDockItem)
    case trash(TrashDockItem)
    case gap(String)

    var id: String {
        switch self {
        case .action(let item): return DockEntryID.action(item.tile.id).hitID
        case .app(let item): return "app:\(item.id)"
        case .folder(let item): return item.id
        case .gap(let id): return "gap:\(id)"
        case .group(let control): return DockEntryID.group(control.group).hitID
        case .sessionCapsule(let item): return item.id
        case .sessionCapsules(let item): return item.id
        case .shelf(let item): return item.id
        case .trash(let item): return item.id
        }
    }
    var isPinned: Bool {
        switch self {
        case .app(let item): return item.isFavorite
        case .folder, .gap: return true
        case .group(let control): return control.group == .pinned
        case .action, .sessionCapsule, .sessionCapsules, .shelf, .trash: return false
        }
    }
    var item: DockItem? { if case .app(let item) = self { return item }; return nil }
    var folder: FolderDockItem? { if case .folder(let item) = self { return item }; return nil }
    var trash: TrashDockItem? { if case .trash(let item) = self { return item }; return nil }
    var shelf: ShelfDockItem? { if case .shelf(let item) = self { return item }; return nil }
    var capsules: CapsuleDockItem? { if case .sessionCapsules(let item) = self { return item }; return nil }
    var capsule: SessionCapsuleDockItem? { if case .sessionCapsule(let item) = self { return item }; return nil }
    /// Trailing tiles that are neither pins nor running applications, and share one divider.
    var action: ActionDockItem? { if case .action(let item) = self { return item }; return nil }
    var isUtility: Bool { action != nil || trash != nil || shelf != nil || capsules != nil || capsule != nil }
    var appGroup: DockAppGroup? {
        switch self {
        case .app(let item): item.isFavorite ? .pinned : .running
        case .folder: .pinned
        case .group(let control): control.group
        case .action, .sessionCapsule, .sessionCapsules, .shelf, .trash, .gap: nil
        }
    }
    var pin: DockPin? {
        switch self {
        case .app(let item) where item.isFavorite: .application(item.reference)
        case .folder(let item): .folder(item.reference)
        default: nil
        }
    }
    var icon: NSImage? { item?.icon ?? folder?.icon ?? capsule?.icon ?? capsules?.icon ?? shelf?.icon ?? trash?.icon }
    var name: String {
        switch self {
        case .action(let item): item.tile.name
        case .app(let item): item.reference.name
        case .folder(let item): item.reference.name
        case .group(let control): String(localized: control.title)
        case .sessionCapsule(let item): item.title
        case .sessionCapsules: String(localized: .capsulesName)
        case .shelf: String(localized: .shelfName)
        case .trash: String(localized: .trashName)
        case .gap: ""
        }
    }

    var target: DockEntryID? {
        switch self {
        case .action(let item): .action(item.tile.id)
        case .app(let item): .app(item.id)
        case .folder(let item): .folder(item.reference.id)
        case .group(let control): .group(control.group)
        case .sessionCapsule(let item): .sessionCapsule(item.capsuleID)
        case .sessionCapsules: .sessionCapsules
        case .shelf: .shelf
        case .trash: .trash
        case .gap: nil
        }
    }

    static func slots(items: [DockItem], proposal: DockDragProposal?) -> [DockRenderSlot] {
        slots(entries: items.map(Self.app), proposal: proposal)
    }

    /// Gap indices refer to persisted pins, excluding section controls and incoming duplicates.
    static func slots(entries: [Self], proposal: DockDragProposal?) -> [Self] {
        guard let proposal else { return entries }
        let ids = Set(proposal.pins.map(\.id))
        let pins = entries.compactMap(\.pin)
        // Collapsed and hidden pins must never leak into a gap preview.
        if entries.contains(where: { if case .group(let c) = $0 { return c.group == .pinned && !c.expanded }; return false }) { return entries }
        let boundary = pins.prefix(max(0, proposal.index)).filter { !ids.contains($0.id) }.count
        var result = entries.filter { slot in slot.pin.map { !ids.contains($0.id) } ?? true }
        let controlCount = result.prefix { if case .group(let c) = $0 { return c.group == .pinned }; return false }.count
        result.insert(contentsOf: proposal.pins.map { .gap($0.id) }, at: min(controlCount + boundary, result.count))
        return result
    }
}

/// A connected destination for the accessible copy-pin command. Display names are supplied by macOS.
struct DockPinDestination: Identifiable {
    let id: String
    let name: String
}
