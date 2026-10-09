import AppKit
import Testing
@testable import DeeDock

/// Keyboard routing, per-display state, and file handover for the Hub's Apps tab.
///
/// The tab is never shown here: `hubTabDidAppear` would start window and app discovery, so the
/// launcher is marked active with its preview hook instead. No test presses Return, which would
/// open a real app.
@MainActor
struct HubAppsModelTests {
    private func model(appCount: Int = 8, suggested: [Int] = [], columns: Int = 4) -> HubAppsModel {
        let applications = (0..<appCount).map { index in
            LauncherApplication(reference: ApplicationReference(bundleIdentifier: "example.app\(index)",
                url: URL(fileURLWithPath: "/Applications/App \(String(format: "%02d", index)).app"),
                name: "App \(String(format: "%02d", index))"))
        }
        let store = LauncherSuggestionsStore(directory: nil, defaults: nil)
        store.setEnabled(!suggested.isEmpty)
        let catalog = ApplicationCatalog(service: ApplicationService(),
                                         launcherLibrary: LauncherLibrary(applications: applications),
                                         suggestions: store)
        let launcher = LauncherState(catalog: catalog)
        launcher.navigationColumns = columns
        launcher.activateForPreview()
        if !suggested.isEmpty {
            let date = Date()
            launcher.suggestions.installPreview(LauncherSuggestionSnapshot(
                context: LauncherSuggestionContext(date: date, foregroundID: "example.source", modeID: nil),
                modelVersion: "test", rankedIDs: suggested.map { applications[$0].id },
                createdAt: date, generation: store.revision))
        }
        return HubAppsModel(launcher: launcher)
    }

    private func key(_ code: UInt16, _ characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: code)!
    }

    @Test("Down from the search field enters the grid and moves by whole rows")
    func arrowsMoveByRows() {
        let model = model(columns: 4)
        let ids = model.launcher.results.map { LauncherBrowseID.application($0.id) }
        #expect(model.handleKeyDown(key(125), fromSearchField: true))
        #expect(model.launcher.selectedID == ids[0])
        #expect(model.handleKeyDown(key(125), fromSearchField: true))
        #expect(model.launcher.selectedID == ids[4])
        #expect(model.handleKeyDown(key(126), fromSearchField: true))
        #expect(model.launcher.selectedID == ids[0])
    }

    @Test("Left and right edit text in the field until arrow navigation has begun")
    func horizontalArrowsRespectTheField() {
        let model = model()
        #expect(!model.handleKeyDown(key(124), fromSearchField: true))
        #expect(model.launcher.selectedID == nil)
        _ = model.handleKeyDown(key(125), fromSearchField: true)
        #expect(model.handleKeyDown(key(124), fromSearchField: true))
        #expect(model.launcher.selectedID == .application(model.launcher.results[1].id))
        // From the results themselves, horizontal arrows always navigate.
        model.clearKeyboardSelection()
        #expect(model.handleKeyDown(key(124), fromSearchField: false))
    }

    @Test("Escape leaves arrow navigation first, then falls through to the shell")
    func escapeOrder() {
        let model = model()
        _ = model.handleKeyDown(key(125), fromSearchField: true)
        #expect(model.handleKeyDown(key(53), fromSearchField: true))
        #expect(model.launcher.selectedID == nil)
        #expect(!model.launcher.keyboardNavigationActive)
        #expect(!model.handleKeyDown(key(53), fromSearchField: true), "The shell clears the query or closes")
    }

    @Test("Tab drops the result selection and keeps native focus navigation")
    func tabClearsSelection() {
        let model = model()
        _ = model.handleKeyDown(key(125), fromSearchField: true)
        #expect(!model.handleKeyDown(key(48, "\t"), fromSearchField: true))
        #expect(model.launcher.selectedID == nil)
    }

    @Test("Typing while results have focus goes to the query; shortcuts are left alone")
    func typeToSearch() {
        let model = model()
        #expect(model.handleKeyDown(key(0, "a"), fromSearchField: false))
        #expect(model.query == "a")
        #expect(!model.handleKeyDown(key(0, "a"), fromSearchField: true), "The field edits its own text")
        #expect(!model.handleKeyDown(key(1, "s", modifiers: .command), fromSearchField: false))
        #expect(model.query == "a")
    }

    @Test("Suggestions are a single row of at most three cards, navigated before the grid")
    func suggestionsLeadNavigation() throws {
        let model = model(appCount: 10, suggested: [7, 2, 5, 1], columns: 6)
        let apps = model.launcher.results.map(\.id)
        let suggested = model.launcher.suggestedApplications.map(\.id)
        try #require(suggested == [apps[7], apps[2], apps[5]])
        _ = model.handleKeyDown(key(125), fromSearchField: true)
        #expect(model.launcher.selectedID == .suggested(apps[7]))
        _ = model.handleKeyDown(key(125), fromSearchField: true)
        #expect(model.launcher.selectedID == .application(apps[0]))
    }

    @Test("Browse scroll is remembered per display")
    func scrollPerDisplay() {
        let model = model()
        let launcher = model.launcher
        func context(_ id: String) -> HubAppsDisplayContext {
            HubAppsDisplayContext(displayID: id, dockStore: nil, usesLineIcons: false, lineIconMotion: .hover,
                                  appVisibility: .showAll, foregroundBundleIdentifier: nil)
        }
        let saved = LauncherBrowseScroll(context: .init(state: launcher, columns: 4, groups: launcher.groups), offset: 240)
        model.present(on: context("A"))
        launcher.browseScroll = saved
        model.present(on: context("B"))
        #expect(launcher.browseScroll == nil)
        model.present(on: context("A"))
        #expect(launcher.browseScroll?.offset == 240)
    }

    @Test("Display context sets line icons and the visibility suggestions respect")
    func displayContextAppliesSettings() {
        let model = model()
        model.present(on: HubAppsDisplayContext(displayID: "A", dockStore: nil, usesLineIcons: true,
                                                lineIconMotion: .hover, appVisibility: .hideRunning,
                                                foregroundBundleIdentifier: "example.source"))
        #expect(model.launcher.usesLineIcons)
        #expect(model.launcher.suggestionVisibility?() == .hideRunning)
    }

    @Test("Files handed over while the tab is visible enter file-action mode at once")
    func adoptWhileVisible() {
        let model = model()
        model.query = "App"
        model.adoptFiles(.owned(DocumentResourceAccess([URL(fileURLWithPath: "/tmp/HubAppsModelTests.txt")],
                                                       startAccess: { _ in false }, stopAccess: { _ in }),
                                source: .picker))
        #expect(model.launcher.usesFileActions)
        #expect(model.query.isEmpty)
    }
}
