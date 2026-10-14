import CoreGraphics

/// Decides what a drag over the Favorites list targets: a slot between rows, a row's folder, or
/// nothing. Pure geometry so it can be tested without views.
///
/// Positions are top-down distances in one coordinate space (the sidebar converts screen points
/// into it). `rows` is the *base* layout: the rows as they sit with no insertion slot open and, for
/// a reorder, without the lifted row. Opening a slot pushes the rows under it down; mapping the
/// pointer back into the base layout first means the slot appearing under the pointer can't
/// change the answer, which would otherwise make the slot flicker open and shut.
nonisolated struct HubFilesSidebarDropLayout: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        /// The row's index in the Favorites list (with the lifted row still counted).
        var index: Int
        var top: CGFloat
        var bottom: CGFloat
        /// Whether a file drop in the middle of the row lands in its folder (not Recents, not a
        /// missing or disconnected folder, not a folder being dragged).
        var acceptsInto: Bool
    }

    /// An open insertion slot: where it starts in the base layout and how tall it is drawn.
    struct Slot: Equatable, Sendable {
        var index: Int
        var top: CGFloat
        var height: CGFloat
    }

    enum Mode: Equatable, Sendable {
        /// Files or folders dragged in. `canInsert` is false when none of them is a folder.
        case items(canInsert: Bool)
        /// A sidebar row being reordered: every position inserts, nothing drops "into".
        case reorder
    }

    enum Target: Equatable, Sendable {
        /// Open a slot before the row at this index (the count means "at the end").
        case insert(Int)
        /// Drop into the folder of the row at this index.
        case into(Int)
        case none
    }

    /// Favorites rows top to bottom, in base layout.
    var rows: [Row]
    /// The number of Favorites entries, the index of "at the end".
    var count: Int
    /// The top of the Favorites area (its header): from here down to the first row inserts first.
    var top: CGFloat
    /// The bottom of the Favorites area (the end slot, else the last row plus a margin). Between
    /// the last row and this edge inserts at the end.
    var bottom: CGFloat

    /// The fraction of a row's height at its top and bottom that means "between rows".
    static let edgeFraction: CGFloat = 0.25

    func target(at y: CGFloat, slot: Slot?, mode: Mode) -> Target {
        var y = y
        if let slot, y >= slot.top {
            if y < slot.top + slot.height { return .insert(slot.index) }
            y -= slot.height
        }
        return baseTarget(at: y, mode: mode)
    }

    /// Where a slot for `index` starts in the base layout.
    func slotTop(for index: Int) -> CGFloat {
        if let row = rows.first(where: { $0.index >= index }) { return row.top }
        return rows.last?.bottom ?? top
    }

    private func baseTarget(at y: CGFloat, mode: Mode) -> Target {
        let inserts: Bool
        switch mode {
        case .items(let canInsert): inserts = canInsert
        case .reorder: inserts = true
        }
        guard y >= top, y <= bottom else { return .none }
        if let row = rows.first(where: { y >= $0.top && y <= $0.bottom }) {
            let fraction = (y - row.top) / max(row.bottom - row.top, 1)
            let nearer = fraction < 0.5 ? row.index : row.index + 1
            if mode == .reorder { return .insert(nearer) }
            if inserts, fraction < Self.edgeFraction || fraction > 1 - Self.edgeFraction { return .insert(nearer) }
            if row.acceptsInto { return .into(row.index) }
            return inserts ? .insert(nearer) : .none
        }
        guard inserts else { return .none }
        if let first = rows.first, y < first.top { return .insert(first.index) }
        return .insert(count)
    }
}
