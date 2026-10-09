import Foundation
import Testing
@testable import DeeDock

/// Files tab state: pane history, selection ranges, `hub.files.v1` persistence, and the home
/// fallback for vanished locations. Uses an in-memory folder tree; nothing touches the disk.
@MainActor
struct HubFilesModelTests {
    private let home = URL(filePath: "/Users/tester")

    private func source() -> HubFilesMemoryDataSource {
        let source = HubFilesMemoryDataSource(home: home)
        for folder in ["Desktop", "Documents", "Downloads", "Documents/Projects", "Documents/Projects/DOKK"] {
            source.add("/Users/tester/\(folder)")
        }
        source.add("/Applications")
        return source
    }

    private func defaults() -> UserDefaults {
        let suite = "dokk.tests.hub.files.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func folder(_ path: String) -> HubFilesLocation { .folder(URL(filePath: path)) }

    private func pane(_ source: HubFilesMemoryDataSource, at path: String) -> HubFilesPane {
        HubFilesPane(location: folder(path), dataSource: source, anchors: HubFilesPlace.anchors(home: home))
    }

    // MARK: History

    @Test("Back and forward walk the history, and a new navigation clears forward")
    func backForward() {
        let pane = pane(source(), at: "/Users/tester/Documents")
        pane.navigate(to: folder("/Users/tester/Documents/Projects"))
        pane.navigate(to: folder("/Users/tester/Documents/Projects/DOKK"))

        pane.goBack()
        #expect(pane.location == folder("/Users/tester/Documents/Projects"))
        #expect(pane.canGoForward)

        pane.goBack()
        #expect(pane.location == folder("/Users/tester/Documents"))
        #expect(!pane.canGoBack)

        pane.goForward()
        #expect(pane.location == folder("/Users/tester/Documents/Projects"))

        pane.navigate(to: folder("/Users/tester/Downloads"))
        #expect(!pane.canGoForward)
        pane.goBack()
        #expect(pane.location == folder("/Users/tester/Documents/Projects"))
    }

    @Test("Navigating to the current location does not add history")
    func sameLocation() {
        let pane = pane(source(), at: "/Users/tester/Documents")
        pane.navigate(to: .folder(normalizing: URL(filePath: "/Users/tester/Documents/")))
        #expect(!pane.canGoBack)
    }

    @Test("Parent goes up one folder, pushes history, and stops at the root")
    func parent() {
        let pane = pane(source(), at: "/Users/tester/Documents/Projects")
        pane.goToParent()
        #expect(pane.location == folder("/Users/tester/Documents"))
        pane.goBack()
        #expect(pane.location == folder("/Users/tester/Documents/Projects"))

        let root = self.pane(source(), at: "/")
        #expect(!root.canGoToParent)
        root.goToParent()
        #expect(root.location == folder("/"))
    }

    @Test("Breadcrumbs start at the nearest sidebar location")
    func breadcrumbs() {
        let pane = pane(source(), at: "/Users/tester/Documents/Projects/DOKK")
        #expect(pane.pathChain.map(\.path) == ["/Users/tester/Documents", "/Users/tester/Documents/Projects",
                                               "/Users/tester/Documents/Projects/DOKK"])
        let outside = self.pane(source(), at: "/Library/Fonts")
        #expect(outside.pathChain.map(\.path) == ["/", "/Library", "/Library/Fonts"])
    }

    // MARK: Selection

    private let order = (1...6).map { URL(filePath: "/f/\($0)") }

    @Test("Shift-click selects the range from the anchor in either direction")
    func shiftRange() {
        var selection = HubFilesSelection()
        selection.click(order[1], mode: .replace, order: order)
        selection.click(order[4], mode: .extend, order: order)
        #expect(selection.urls == Set(order[1...4]))

        selection.click(order[0], mode: .extend, order: order)
        #expect(selection.urls == Set(order[0...1]))
        #expect(selection.anchor == order[1])
    }

    @Test("Command-click toggles and moves the anchor")
    func toggle() {
        var selection = HubFilesSelection()
        selection.click(order[0], mode: .replace, order: order)
        selection.click(order[3], mode: .toggle, order: order)
        #expect(selection.urls == [order[0], order[3]])
        selection.click(order[0], mode: .toggle, order: order)
        #expect(selection.urls == [order[3]])
        selection.click(order[5], mode: .extend, order: order)
        #expect(selection.urls == Set(order[3...5]))
    }

    @Test("Arrow keys move and clamp; Shift-arrows grow and shrink around the anchor")
    func arrows() {
        var selection = HubFilesSelection()
        selection.move(by: 1, order: order, extending: false)
        #expect(selection.urls == [order[0]])
        selection.move(by: -1, order: order, extending: false)
        #expect(selection.urls == [order[0]])

        selection.move(by: 2, order: order, extending: true)
        #expect(selection.urls == Set(order[0...2]))
        selection.move(by: -1, order: order, extending: true)
        #expect(selection.urls == Set(order[0...1]))

        selection.move(by: 10, order: order, extending: false)
        #expect(selection.urls == [order[5]])
    }

    @Test("Without a cursor, moving back starts at the last item")
    func backFromNothing() {
        var selection = HubFilesSelection()
        selection.move(by: -1, order: order, extending: false)
        #expect(selection.urls == [order[5]])
    }

    @Test("Pruning drops items that left the listing")
    func prune() {
        var selection = HubFilesSelection()
        selection.set([order[1], order[2]])
        selection.prune(to: [order[2], order[3]])
        #expect(selection.urls == [order[2]])
        #expect(selection.anchor == nil)
    }

    // MARK: Persistence

    @Test("First run matches the mockup: Documents | Downloads split, then Downloads")
    func firstRun() {
        let model = HubFilesModel(defaults: defaults(), dataSource: source())
        #expect(model.tabs.count == 2)
        #expect(model.tabs[0].isSplit)
        #expect(model.tabs[0].panes.map(\.location) == [folder("/Users/tester/Documents"), folder("/Users/tester/Downloads")])
        #expect(model.tabs[1].panes.map(\.location) == [folder("/Users/tester/Downloads")])
        #expect(model.showsPreview)
    }

    @Test("Tabs, locations, view modes, sorts, split, and preview survive a relaunch")
    func roundTrip() {
        let defaults = defaults(), source = source()
        let model = HubFilesModel(defaults: defaults, dataSource: source)
        model.activePane.navigate(to: folder("/Users/tester/Documents/Projects"))
        model.activePane.sort = HubFileSort(key: .modified, ascending: false)
        model.toggleSplit()
        model.newTab()
        model.selectedTab.viewMode = .columns
        model.activePane.navigate(to: .recents)
        model.showsPreview = false
        model.persist()

        let restored = HubFilesModel(defaults: defaults, dataSource: source)
        #expect(restored.tabs.count == 3)
        #expect(restored.selectedTabID == restored.tabs[2].id)
        #expect(!restored.tabs[0].isSplit)
        #expect(restored.tabs[0].panes[0].location == folder("/Users/tester/Documents/Projects"))
        #expect(restored.tabs[0].panes[0].sort == HubFileSort(key: .modified, ascending: false))
        #expect(restored.tabs[2].viewMode == .columns)
        #expect(restored.tabs[2].activePane.location == .recents)
        #expect(!restored.showsPreview)
    }

    @Test("A location that no longer exists restores as home")
    func vanishedOnRestore() {
        let defaults = defaults(), source = source()
        let model = HubFilesModel(defaults: defaults, dataSource: source)
        model.activePane.navigate(to: folder("/Users/tester/Documents/Projects/DOKK"))
        model.persist()

        source.remove("/Users/tester/Documents/Projects")
        let restored = HubFilesModel(defaults: defaults, dataSource: source)
        #expect(restored.tabs[0].panes[0].location == folder("/Users/tester"))
        #expect(restored.tabs[0].panes[1].location == folder("/Users/tester/Downloads"))
    }

    @Test("Panes on an ejected volume go home")
    func ejectedVolume() {
        let source = source()
        source.add("/Volumes/USB")
        source.add("/Volumes/USB/Photos")
        let model = HubFilesModel(defaults: defaults(), dataSource: source)
        model.activePane.navigate(to: folder("/Volumes/USB/Photos"))
        model.volumeDidUnmount(URL(filePath: "/Volumes/USB/"))
        #expect(model.activePane.location == folder("/Users/tester"))
        #expect(model.tabs[0].panes[1].location == folder("/Users/tester/Downloads"))
    }

    @Test("A shown folder deleted while visible falls back home on reload")
    func vanishedWhileShown() async throws {
        let source = source()
        let model = HubFilesModel(defaults: defaults(), dataSource: source)
        model.activePane.navigate(to: folder("/Users/tester/Documents/Projects"))
        source.remove("/Users/tester/Documents/Projects")
        model.activateWithoutShell()
        for _ in 0..<50 where model.activePane.location != folder("/Users/tester") {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.activePane.location == folder("/Users/tester"))
    }

    @Test("Closing tabs keeps at least one")
    func closeTabs() {
        let model = HubFilesModel(defaults: defaults(), dataSource: source())
        model.closeTab(model.tabs[1].id)
        model.closeTab(model.tabs[0].id)
        #expect(model.tabs.count == 1)
    }
}
