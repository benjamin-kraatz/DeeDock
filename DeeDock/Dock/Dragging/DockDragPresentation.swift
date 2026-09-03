import AppKit

/// A temporary insertion proposal; it never changes the store or writes preferences.
struct DockDragProposal: Equatable {
    let references: [ApplicationReference]
    let index: Int
}

/// A stable render identity for either an application or one place in a multi-app insertion gap.
enum DockRenderSlot: Identifiable {
    case app(DockItem)
    case gap(String)

    var id: String {
        switch self {
        case .app(let item): return "app:\(item.id)"
        case .gap(let id): return "gap:\(id)"
        }
    }
    var isPinned: Bool {
        switch self { case .app(let item): return item.isFavorite; case .gap: return true }
    }
    var item: DockItem? { if case .app(let item) = self { return item }; return nil }

    static func slots(items: [DockItem], proposal: DockDragProposal?) -> [DockRenderSlot] {
        guard let proposal else { return items.map(Self.app) }
        let ids = Set(proposal.references.map(\.id))
        let pinned = items.filter(\.isFavorite)
        let index = pinned.prefix(max(0, proposal.index)).filter { !ids.contains($0.id) }.count
        var result = items.filter { !ids.contains($0.id) }.map(Self.app)
        result.insert(contentsOf: proposal.references.map { .gap($0.id) }, at: min(index, result.count))
        return result
    }
}

/// A connected destination for the accessible copy-pin command. Display names are supplied by macOS.
struct DockPinDestination: Identifiable {
    let id: String
    let name: String
}
