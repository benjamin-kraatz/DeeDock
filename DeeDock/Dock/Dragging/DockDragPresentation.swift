import AppKit

/// A temporary insertion proposal; it never changes the store or writes preferences.
struct DockDragProposal: Equatable {
    let pins: [DockPin]
    let index: Int
}

/// A stable render identity for either an application or one place in a multi-app insertion gap.
enum DockRenderSlot: Identifiable {
    case app(DockItem)
    case folder(FolderDockItem)
    case group(DockGroupControl)
    case trash(TrashDockItem)
    case gap(String)

    var id: String {
        switch self {
        case .app(let item): return "app:\(item.id)"
        case .folder(let item): return item.id
        case .gap(let id): return "gap:\(id)"
        case .group(let control): return DockEntryID.group(control.group).hitID
        case .trash(let item): return item.id
        }
    }
    var isPinned: Bool {
        switch self {
        case .app(let item): return item.isFavorite
        case .folder, .gap: return true
        case .group(let control): return control.group == .pinned
        case .trash: return false
        }
    }
    var item: DockItem? { if case .app(let item) = self { return item }; return nil }
    var folder: FolderDockItem? { if case .folder(let item) = self { return item }; return nil }
    var trash: TrashDockItem? { if case .trash(let item) = self { return item }; return nil }
    var isUtility: Bool { trash != nil }
    var appGroup: DockAppGroup? {
        switch self {
        case .app(let item): item.isFavorite ? .pinned : .running
        case .folder: .pinned
        case .group(let control): control.group
        case .trash, .gap: nil
        }
    }
    var pin: DockPin? {
        switch self {
        case .app(let item) where item.isFavorite: .application(item.reference)
        case .folder(let item): .folder(item.reference)
        default: nil
        }
    }
    var icon: NSImage? { item?.icon ?? folder?.icon ?? trash?.icon }
    var name: String {
        switch self {
        case .app(let item): item.reference.name
        case .folder(let item): item.reference.name
        case .group(let control): String(localized: control.title)
        case .trash: String(localized: .trashName)
        case .gap: ""
        }
    }

    var target: DockEntryID? {
        switch self {
        case .app(let item): .app(item.id)
        case .folder(let item): .folder(item.reference.id)
        case .group(let control): .group(control.group)
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
