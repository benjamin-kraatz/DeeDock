import Foundation

/// One island as rendered: which island it is and which consecutive slots it covers.
///
/// The DOKK tile placed among pins splits one island into two spans; both carry the island's
/// identity, so `id` adds the span's first slot to stay unique for SwiftUI.
struct DockIslandSpan: Equatable, Identifiable {
    let island: DockIsland
    let range: Range<Int>
    /// Position among the custom islands, so split islands cycle through the palette.
    let customIndex: Int
    var id: String { "\(island.id.uuidString):\(range.lowerBound)" }
}

/// Groups a projected dock into islands.
///
/// Pure over render slots and a plan, so the panel, previews, and tests agree on where each
/// island starts. The tile, running apps, and utilities each form one island where they appear;
/// pinned slots follow the plan's counts. A slot kind that reappears after another kind (the DOKK
/// tile placed among pins, for example) opens a new span of the same island.
enum DockIslandAssignment {
    private enum Key: Equatable {
        case tile, pinned(Int), running, utilities
    }

    /// Islands for `slots`, in slot order. Empty for an empty dock.
    ///
    /// Membership comes from each pin's place in `pinOrder`, the display's saved pin list, so a pin
    /// parked off the dock or lifted into a drag keeps the others in their islands. A pin missing
    /// from `pinOrder` counts sequentially after it. Gaps and section controls join the open island.
    static func spans(slots: [DockRenderSlot], plan: DockIslandPlan, pinOrder: [String]) -> [DockIslandSpan] {
        let positions = Dictionary(pinOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let pinCount = max(pinOrder.count, slots.filter { $0.pin != nil }.count)
        let plan = plan.reconciled(pinCount: pinCount)
        let starts = plan.pinnedIslandStarts(pinCount: pinCount)
        func group(forPin index: Int) -> Int { starts.lastIndex { $0 <= index } ?? 0 }
        var unlisted = pinOrder.count
        var current: (key: Key, start: Int)?
        var result: [(Key, Range<Int>)] = []
        func close(at end: Int) {
            if let current { result.append((current.key, current.start..<end)) }
        }
        for (index, slot) in slots.enumerated() {
            let key: Key
            if slot.isLauncher {
                key = .tile
            } else if slot.isPinned {
                if let pin = slot.pin {
                    let position = positions[pin.id] ?? { defer { unlisted += 1 }; return unlisted }()
                    key = .pinned(group(forPin: position))
                } else if case .pinned(let group) = current?.key {
                    key = .pinned(group)
                } else {
                    key = .pinned(0)
                }
            } else if slot.appGroup == .running {
                key = .running
            } else {
                key = .utilities
            }
            if key != current?.key {
                close(at: index)
                current = (key, index)
            }
        }
        close(at: slots.count)
        return result.map { key, range in
            switch key {
            case .tile: return DockIslandSpan(island: plan.island(for: .tile), range: range, customIndex: 0)
            case .running: return DockIslandSpan(island: plan.island(for: .running), range: range, customIndex: 0)
            case .utilities: return DockIslandSpan(island: plan.island(for: .utilities), range: range, customIndex: 0)
            case .pinned(let group):
                let island = plan.pinnedIslands.indices.contains(group) ? plan.pinnedIslands[group] : DockIsland.automatic(.pinned)
                // Counted in the plan, not per span, so an island split by the tile keeps one colour
                // and hiding an earlier island never recolours the later ones.
                let position = island.kind == .custom ? plan.pinnedIslands.prefix(group).filter { $0.kind == .custom }.count : 0
                return DockIslandSpan(island: island, range: range, customIndex: position)
            }
        }
    }

    /// Geometry bands for `spans`.
    static func layout(spans: [DockIslandSpan], settings: DockIslandSettings) -> DockGeometry.IslandLayout {
        DockGeometry.IslandLayout(starts: spans.map(\.range.lowerBound), gap: settings.gap, padding: settings.padding)
    }
}
