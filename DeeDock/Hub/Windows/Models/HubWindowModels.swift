import CoreGraphics
import Foundation

/// One window card in the Hub's Windows tab.
///
/// Wraps the ``HarborWindow`` that Radar's discovery produced; its Accessibility token and
/// capture number stay meaningful only for the service session that found it.
nonisolated struct HubWindowItem: Identifiable, Equatable, Sendable {
    /// Identity that survives a rediscovery of the same window, so selection and thumbnails stay
    /// put when the tab refreshes after an app launches or quits. See ``HubWindowsGrouping/stableID(for:)``.
    let id: String
    let window: HarborWindow

    var isMinimized: Bool { window.state == .minimized }
    var isHidden: Bool { window.state == .hidden }
}

/// One app's windows in the Windows tab: an app group card.
nonisolated struct HubWindowGroup: Identifiable, Equatable, Sendable {
    /// The app's ``HarborRunningApp/id``: bundle identifier or bundle path.
    let id: String
    let name: String
    /// On-screen windows front to back, then minimized, then hidden-app windows.
    var windows: [HubWindowItem]
}

/// Pure grouping, ordering, and filtering for the Windows tab, kept apart from discovery so it is testable.
nonisolated enum HubWindowsGrouping {
    /// Groups windows by app across every display.
    ///
    /// Apps are ordered by their frontmost on-screen window; apps with only minimized or hidden
    /// windows follow in running-app order. Inside a group, on-screen windows come first (front to
    /// back), then minimized, then hidden ones. Windows of apps missing from `apps` are dropped.
    static func groups(windows: [HarborWindow], apps: [HarborRunningApp]) -> [HubWindowGroup] {
        let names = Dictionary(apps.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let appOrder = Dictionary(apps.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: [String: Int] = [:]
        let items = windows.filter { names[$0.appID] != nil }.map { window in
            // Two identical untitled windows produce the same key; suffix the repeats.
            let base = stableID(for: window)
            let count = seen[base, default: 0]
            seen[base] = count + 1
            return HubWindowItem(id: count == 0 ? base : "\(base)#\(count)", window: window)
        }
        var groups = Dictionary(grouping: items, by: \.window.appID).map { appID, items in
            HubWindowGroup(id: appID, name: names[appID] ?? "",
                           windows: items.sorted { rank($0) < rank($1) || (rank($0) == rank($1)
                               && $0.window.stackOrder < $1.window.stackOrder) })
        }
        groups.sort { first, second in
            let a = frontmost(first), b = frontmost(second)
            switch (a, b) {
            case let (a?, b?): return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil):
                return (appOrder[first.id] ?? .max, first.name) < (appOrder[second.id] ?? .max, second.name)
            }
        }
        return groups
    }

    /// Keeps the windows whose title or app name contains every word of `query`, ignoring case
    /// and diacritics. A match on the app name keeps all of that app's windows; groups left empty
    /// are dropped.
    static func filter(_ groups: [HubWindowGroup], query: String) -> [HubWindowGroup] {
        let words = normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return groups }
        return groups.compactMap { group in
            let name = normalized(group.name)
            var result = group
            result.windows = group.windows.filter { item in
                let haystack = name + " " + normalized(item.window.title ?? "")
                return words.allSatisfy(haystack.contains)
            }
            return result.windows.isEmpty ? nil : result
        }
    }

    /// A key for `window` that stays the same across discovery passes.
    ///
    /// Window-server numbers are stable for a window's lifetime, so they win when present.
    /// Otherwise (no Screen Recording, minimized windows) the process, state, title, and rounded
    /// frame stand in; a moved or retitled window then counts as new, which only resets its selection.
    static func stableID(for window: HarborWindow) -> String {
        if let number = window.captureID { return "w\(number)" }
        let frame = window.frame
        let geometry = [frame.minX, frame.minY, frame.width, frame.height].map { String(Int($0.rounded())) }
            .joined(separator: ",")
        return "p\(window.processIdentifier)|\(window.state)|\(window.title ?? "")|\(geometry)"
    }

    private static func rank(_ item: HubWindowItem) -> Int {
        switch item.window.state {
        case .visible: 0
        case .minimized: 1
        case .hidden: 2
        }
    }

    private static func frontmost(_ group: HubWindowGroup) -> Int? {
        group.windows.filter { $0.window.state == .visible }.map(\.window.stackOrder).min()
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

/// Arrow-key movement across the Windows tab's cards.
nonisolated enum HubWindowsNavigation {
    /// The card to select after an arrow key.
    ///
    /// Left and right step through reading order (groups in order, windows within each), which
    /// matches the wrapping layout. Up and down pick the nearest card above or below using the
    /// cards' laid-out frames, with Radar's scoring; without a candidate the selection stays.
    /// - Parameters:
    ///   - current: The selected card, or nil to select the first card.
    ///   - order: Every shown card in reading order.
    ///   - frames: Card frames in one shared coordinate space; cards without a frame are skipped
    ///     for up and down.
    static func next(from current: String?, direction: HarborDirection, order: [String],
                     frames: [String: CGRect]) -> String? {
        guard let first = order.first else { return nil }
        guard let current, let index = order.firstIndex(of: current) else { return first }
        switch direction {
        case .left: return order[max(index - 1, 0)]
        case .right: return order[min(index + 1, order.count - 1)]
        case .up, .down:
            guard let origin = frames[current] else { return current }
            // HarborNavigation works on UUIDs; give each candidate a temporary one.
            let candidates = order.filter { $0 != current }.compactMap { id in frames[id].map { (UUID(), id, $0) } }
            let lookup = Dictionary(uniqueKeysWithValues: candidates.map { ($0.0, $0.1) })
            let picked = HarborNavigation.next(from: origin, direction: direction,
                                               candidates: candidates.map { ($0.0, $0.2) })
            return picked.flatMap { lookup[$0] } ?? current
        }
    }
}
