import AppKit
import Testing
@testable import DeeDock

/// About the width of a regular legacy scroller. Wider than the Shelf ideal grid's 6 pt of slack.
nonisolated private enum GridKeyboardFixture {
    static let legacyGutter: CGFloat = 15
}

@MainActor
struct AdaptiveGridLayoutTests {
    @Test("A folder grid is five columns at the ideal width and two at the minimum", arguments: [
        (DockPopoverGeometry.idealSize.width, CGFloat(0), 5),
        (DockPopoverGeometry.minimumSize.width, CGFloat(0), 2),
        // 490 pt is an exact five-column fit; a legacy gutter drops it to four.
        (CGFloat(490), CGFloat(0), 5),
        (CGFloat(490), GridKeyboardFixture.legacyGutter, 4),
    ])
    func folderColumnCounts(panel: CGFloat, gutter: CGFloat, columns: Int) {
        let width = gridWidth(panel: panel, padding: FolderStackGridMetrics.horizontalPadding, gutter: gutter)
        #expect(folderColumns(width: width) == columns)
    }

    @Test("A Shelf grid is four columns at its ideal width and two at the minimum", arguments: [
        (ShelfGridMetrics.idealPanelWidth, CGFloat(0), 4),
        (DockPopoverGeometry.minimumSize.width, CGFloat(0), 2),
        // Ideal Shelf content has 6 pt of slack. A ~15 pt legacy gutter leaves three columns.
        (ShelfGridMetrics.idealPanelWidth, GridKeyboardFixture.legacyGutter, 3),
    ])
    func shelfColumnCounts(panel: CGFloat, gutter: CGFloat, columns: Int) {
        let width = gridWidth(panel: panel, padding: ShelfGridMetrics.horizontalPadding, gutter: gutter)
        #expect(shelfColumns(width: width) == columns)
    }

    @Test("Column count is the largest row that still fits, including an exact fit")
    func exactFit() {
        let minimum = FolderStackGridMetrics.minimumCell
        let spacing = FolderStackGridMetrics.columnSpacing
        let two = 2 * minimum + spacing
        #expect(AdaptiveGridLayout.columnCount(width: two, minimum: minimum, spacing: spacing) == 2)
        #expect(AdaptiveGridLayout.columnCount(width: two - 1, minimum: minimum, spacing: spacing) == 1)
        #expect(AdaptiveGridLayout.columnCount(width: 0, minimum: minimum, spacing: spacing) == 1)
    }

    @Test("Grid arrows step one cell sideways and one row vertically")
    func arrowSteps() {
        #expect(AdaptiveGridLayout.gridStep(keyCode: 123, columns: 5) == -1)
        #expect(AdaptiveGridLayout.gridStep(keyCode: 124, columns: 5) == 1)
        #expect(AdaptiveGridLayout.gridStep(keyCode: 125, columns: 5) == 5)
        #expect(AdaptiveGridLayout.gridStep(keyCode: 126, columns: 2) == -2)
        #expect(AdaptiveGridLayout.gridStep(keyCode: 36, columns: 5) == nil)
    }

    @Test("A short last row stops the selection instead of wrapping")
    func clampedIndex() {
        #expect(AdaptiveGridLayout.clampedIndex(current: 5, count: 7, delta: 5) == 6)
        #expect(AdaptiveGridLayout.clampedIndex(current: 0, count: 7, delta: -5) == 0)
        #expect(AdaptiveGridLayout.clampedIndex(current: 0, count: 7, delta: -1) == 0)
        #expect(AdaptiveGridLayout.clampedIndex(current: 6, count: 7, delta: 1) == 6)
    }

    @Test("Folder grid keys follow the laid-out width and stop at the ends")
    func folderGridKeys() throws {
        let narrow = folderState(count: 7)
        try move(narrow, key: 125, panel: DockPopoverGeometry.minimumSize.width)
        #expect(index(narrow) == 2)
        try move(narrow, key: 124, panel: DockPopoverGeometry.minimumSize.width)
        #expect(index(narrow) == 3)
        try move(narrow, key: 123, panel: DockPopoverGeometry.minimumSize.width)
        #expect(index(narrow) == 2)
        try move(narrow, key: 126, panel: DockPopoverGeometry.minimumSize.width)
        try move(narrow, key: 126, panel: DockPopoverGeometry.minimumSize.width)
        #expect(index(narrow) == 0)
        try move(narrow, key: 123, panel: DockPopoverGeometry.minimumSize.width)
        #expect(index(narrow) == 0)

        let wide = folderState(count: 12)
        try move(wide, key: 125, panel: DockPopoverGeometry.idealSize.width)
        #expect(index(wide) == 5)
        try move(wide, key: 125, panel: DockPopoverGeometry.idealSize.width)
        #expect(index(wide) == 10)
        try move(wide, key: 125, panel: DockPopoverGeometry.idealSize.width)
        #expect(index(wide) == 11)
        try move(wide, key: 124, panel: DockPopoverGeometry.idealSize.width)
        #expect(index(wide) == 11)
    }

    @Test("Folder list arrows still wrap one item at a time")
    func folderListWraps() {
        let state = folderState(count: 3, presentation: .list)
        state.select(by: 1)
        state.select(by: 1)
        state.select(by: 1)
        #expect(index(state) == 0)
        state.select(by: -1)
        #expect(index(state) == 2)
    }

