import AppKit
import Foundation
import Testing

struct FolderStackSearchTests {
    private func reference(_ name: String) -> FolderStackEntryReference {
        FolderStackEntryReference(url: URL(fileURLWithPath: "/Search/\(name)"), name: name,
                                  isFolder: !name.contains("."))
    }

    private func entry(_ name: String) -> FolderStackEntry {
        FolderStackEntry(reference: reference(name), icon: NSImage())
    }

    private func state(_ names: [String]) -> FolderStackState {
        FolderStackState(folder: FolderReference(url: URL(fileURLWithPath: "/Search"), name: "Search",
                                                 bookmarkData: Data(), presentation: .list),
                         entries: names.map(entry))
    }

    @Test("Terms match in any order and fold case and diacritics")
    func matching() {
        let file = reference("Ärger Report 2024.pdf")
        #expect(FolderStackSearchFilter.matches(file, terms: FolderStackSearchFilter.terms(in: "report arger")))
        #expect(FolderStackSearchFilter.matches(file, terms: FolderStackSearchFilter.terms(in: "  ")))
        #expect(!FolderStackSearchFilter.matches(file, terms: FolderStackSearchFilter.terms(in: "report 2025")))
    }

    @Test("A bare extension matches every file of that type")
    func extensionMatching() {
        let terms = FolderStackSearchFilter.terms(in: "png")
        #expect(FolderStackSearchFilter.matches(reference("Harbor.png"), terms: terms))
        #expect(!FolderStackSearchFilter.matches(reference("Harbor.jpg"), terms: terms))
    }

    @MainActor
    @Test("The field appears only past the threshold, and stays while a query is active")
    func availability() {
        let short = state((1...FolderStackSearchFilter.threshold).map { "item \($0).txt" })
        #expect(!short.searchAvailable)
        let long = state((1...(FolderStackSearchFilter.threshold + 1)).map { "item \($0).txt" })
        #expect(long.searchAvailable)
        long.query = "item 1"
        #expect(long.searchAvailable)
    }

    @MainActor
    @Test("A query narrows the listing without discarding the loaded entries")
    func filtering() {
        let state = state(["Invoice 1.pdf", "Invoice 2.pdf", "Notes.txt"])
        state.query = "invoice"
        #expect(state.visibleEntries.map(\.reference.name) == ["Invoice 1.pdf", "Invoice 2.pdf"])
        #expect(state.entries.count == 3)
        state.query = "   "
        #expect(!state.searching)
        #expect(state.visibleEntries.count == 3)
    }

    @MainActor
    @Test("Selection follows the query instead of pointing at a hidden item")
    func selectionFollowsQuery() {
        let state = state(["Invoice 1.pdf", "Notes.txt"])
        state.selectedID = state.entries.last?.id
        state.query = "invoice"
        #expect(state.selectedID == state.entries.first?.id)
        state.query = "nothing matches"
        #expect(state.selectedID == nil)
        state.clearSearch()
        #expect(state.selectedID == state.entries.first?.id)
    }

    @MainActor
    @Test("Keyboard selection wraps within the filtered listing, skipping hidden items")
    func keyboardSelection() {
        let state = state(["Invoice 1.pdf", "Notes.txt", "Invoice 2.pdf"])
        state.query = "invoice"
        func selectedName() -> String? { state.entries.first { $0.id == state.selectedID }?.reference.name }
        #expect(selectedName() == "Invoice 1.pdf")
        state.select(by: 1)
        #expect(selectedName() == "Invoice 2.pdf")
        state.select(by: 1)
        #expect(selectedName() == "Invoice 1.pdf")
    }
}
