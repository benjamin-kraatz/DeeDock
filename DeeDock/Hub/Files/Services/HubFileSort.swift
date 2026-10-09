import Foundation

/// Columns the Files tab can sort by.
nonisolated enum HubFileSortKey: String, Codable, Sendable, CaseIterable {
    case name, modified, size, kind
}

/// A sort order for Files listings, persisted per pane.
nonisolated struct HubFileSort: Codable, Hashable, Sendable {
    var key: HubFileSortKey = .name
    var ascending: Bool = true

    init(key: HubFileSortKey = .name, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }

    /// Sorts the way Finder does.
    ///
    /// Names use `localizedStandardCompare` ("File 2" before "File 10"). When sorting by name,
    /// folders stay on top in both directions. Ties on other keys fall back to name ascending so
    /// the order is stable between refreshes. Missing dates and sizes sort as the smallest values.
    func sorted(_ items: [HubFileItem]) -> [HubFileItem] {
        items.sorted(by: areInIncreasingOrder)
    }

    /// The comparison `sorted(_:)` uses. Exposed for incremental inserts.
    func areInIncreasingOrder(_ a: HubFileItem, _ b: HubFileItem) -> Bool {
        if key == .name, a.isDirectory != b.isDirectory { return a.isDirectory }
        let order: ComparisonResult
        switch key {
        case .name:
            order = a.name.localizedStandardCompare(b.name)
        case .modified:
            order = Self.compare(a.modified ?? .distantPast, b.modified ?? .distantPast)
        case .size:
            order = Self.compare(a.byteSize ?? -1, b.byteSize ?? -1)
        case .kind:
            order = a.kindDescription.localizedStandardCompare(b.kindDescription)
        }
        if order != .orderedSame { return ascending ? order == .orderedAscending : order == .orderedDescending }
        let byName = a.name.localizedStandardCompare(b.name)
        if byName != .orderedSame { return byName == .orderedAscending }
        return a.url.path < b.url.path
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}
