import Foundation

/// One island as rendered: which island it is and which consecutive slots it covers.
struct DockIslandSpan: Equatable, Identifiable {
    let island: DockIsland
    let range: Range<Int>
    /// Position among the custom islands, so split islands cycle through the palette.
    let customIndex: Int
    var id: UUID { island.id }
}

/// Groups a projected dock into islands.
///
/// Pure over render slots and a plan, so the panel, previews, and tests agree on where each
/// island starts. The tile, running apps, and utilities each form one island where they appear;
/// pinned slots follow the plan's counts. A slot kind that reappears after another kind (the DOKK
/// tile placed among pins, for example) opens a new island of the same kind.
enum DockIslandAssignment {
    private enum Key: Equatable {
        case tile, pinned(Int), running, utilities
    }

    /// Islands for `slots`, in slot order. Empty for an empty dock.
    static func spans(slots: [DockRenderSlot], plan: DockIslandPlan) -> [DockIslandSpan] {
        let pinCount = slots.filter { $0.pin != nil }.count
        let plan = plan.reconciled(pinCount: pinCount)
        let starts = plan.pinnedIslandStarts(pinCount: pinCount)
        var pinIndex = 0
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
                if slot.pin != nil {
                    key = .pinned(starts.lastIndex { $0 <= pinIndex } ?? 0)
                    pinIndex += 1
                } else if case .pinned(let group) = current?.key {
                    // Gaps and the collapsed Pinned control join the open pinned island.
                    key = .pinned(group)
                } else {
                    key = .pinned(starts.lastIndex { $0 <= pinIndex } ?? 0)
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
        var customIndex = 0
        return result.map { key, range in
            switch key {
            case .tile: return DockIslandSpan(island: plan.island(for: .tile), range: range, customIndex: 0)
            case .running: return DockIslandSpan(island: plan.island(for: .running), range: range, customIndex: 0)
            case .utilities: return DockIslandSpan(island: plan.island(for: .utilities), range: range, customIndex: 0)
            case .pinned(let group):
                let island = plan.pinnedIslands.indices.contains(group) ? plan.pinnedIslands[group] : DockIsland(kind: .pinned)
                let position = island.kind == .custom ? customIndex : 0
                if island.kind == .custom { customIndex += 1 }
                return DockIslandSpan(island: island, range: range, customIndex: position)
            }
        }
    }

    /// Geometry bands for `spans`.
    static func layout(spans: [DockIslandSpan], settings: DockIslandSettings) -> DockGeometry.IslandLayout {
        DockGeometry.IslandLayout(starts: spans.map(\.range.lowerBound), gap: settings.gap, padding: settings.padding)
    }

    /// The pin index of `pinID` among `slots`, or nil when it is not a visible pin.
    static func pinIndex(of pinID: String, in slots: [DockRenderSlot]) -> Int? {
        slots.compactMap(\.pin).firstIndex { $0.id == pinID }
    }
}
