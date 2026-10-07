import AppKit
import Testing
@testable import DeeDock

@MainActor
struct CompactLauncherTests {
    /// - Parameter suggested: Indexes of apps to rank as suggestions, in order, from an in-memory store.
    private func model(appCount: Int, suggested: [Int] = []) -> CompactLauncherModel {
        let applications = (0..<appCount).map { index in
            LauncherApplication(reference: ApplicationReference(bundleIdentifier: "example.app\(index)",
                url: URL(fileURLWithPath: "/Applications/App \(String(format: "%02d", index)).app"),
                name: "App \(String(format: "%02d", index))"))
        }
        let store = LauncherSuggestionsStore(directory: nil, defaults: nil)
        store.setEnabled(!suggested.isEmpty)
        let catalog = ApplicationCatalog(service: ApplicationService(),
                                         launcherLibrary: LauncherLibrary(applications: applications), suggestions: store)
        let launcher = LauncherState(catalog: catalog)
        if !suggested.isEmpty {
            // Without `begin`, the launcher keeps the full style; six grid columns allow the same three suggestions.
            launcher.navigationColumns = CompactLauncherLayout.columns
            let date = Date()
            launcher.suggestions.installPreview(LauncherSuggestionSnapshot(
                context: LauncherSuggestionContext(date: date, foregroundID: "example.source", modeID: nil),
                modelVersion: "test", rankedIDs: suggested.map { applications[$0].id },
                createdAt: date, generation: store.revision))
        }
        return CompactLauncherModel(launcher: launcher)
    }

    @Test("Arrow navigation enters at the first app, moves by rows, and stops at both ends")
    func navigationStaysInBounds() {
        let model = model(appCount: 8)
        let ids = model.results.map { LauncherBrowseID.application($0.id) }
        let columns = CompactLauncherLayout.columns
        #expect(!model.navigating)
        model.move(by: 0)
        #expect(model.selectedID == ids[0])
        model.move(by: columns - 1)
        model.move(by: columns)
        #expect(model.selectedID == ids.last, "Down keeps the column, clamped to the short last row")
        model.move(by: columns)
        #expect(model.selectedID == ids.last, "Down on the last row stays put")
        model.move(by: -100)
        #expect(model.selectedID == ids.first)
    }

    @Test("Suggestions lead navigation with their own identity, and vertical moves keep the column")
    func suggestedRowNavigation() throws {
        let model = model(appCount: 8, suggested: [3, 5])
        let apps = model.results.map(\.id)
        let suggested = model.suggestions.map(\.id)
        try #require(suggested == [apps[3], apps[5]])
        model.move(by: 0)
        #expect(model.selectedID == .suggested(apps[3]))
        model.move(by: 1)
        #expect(model.selectedID == .suggested(apps[5]))
        model.move(by: CompactLauncherLayout.columns)
        #expect(model.selectedID == .application(apps[1]))
        model.move(by: -CompactLauncherLayout.columns)
        #expect(model.selectedID == .suggested(apps[5]))
        model.query = "App"
        #expect(model.suggestions.isEmpty)
    }

    @Test("Typing clears the grid selection, and a query with no matches leaves nothing to select")
    func queryResetsSelection() {
        let model = model(appCount: 3)
        model.move(by: 0)
        model.query = "App 02"
        #expect(model.selectedID == nil)
        #expect(model.results.map(\.reference.name) == ["App 02"])
        model.query = "zzz"
        model.move(by: 0)
        #expect(model.selectedID == nil)
    }

    @Test("Launcher style defaults to full for older documents and inherits per display")
    func stylePersistence() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(DockSettings.defaults)) as? [String: Any])
        object.removeValue(forKey: "launcherStyle")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(DockSettings.self, from: legacy).launcherStyle == .full)

        var shared = DockSettings.defaults
        shared.launcherStyle = .compact
        #expect(try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(shared)).launcherStyle == .compact)
        var overrides = DockSettingsOverrides()
        #expect(overrides.resolving(shared).launcherStyle == .compact)
        overrides.set(.launcherStyle, from: DockSettings.defaults)
        #expect(overrides.contains(.launcherStyle))
        #expect(overrides.resolving(shared).launcherStyle == .full)
        let decoded = try JSONDecoder().decode(DockSettingsOverrides.self, from: JSONEncoder().encode(overrides))
        #expect(decoded.launcherStyle == .full)
    }
}
