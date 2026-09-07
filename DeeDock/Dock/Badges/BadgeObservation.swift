import Foundation

/// Missing/unsupported AX data is unknown. Only an explicitly empty status is cleared.
nonisolated enum BadgeObservation: Codable, Equatable, Sendable {
    case unknown
    case cleared
    case count(Int64)
    case text(String)

    init(label: String) {
        let value = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { self = .cleared }
        else if value.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int64(value) {
            self = .count(number)
        } else { self = .text(String(value.prefix(128))) }
    }

    var numericValue: Int64? {
        switch self {
        case .cleared: 0
        case .count(let value): value
        default: nil
        }
    }
    var label: String? {
        switch self {
        case .count(let value): String(value)
        case .text(let value): value
        default: nil
        }
    }
    /// Both operands are nonnegative Int64 counts, so subtraction cannot overflow.
    func delta(from baseline: Self) -> Int64? {
        guard let current = numericValue, let previous = baseline.numericValue else { return nil }
        return current - previous
    }
}

nonisolated struct BadgeCheck: Codable, Equatable {
    var value: BadgeObservation
    var date: Date
}

nonisolated struct BadgeChange: Codable, Equatable, Identifiable {
    var id = UUID()
    var value: BadgeObservation
    var date: Date
}

nonisolated struct BadgeAppMemory: Codable, Equatable {
    var checked: BadgeCheck?
    var changes: [BadgeChange] = []
    var touched: Date
}

/// Endpoints express net observed change. They are never a count of incoming messages.
nonisolated struct BadgeDigestRow: Codable, Equatable {
    var first: BadgeObservation
    var last: BadgeObservation
    var changes = 0
    var hasGap = false
}

nonisolated struct BadgeFocusDigest: Codable, Equatable, Identifiable {
    var id: UUID
    var modeName: String
    var started: Date
    var ended: Date?
    /// Retained separately because FocusSession clears its deadline when completing at startup.
    var deadline: Date?
    /// Deleted app rows stay excluded for this session, including across a relaunch.
    var excludedPaths: Set<String> = []
    var incomplete = false
    var rows: [String: BadgeDigestRow] = [:]
}

nonisolated struct BadgeMemoryDocument: Codable, Equatable {
    var version = 1
    var collectFocus = false
    var lastSessionID: UUID?
    var apps: [String: BadgeAppMemory] = [:]
    var active: BadgeFocusDigest?
    var digests: [BadgeFocusDigest] = []
}
