import AppKit
import Testing
@testable import DeeDock

@MainActor
struct DockArrangementMenuTests {
    @Test("Without an override, the menu writes the shared value; with one, it writes the display's")
    func writesInheritedSource() {
        let defaults = DockSettingsStore(repository: nil)
        let profiles = DisplayProfilesStore(defaults: defaults, repository: nil)
        let display = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
        profiles.synchronize([display]) { [] }
        let dock = DockStore(displayID: display.id, catalog: ApplicationCatalog(service: ArrangementFixtureService()),
                             profiles: profiles)
        defer { dock.stop() }

        dock.setAutoHide(!DockSettings.defaults.behavior.autoHide)
        dock.setAlignment(.end)
        #expect(defaults.value.behavior.autoHide == !DockSettings.defaults.behavior.autoHide)
        #expect(defaults.value.alignment == .end)
        #expect(profiles.document.profiles[display.id]?.overrides.contains(.autoHide) == false)
        #expect(profiles.document.profiles[display.id]?.overrides.contains(.alignment) == false)

        profiles.update(display.id, keyPath: \.alignment, to: .center)
        dock.setAlignment(.start)
        #expect(profiles.effectiveSettings(for: display.id).alignment == .start)
        #expect(defaults.value.alignment == .end)
    }

    @Test("The group checks the current choices and names them for the dock's edge",
          arguments: [DockEdge.bottom, .top, .left, .right])
    func builds(edge: DockEdge) throws {
        let builder = DockArrangementMenu()
        builder.setAutoHide = { _ in }
        builder.setAlignment = { _ in }
        builder.autoHide = true
        builder.alignment = .end
        builder.edge = edge
        let menu = NSMenu()
        builder.addItems(to: menu)

        #expect(menu.items.count == 3)
        #expect(menu.items[0].isSeparatorItem)
        #expect(menu.items[1].title == String(localized: .dockMenuAutoHide))
        #expect(menu.items[1].state == .on)
        #expect(menu.items[2].title == String(localized: .dockMenuPosition))
        let choices = try #require(menu.items[2].submenu).items
        let expected: [LocalizedStringResource] = edge.isVertical
            ? [.settingsAlignTop, .settingsAlignCenter, .settingsAlignBottom]
            : [.settingsAlignLeft, .settingsAlignCenter, .settingsAlignRight]
        #expect(choices.map(\.title) == expected.map { String(localized: $0) })
        #expect(choices.map(\.state) == [.off, .off, .on])
    }

    @Test("An unwired panel adds nothing")
    func unwired() {
        let menu = NSMenu()
        DockArrangementMenu().addItems(to: menu)
        #expect(menu.items.isEmpty)
    }

    @Test("Choosing items turns auto-hide over and picks the alignment")
    func actions() async throws {
        let builder = DockArrangementMenu()
        builder.autoHide = false
        builder.alignment = .center
        let menu = NSMenu()
        let toggled = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            builder.setAutoHide = { done.resume(returning: $0) }
            builder.setAlignment = { _ in }
            builder.addItems(to: menu)
            menu.performActionForItem(at: 1)
        }
        #expect(toggled)

        let submenu = try #require(menu.items[2].submenu)
        let chosen = await withCheckedContinuation { (done: CheckedContinuation<DockSettings.Alignment, Never>) in
            builder.setAlignment = { done.resume(returning: $0) }
            submenu.performActionForItem(at: 0)
        }
        #expect(chosen == .start)
    }
}

@MainActor
private final class ArrangementFixtureService: ApplicationServicing {
    func runningApplications() -> [ApplicationReference] { [] }
    func defaultFavorites() -> [ApplicationReference] { [] }
    func resolvedURL(for reference: ApplicationReference) -> URL? { reference.url }
    func icon(for url: URL?) -> NSImage { NSImage(size: CGSize(width: 48, height: 48)) }
    func pruneIcons(keeping urls: Set<URL>) {}
    func openDocuments(_ urls: [URL], with reference: ApplicationReference) async throws { Issue.record("Unexpected document open") }
    func performPrimaryAction(_ reference: ApplicationReference) async throws -> ApplicationPrimaryActionOutcome {
        Issue.record("Menu tests must never toggle applications"); return .opened
    }
    func open(_ reference: ApplicationReference) async throws { Issue.record("Menu tests must never launch applications") }
}
