import Foundation

/// A Finder-style multiple selection over an ordered list of item URLs.
///
/// `anchor` is where a Shift-range starts; `cursor` is the item arrow keys move from. Both are
/// kept separately so Shift-arrow grows or shrinks a range around a fixed anchor.
nonisolated struct HubFilesSelection: Equatable, Sendable {
    /// How a click changes the selection.
    enum ClickMode: Sendable {
        /// Plain click: select only this item.
        case replace
        /// Command-click: add or remove this item.
        case toggle
        /// Shift-click: select from the anchor to this item.
        case extend
    }

    private(set) var urls: Set<URL> = []
    private(set) var anchor: URL?
    private(set) var cursor: URL?

    var isEmpty: Bool { urls.isEmpty }
    var count: Int { urls.count }

    func contains(_ url: URL) -> Bool { urls.contains(url) }

    /// Selected URLs in `order`, the listing's visible order.
    func ordered(in order: [URL]) -> [URL] {
        order.filter(urls.contains)
    }

    /// Applies a click on `url`.
    mutating func click(_ url: URL, mode: ClickMode, order: [URL]) {
        switch mode {
        case .replace:
            set([url])
        case .toggle:
            cursor = url
            if urls.insert(url).inserted {
                anchor = url
            } else {
                urls.remove(url)
                // Deselecting must not leave the Shift-range anchor on an unselected item: keep a
                // still-selected anchor, otherwise move it to the selected item nearest the click.
                if let anchor, urls.contains(anchor) { break }
                anchor = nearestSelected(to: url, in: order)
            }
        case .extend:
            guard let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: url) else {
                set([url]); return
            }
            urls = Set(order[min(from, to)...max(from, to)])
            cursor = url
        }
    }

    /// Moves the cursor by `delta` positions in `order`, clamped to its ends.
    ///
    /// Without a cursor, a forward move starts at the first item and a backward move at the last.
    /// With `extending`, the selection becomes the range from the anchor to the new cursor.
    /// - Returns: The new cursor, or nil when `order` is empty.
    @discardableResult
    mutating func move(by delta: Int, order: [URL], extending: Bool) -> URL? {
        guard !order.isEmpty else { return nil }
        let target: Int
        if let cursor, let index = order.firstIndex(of: cursor) {
            target = min(max(index + delta, 0), order.count - 1)
        } else {
            target = delta >= 0 ? 0 : order.count - 1
        }
        let url = order[target]
        if extending, let anchor, order.contains(anchor) {
            click(url, mode: .extend, order: order)
        } else {
            set([url])
        }
        return url
    }

    /// Replaces the selection; the first URL becomes anchor and cursor.
    mutating func set(_ selection: [URL]) {
        urls = Set(selection)
        anchor = selection.first
        cursor = selection.first
    }

    /// Selects every item in `order`, keeping the cursor.
    mutating func selectAll(_ order: [URL]) {
        urls = Set(order)
        if anchor == nil { anchor = order.first }
        if cursor == nil { cursor = order.last }
    }

    /// The selected URL closest to `url` in `order`, or nil when nothing is selected.
    private func nearestSelected(to url: URL, in order: [URL]) -> URL? {
        guard let index = order.firstIndex(of: url) else { return ordered(in: order).first }
        return order.indices
            .filter { urls.contains(order[$0]) }
            .min { abs($0 - index) < abs($1 - index) }
            .map { order[$0] }
    }

    mutating func clear() {
        self = HubFilesSelection()
    }

    /// Drops URLs no longer in `order` (after a refresh), keeping anchor and cursor only if present.
    mutating func prune(to order: [URL]) {
        let present = Set(order)
        urls.formIntersection(present)
        if let anchor, !present.contains(anchor) { self.anchor = nil }
        if let cursor, !present.contains(cursor) { self.cursor = urls.first }
    }
}
