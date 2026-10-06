import AppKit
import Testing
@testable import DeeDock

@MainActor
struct CompactLauncherTests {
    private func model(appCount: Int) -> CompactLauncherModel {
        let applications = (0..<appCount).map { index in
            LauncherApplication(reference: ApplicationReference(bundleIdentifier: "example.app\(index)",
                url: URL(fileURLWithPath: "/Applications/App \(String(format: "%02d", index)).app"),
                name: "App \(String(format: "%02d", index))"))
        }
        let catalog = ApplicationCatalog(service: ApplicationService(),
                                         launcherLibrary: LauncherLibrary(applications: applications))
        return CompactLauncherModel(launcher: LauncherState(catalog: catalog))
    }

    @Test("Arrow navigation enters at the first app, moves by rows, and stops at both ends")
    func navigationStaysInBounds() {
        let model = model(appCount: 8)
        let ids = model.results.map(\.id)
        #expect(!model.navigating)
        model.move(by: 0)
        #expect(model.selectedID == ids[0])
        model.move(by: CompactLauncherLayout.columns)
        #expect(model.selectedID == ids[CompactLauncherLayout.columns])
        model.move(by: CompactLauncherLayout.columns)
        #expect(model.selectedID == ids.last)
        model.move(by: -100)
        #expect(model.selectedID == ids.first)
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