    @Test("Shelf grid keys follow the laid-out width and stop at the ends")
    func shelfGridKeys() throws {
        let narrow = shelfState(count: 6)
        try move(narrow, key: 125, panel: DockPopoverGeometry.minimumSize.width)
        #expect(index(narrow) == 2)
        try move(narrow, key: 124, panel: DockPopoverGeometry.minimumSize.width)
        #expect(index(narrow) == 3)
        try move(narrow, key: 125, panel: DockPopoverGeometry.minimumSize.width)
        try move(narrow, key: 125, panel: DockPopoverGeometry.minimumSize.width)
        #expect(index(narrow) == 5)
        try move(narrow, key: 125, panel: DockPopoverGeometry.minimumSize.width)
        #expect(index(narrow) == 5)

        let wide = shelfState(count: 10)
        try move(wide, key: 125, panel: ShelfGridMetrics.idealPanelWidth)
        #expect(index(wide) == 4)
        try move(wide, key: 126, panel: ShelfGridMetrics.idealPanelWidth)
        #expect(index(wide) == 0)
        try move(wide, key: 123, panel: ShelfGridMetrics.idealPanelWidth)
        #expect(index(wide) == 0)
    }

    @Test("A legacy gutter makes Shelf Down move by three columns")
    func shelfGutterStride() throws {
        let state = shelfState(count: 8)
        let width = gridWidth(panel: ShelfGridMetrics.idealPanelWidth, padding: ShelfGridMetrics.horizontalPadding,
                              gutter: GridKeyboardFixture.legacyGutter)
        state.gridContentWidth = width
        #expect(state.gridColumnCount == 3)
        try move(state, key: 125, width: width)
        #expect(index(state) == 3)
    }

    @Test("A Shelf arrow on the last item collapses a multiple selection without wrapping")
    func shelfEdgeCollapsesSelection() throws {
        let state = shelfState(count: 4)
        state.selection = Set(state.order)
        state.anchorID = state.order.last
        try move(state, key: 124, panel: ShelfGridMetrics.idealPanelWidth)
        #expect(state.anchorID == state.order.last)
        #expect(state.selection == Set([try #require(state.order.last)]))
    }

    @Test("Shelf list arrows still wrap one item at a time")
    func shelfListWraps() {
        let state = shelfState(count: 3, presentation: .list)
        state.select(by: 1)
        state.select(by: 1)
        state.select(by: 1)
        #expect(index(state) == 0)
        state.select(by: -1)
        #expect(index(state) == 2)
    }

    /// Width the grid is offered once padding and an optional gutter are gone. The views measure this.
    private func gridWidth(panel: CGFloat, padding: CGFloat, gutter: CGFloat = 0) -> CGFloat {
        panel - padding * 2 - gutter
    }

    private func folderColumns(width: CGFloat) -> Int {
        AdaptiveGridLayout.columnCount(width: width, minimum: FolderStackGridMetrics.minimumCell,
                                       spacing: FolderStackGridMetrics.columnSpacing)
    }

    private func shelfColumns(width: CGFloat) -> Int {
        AdaptiveGridLayout.columnCount(width: width, minimum: ShelfGridMetrics.minimumCell,
                                       spacing: ShelfGridMetrics.columnSpacing)
    }

    /// The same step the panel applies once the grid has reported `panel`'s content width.
    private func move(_ state: FolderStackState, key: UInt16, panel: CGFloat) throws {
        try move(state, key: key, width: gridWidth(panel: panel, padding: FolderStackGridMetrics.horizontalPadding))
    }

    private func move(_ state: FolderStackState, key: UInt16, width: CGFloat) throws {
        state.gridContentWidth = width
        let step = try #require(AdaptiveGridLayout.gridStep(keyCode: key, columns: state.gridColumnCount))
        state.selectClamped(by: step)
    }

    private func move(_ state: ShelfPanelState, key: UInt16, panel: CGFloat) throws {
        try move(state, key: key, width: gridWidth(panel: panel, padding: ShelfGridMetrics.horizontalPadding))
    }

    private func move(_ state: ShelfPanelState, key: UInt16, width: CGFloat) throws {
        state.gridContentWidth = width
        let step = try #require(AdaptiveGridLayout.gridStep(keyCode: key, columns: state.gridColumnCount))
        state.selectClamped(by: step)
    }

    private func folderState(count: Int, presentation: FolderStackPresentation = .grid) -> FolderStackState {
        let entries = (0..<count).map { offset in
            let name = String(format: "item-%02d", offset)
            let reference = FolderStackEntryReference(url: URL(fileURLWithPath: "/Grid/\(name)"), name: name, isFolder: false)
            return FolderStackEntry(reference: reference, icon: NSImage())
        }
        return FolderStackState(folder: FolderReference(url: URL(fileURLWithPath: "/Grid"), name: "Grid",
                                                        bookmarkData: Data(), presentation: presentation),
                                 entries: entries)
    }

    private func index(_ state: FolderStackState) -> Int {
        state.displayedEntries.firstIndex { $0.id == state.selectedID } ?? -1
    }

    private func shelfState(count: Int, presentation: ShelfPresentation = .grid) -> ShelfPanelState {
        let entries = (0..<count).map { offset in
            let name = String(format: "item-%02d", offset)
            let item = ShelfItem(url: URL(fileURLWithPath: "/Shelf/\(name)"), name: name, bookmarkData: Data())
            return ShelfPanelEntry(item: item, icon: NSImage(), isAvailable: true, location: "Shelf")
        }
        return ShelfPanelState(entries: entries, presentation: presentation)
    }

    private func index(_ state: ShelfPanelState) -> Int {
        state.anchorID.flatMap { id in state.order.firstIndex(of: id) } ?? -1
    }
}
