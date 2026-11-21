import Foundation

/// One drawn row: an item, how it matched a search, and its place in a version group.
struct FlixListRow: Identifiable, Equatable {
    let item: FlixItem
    /// Set while searching; `.meaning` draws the "✦ by meaning" chip.
    var match: FlixMatchKind?
    /// An older version drawn indented under its newest version.
    var isChild = false
    /// Versions in this row's group, counting itself; 0 when it has none or is a child.
    var versionCount = 0
    var versionGroup: String?
    var isNoise = false

    var id: String { (isChild ? "c:" : "r:") + item.id.uuidString }
}

/// One time section of the list.
struct FlixListSection: Identifiable, Equatable {
    let group: FlixTimeGroup
    var rows: [FlixListRow]
    var id: FlixTimeGroup { group }
}

/// The list as drawn, plus what the header and footer count.
struct FlixListResult: Equatable {
    var sections: [FlixListSection] = []
    /// Top-level rows, for the header's "12 items".
    var count = 0
    /// Noise items in the whole history, for the footer.
    var noiseCount = 0
    /// Every row's item in drawing order, children included, for arrow keys and Shift-click.
    var order: [FlixItem.ID] = []
}

/// What the list depends on, as values, so building it is a pure function.
struct FlixListInput {
    var items: [FlixItem]
    var filter: FlixFilter = .all
    /// Plain search text. Ignored while `query` is understood.
    var searchText = ""
    var searchActive = false
    var query: FlixQueryState = .idle
    var moreLikeThis: FlixMoreLikeThis?
    var hidesNoise = true
    var showNoise = false
    var annotations: [FlixItem.ID: FlixItemAnnotation] = [:]
    var expandedVersions: Set<String> = []
    var smartFilters: [FlixSmartFilter] = []
    var favorites: [FlixFavorite] = []
    var threads: [FlixThread] = []
    var now = Date.now
    var calendar = Calendar.current
    var semantic: (String, FlixItem) -> Bool? = { _, _ in nil }
}

/// Builds the visible list: noise, then More like this, search, or the sidebar filter, then version
/// collapsing, then time sections.
enum FlixListBuilder {
    static func build(_ input: FlixListInput) -> FlixListResult {
        var result = FlixListResult()
        let isNoise: (FlixItem) -> Bool = { item in
            input.annotations[item.id]?.isNoise ?? FlixNoiseRules.isNoise(path: item.path)
        }
        result.noiseCount = input.hidesNoise ? input.items.lazy.filter(isNoise).count : 0
        let hidden = input.hidesNoise && !input.showNoise
        let base = hidden ? input.items.filter { !isNoise($0) } : input.items

        let matched: [(FlixItem, FlixMatchKind?)]
        if let like = input.moreLikeThis {
            let ids = Set(like.resultIDs ?? [])
            matched = base.filter { ids.contains($0.id) && $0.id != like.sourceID }.map { ($0, .meaning) }
        } else if input.searchActive, case .understood(let tokens, let matches) = input.query {
            if let matches {
                matched = base.compactMap { item in matches[item.id].map { (item, $0) } }
            } else {
                matched = base.filter { item in
                    tokens.allSatisfy { $0.rule.matches(item, now: input.now, semantic: input.semantic) }
                }.map { ($0, FlixMatchKind.name) }
            }
        } else if input.searchActive, !input.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let text = input.searchText.trimmingCharacters(in: .whitespaces)
            matched = base.filter { $0.name.localizedStandardContains(text) }.map { ($0, .name) }
        } else {
            let members = threadMembers(input)
            matched = base.filter {
                input.filter.matches($0, smartFilters: input.smartFilters, favorites: input.favorites,
                                     threadMembers: members, now: input.now, semantic: input.semantic)
            }.map { ($0, nil) }
        }

        // Versions: only the newest of a group shows, with its older ones as children when expanded.
        let groupOf: (FlixItem) -> (String, Int)? = { item in
            guard let annotation = input.annotations[item.id], let group = annotation.versionGroup else { return nil }
            return (group, annotation.versionRank ?? 0)
        }
        var newestInGroup: [String: (FlixItem.ID, Int)] = [:]
        var groupCounts: [String: Int] = [:]
        for item in input.items {
            guard let (group, rank) = groupOf(item) else { continue }
            groupCounts[group, default: 0] += 1
            if rank >= newestInGroup[group]?.1 ?? .min { newestInGroup[group] = (item.id, rank) }
        }
        let visibleNewest = Set(matched.compactMap { item, _ -> String? in
            guard let (group, _) = groupOf(item), newestInGroup[group]?.0 == item.id else { return nil }
            return group
        })

        var sections: [FlixListSection] = []
        for (item, match) in matched {
            let version = groupOf(item)
            if let (group, _) = version, newestInGroup[group]?.0 != item.id, visibleNewest.contains(group) {
                continue // drawn as a child of the newest version instead
            }
            let isParent = version.map { newestInGroup[$0.0]?.0 == item.id } ?? false
            let count = isParent ? version.flatMap { groupCounts[$0.0] } ?? 0 : 0
            let row = FlixListRow(item: item, match: match, versionCount: count > 1 ? count : 0,
                                  versionGroup: version?.0, isNoise: isNoise(item))
            let group = FlixTimeGroup.group(for: item.date, now: input.now, calendar: input.calendar)
            if sections.last?.group != group {
                if let index = sections.firstIndex(where: { $0.group == group }) {
                    sections[index].rows.append(row)
                } else {
                    sections.append(FlixListSection(group: group, rows: [row]))
                }
            } else {
                sections[sections.count - 1].rows.append(row)
            }
            result.count += 1
            if isParent, count > 1, let group = version?.0, input.expandedVersions.contains(group) {
                let children = input.items
                    .filter { groupOf($0)?.0 == group && $0.id != item.id }
                    .sorted { (groupOf($0)?.1 ?? 0) > (groupOf($1)?.1 ?? 0) }
                    .map { FlixListRow(item: $0, isChild: true, versionGroup: group, isNoise: isNoise($0)) }
                sections[sections.count - 1].rows.append(contentsOf: children)
            }
        }
        sections.sort { $0.group < $1.group }
        result.sections = sections
        result.order = sections.flatMap { $0.rows.map(\.item.id) }
        return result
    }

    private static func threadMembers(_ input: FlixListInput) -> Set<FlixItem.ID>? {
        guard case .thread(let id) = input.filter else { return nil }
        return Set(input.threads.first { $0.id == id }?.memberIDs ?? [])
    }
}
