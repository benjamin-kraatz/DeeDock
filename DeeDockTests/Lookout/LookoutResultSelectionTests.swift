import Foundation
import Testing
@testable import DeeDock

/// One selection across the Files search sections: names, then Lookout's strong hits, then its weaker hits only
/// while the fold is open. The order is pure (`HubFilesSearchOrder`); the model tests walk it with the arrow-key
/// entry point over preview overrides, so no Spotlight query or Lookout service runs.
@MainActor
struct LookoutResultSelectionTests {
    private let home = URL(filePath: "/Users/tester")
    private let names = [URL(filePath: "/Users/tester/Documents/dog.txt"), URL(filePath: "/Users/tester/Desktop/Dogs")]
    private let strong = [LookoutUIFixtures.hit("/Users/tester/Desktop/Beach/IMG_1.HEIC", kind: .image),
                          LookoutUIFixtures.hit("/Users/tester/Desktop/Beach", folderFiles: 4)]
    private let weak = [LookoutUIFixtures.hit("/Users/tester/Downloads/receipt.pdf", kind: .pdf, segment: .page, loc: 1)]

    private var results: LookoutResultSet { LookoutUIFixtures.results(strong: strong, weak: weak) }

    // MARK: Order

    @Test("Names come first, then strong hits; weaker hits only while the fold is open")
    func order() {
        let folded = HubFilesSearchOrder.flattened(names: names, lookout: results, weakExpanded: false)
        #expect(folded == [.name(names[0]), .name(names[1]), .lookout(strong[0].path), .lookout(strong[1].path)])
        let open = HubFilesSearchOrder.flattened(names: names, lookout: results, weakExpanded: true)
        #expect(open == folded + [.lookout(weak[0].path)])
    }

    @Test("The same file found by name and by content is two results")
    func sameFileInBothSections() {
        let path = "/Users/tester/Documents/dog.txt"
        let order = HubFilesSearchOrder.flattened(
            names: [URL(filePath: path)], lookout: LookoutUIFixtures.results(strong: [LookoutUIFixtures.hit(path)]),
            weakExpanded: false)
        #expect(order.count == 2 && Set(order).count == 2)
    }

    @Test("Steps clamp at both ends and start from the first or last without a cursor")
    func steps() {
        let order = HubFilesSearchOrder.flattened(names: names, lookout: results, weakExpanded: false)
        #expect(HubFilesSearchOrder.step(from: nil, by: 1, in: order) == order.first)
        #expect(HubFilesSearchOrder.step(from: nil, by: -1, in: order) == order.last)
        #expect(HubFilesSearchOrder.step(from: order[1], by: 1, in: order) == order[2])   // names → Lookout
        #expect(HubFilesSearchOrder.step(from: order[2], by: -1, in: order) == order[1])  // Lookout → names
        #expect(HubFilesSearchOrder.step(from: order.last, by: 1, in: order) == order.last)
        #expect(HubFilesSearchOrder.step(from: order.first, by: -1, in: order) == order.first)
        // A weaker hit that folded away is no longer a cursor: the step starts over.
        #expect(HubFilesSearchOrder.step(from: .lookout(weak[0].path), by: 1, in: order) == order.first)
        #expect(HubFilesSearchOrder.step(from: nil, by: 1, in: []) == nil)
    }

    // MARK: Model

    private func model() -> HubFilesModel {
        let suite = "dokk.tests.lookout.selection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let source = HubFilesMemoryDataSource(home: home)
        let items = [source.add(names[0].path, kind: .plainText, size: 10), source.add(names[1].path)]
        let model = HubFilesModel(defaults: defaults, dataSource: source)
        model.previewOverrides.searchResults = items
        model.previewOverrides.lookoutStatus = .ready
        model.previewOverrides.lookoutPhase = .done
        model.previewOverrides.lookoutResults = results
        model.query = "dog"
        return model
    }

    @Test("Down walks the names into Lookout's strong hits and stops above the closed fold")
    func downAcrossSections() {
        let model = model()
        model.moveSearchSelection(by: 1, extending: false)
        model.moveSearchSelection(by: 1, extending: false)
        #expect(model.searchSelection.contains(names[1]) && model.lookoutSelection == nil)
        model.moveSearchSelection(by: 1, extending: false)
        #expect(model.searchSelection.isEmpty && model.lookoutSelection == strong[0].path)
        #expect(model.actionableItems.map(\.url.path) == [strong[0].path])
        model.moveSearchSelection(by: 5, extending: false)
        #expect(model.lookoutSelection == strong[1].path)   // the weaker hit stays folded away
        #expect(model.searchScrollRequest?.id == .lookout(strong[1].path))
    }

    @Test("Up from Lookout returns to the last name")
    func upIntoNames() {
        let model = model()
        model.clickLookoutResult(strong[0])
        model.moveSearchSelection(by: -1, extending: false)
        #expect(model.lookoutSelection == nil && model.searchSelection.contains(names[1]) && model.searchSelection.count == 1)
    }

    @Test("Opening the fold adds the weaker hits; closing it moves a weaker selection to the last strong hit")
    func fold() {
        let model = model()
        model.setLookoutWeakExpanded(true)
        model.clickLookoutResult(strong[1])
        model.moveSearchSelection(by: 1, extending: false)
        #expect(model.lookoutSelection == weak[0].path)
        model.setLookoutWeakExpanded(false)
        #expect(model.lookoutSelection == strong[1].path)
        #expect(model.selectedLookoutHit == strong[1])
    }

    @Test("Clicking a name clears the Lookout selection, and a new query clears both and folds again")
    func clicksAndNewQuery() {
        let model = model()
        model.setLookoutWeakExpanded(true)
        model.clickLookoutResult(strong[0])
        model.clickSearchResult(names[0], mode: .replace)
        #expect(model.lookoutSelection == nil && model.searchSelection.contains(names[0]))
        model.clickLookoutResult(strong[0])
        #expect(model.searchSelection.isEmpty)
        model.query = "dogs"
        #expect(model.lookoutSelection == nil && model.searchSelection.isEmpty && !model.lookoutWeakExpanded)
    }
}
