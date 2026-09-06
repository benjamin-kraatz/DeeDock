import Foundation
import Testing
@testable import DeeDock

@MainActor
struct MenuBarIconTests {
    @Test("Missing and unknown values use the icon")
    func defaultsAndUnknown() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(MenuBarIconController(defaults: defaults).style == .icon)
        defaults.set("banner", forKey: MenuBarIconController.key)
        #expect(MenuBarIconController(defaults: defaults).style == .icon)
    }

    @Test("Choosing the wordmark persists and reloads")
    func persistsWordmark() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MenuBarIconController(defaults: defaults)
        controller.setStyle(.wordmark)
        #expect(controller.style == .wordmark)
        #expect(defaults.string(forKey: MenuBarIconController.key) == "wordmark")
        #expect(MenuBarIconController(defaults: defaults).style == .wordmark)
        controller.setStyle(.icon)
        #expect(MenuBarIconController(defaults: defaults).style == .icon)
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "DeeDockMenuBarIconTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }
}
