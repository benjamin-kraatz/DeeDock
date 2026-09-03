import AppKit

/// A temporary insertion proposal; it never changes the store or writes preferences.
struct DockDragProposal: Equatable {
    let references: [ApplicationReference]
    let index: Int
}

/// A stable render identity for either an application or one place in a multi-app insertion gap.
enum DockRenderSlot: Identifiable {
    case app(DockItem)
    case group(DockGroupControl)
    case gap(String)

    var id: String {
        switch self {
        case .app(let item): return "app:\(item.id)"
        case .gap(let id): return "gap:\(id)"
        case .group(let control): return DockEntryID.group(control.group).hitID
        }
    }
    var isPinned: Bool {
        switch self { case .app(let item): return item.isFavorite; case .gap: return true; case .group(let control): return control.group == .pinned }
    }
    var item: DockItem? { if case .app(let item) = self { return item }; return nil }

    var target: DockEntryID? {
        switch self { case .app(let item): .app(item.id); case .group(let control): .group(control.group); case .gap: nil }
    }

    static func slots(items: [DockItem], proposal: DockDragProposal?) -> [DockRenderSlot] {
        slots(entries: items.map(Self.app), proposal: proposal)
    }

    /// Gap indices refer to persisted pins, excluding section controls and incoming duplicates.
    static func slots(entries: [Self], proposal: DockDragProposal?) -> [Self] {
        guard let proposal else { return entries }
        let ids = Set(proposal.references.map(\.id))
        let pins = entries.compactMap(\.item).filter(\.isFavorite)
        // Collapsed and hidden pins must never leak into a gap preview.
        if entries.contains(where: { if case .group(let c) = $0 { return c.group == .pinned && !c.expanded }; return false }) { return entries }
        let boundary = pins.prefix(max(0, proposal.index)).filter { !ids.contains($0.id) }.count
        var result = entries.filter { $0.item.map { !ids.contains($0.id) } ?? true }
        let controlCount = result.prefix { if case .group(let c) = $0 { return c.group == .pinned }; return false }.count
        result.insert(contentsOf: proposal.references.map { .gap($0.id) }, at: min(controlCount + boundary, result.count))
        return result
    }
}

/// A connected destination for the accessible copy-pin command. Display names are supplied by macOS.
struct DockPinDestination: Identifiable {
    let id: String
    let name: String
}
