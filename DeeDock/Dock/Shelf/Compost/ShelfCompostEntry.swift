import Foundation

/// A retained Shelf reference. Archiving never changes the referenced file or its bookmark.
nonisolated struct ShelfCompostEntry: Codable, Equatable, Identifiable, Sendable {
    /// A full archive pauses aging. Entries are never evicted to make room.
    static let capacity = 500
    let item: ShelfItem
    let archivedAt: Date
    var id: UUID { item.id }
}

/// Automatic archiving is opt-in. A day is 24 elapsed hours, including app downtime.
nonisolated enum ShelfCompostPolicy: Int, Codable, CaseIterable, Sendable {
    case off = 0
    case week = 7
    case fortnight = 14
    case month = 30

    var interval: TimeInterval? { self == .off ? nil : Double(rawValue) * 86_400 }

    var title: LocalizedStringResource {
        switch self {
        case .off: .compostRuleOff
        case .week: .compostRuleWeek
        case .fortnight: .compostRuleFortnight
        case .month: .compostRuleMonth
        }
    }
}

extension ShelfDocument {
    /// Archives the oldest eligible references first, retaining everything when Compost is full.
    /// The caller saves the whole document before publishing either side of the move.
    mutating func compostAgedItems(at now: Date) {
        guard let interval = compostPolicy.interval else { return }
        let eligible = items.filter { $0.addedAt.addingTimeInterval(interval) <= now }
            .sorted { $0.addedAt < $1.addedAt }
            .prefix(max(0, ShelfCompostEntry.capacity - compost.count))
        guard !eligible.isEmpty else { return }
        let ids = Set(eligible.map(\.id))
        compost.insert(contentsOf: eligible.map { ShelfCompostEntry(item: $0, archivedAt: now) }, at: 0)
        items.removeAll { ids.contains($0.id) }
    }

    /// One deadline for the next item, with no polling while disabled, empty, or full.
    var nextCompostDate: Date? {
        guard let interval = compostPolicy.interval,
              compost.count < ShelfCompostEntry.capacity else { return nil }
        return items.map { $0.addedAt.addingTimeInterval(interval) }.min()
    }
}

/// Recoverable restore failures. The archived reference remains saved in both cases.
nonisolated enum ShelfCompostError: LocalizedError {
    case shelfFull
    case alreadyStaged

    var errorDescription: String? {
        switch self {
        case .shelfFull: String(localized: .compostShelfFull)
        case .alreadyStaged: String(localized: .compostAlreadyStaged)
        }
    }
}
