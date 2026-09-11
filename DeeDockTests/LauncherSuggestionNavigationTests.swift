import Testing
@testable import DeeDock

struct LauncherSuggestionNavigationTests {
    @Test("Suggested duplicates keep separate selection and continuous reading order")
    func duplicateIdentity() {
        let rows: [[LauncherBrowseID]] = [[.suggested("A")], [.application("A")], [.application("B")]]
        #expect(LauncherBrowseNavigation.move(.suggested("A"), distance: 1, columns: 1, rows: rows) == .application("A"))
        #expect(LauncherBrowseNavigation.move(.application("A"), distance: -1, columns: 1, rows: rows) == .suggested("A"))
    }

    @Test("Vertical navigation crosses a short suggestion row without skipping ordinary apps")
    func partialRows() {
        let rows: [[LauncherBrowseID]] = [
            [.suggested("A"), .suggested("B"), .suggested("C")],
            [.application("A"), .application("B"), .application("C"), .application("D"), .application("E")],
            [.application("F"), .application("G")]
        ]
        #expect(LauncherBrowseNavigation.move(.suggested("B"), distance: 5, columns: 5, rows: rows) == .application("B"))
        #expect(LauncherBrowseNavigation.move(.application("E"), distance: -5, columns: 5, rows: rows) == .suggested("C"))
        #expect(LauncherBrowseNavigation.move(.application("E"), distance: 5, columns: 5, rows: rows) == .application("G"))
        #expect(LauncherBrowseNavigation.move(.suggested("C"), distance: 1, columns: 5, rows: rows) == .application("A"))
    }

    @Test("A removed selection repairs only on deliberate navigation")
    func removedSelection() {
        let rows: [[LauncherBrowseID]] = [[.application("A")]]
        #expect(LauncherBrowseNavigation.move(.suggested("A"), distance: 1, columns: 3, rows: rows) == .application("A"))
        #expect(LauncherBrowseNavigation.move(.suggested("A"), distance: 1, columns: 3, rows: []) == nil)
    }
}
