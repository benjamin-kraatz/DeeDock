import Testing
import Foundation
@testable import DeeDock

/// The way back is the feature: every path has to leave a person able to get their own macOS
/// Dock settings back, exactly as they had them.
@Suite("Tucking away the macOS Dock")
@MainActor
struct SystemDockTuckTests {
    private let defaults = scratchDefaults()

    private func controller(_ service: InMemorySystemDockPreferences) -> SystemDockTuckController {
        SystemDockTuckController(service: service, repository: SystemDockTuckRepository(defaults: defaults))
    }

    private func expectTucked(_ service: InMemorySystemDockPreferences, _ orientation: String = "left") {
        #expect((service.stored[.autohide] as? NSNumber)?.boolValue == true)
        #expect((service.stored[.autohideDelay] as? NSNumber)?.doubleValue == 10)
        #expect((service.stored[.tileSize] as? NSNumber)?.intValue == 16)
        #expect(service.stored[.orientation] as? String == orientation)
    }

    @Test("Tucking away from macOS defaults writes all four values and restarts the Dock once")
    func tucksFromDefaults() {
        let service = InMemorySystemDockPreferences()
        let tuck = controller(service)
        tuck.tuckAway()
        expectTucked(service)
        #expect(service.restartCount == 1)
        #expect(tuck.isOn)
        #expect(tuck.tuckedOrientation == .left)
    }

    @Test("Restoring writes back the exact previous values and deletes keys that were absent")
    func restoresExactValues() {
        let service = InMemorySystemDockPreferences([.autohide: 1, .tileSize: 45])
        let tuck = controller(service)
        tuck.tuckAway()
        tuck.restore()
        #expect(service.stored[.autohide] as? Int == 1)
        #expect(service.stored[.tileSize] as? Int == 45)
        #expect(service.stored[.autohideDelay] == nil)
        #expect(service.stored[.orientation] == nil)
        #expect(service.restartCount == 2)
        #expect(!tuck.isOn)
        #expect(!tuck.isTucked)
        #expect(SystemDockTuckRepository(defaults: defaults).load() == SystemDockTuckRecord())
    }

    @Test("A setting the person changed while tucked away is kept on restore")
    func keepsPersonsChange() {
        let service = InMemorySystemDockPreferences([.tileSize: 45])
        let tuck = controller(service)
        tuck.tuckAway()
        service.stored[.tileSize] = 30.0
        tuck.restore()
        #expect((service.stored[.tileSize] as? NSNumber)?.doubleValue == 30)
        #expect(service.stored[.autohide] == nil)
    }

    @Test("Quitting restores the Dock but keeps the switch on, and the next launch tucks it away again")
    func quitAndRelaunch() {
        let service = InMemorySystemDockPreferences([.tileSize: 45])
        let tuck = controller(service)
        tuck.tuckAway()
        tuck.restoreForTermination()
        #expect(service.stored[.tileSize] as? Int == 45)
        #expect(tuck.isOn)
        #expect(!tuck.isTucked)

        let relaunched = controller(service)
        relaunched.start()
        defer { relaunched.stop() }
        expectTucked(service)
        #expect(service.restartCount == 3)
    }

    @Test("A launch after a crash keeps the original snapshot and does not restart an already tucked Dock")
    func recoversFromCrash() {
        let service = InMemorySystemDockPreferences([.tileSize: 45])
        controller(service).tuckAway()

        let relaunched = controller(service)
        relaunched.start()
        defer { relaunched.stop() }
        #expect(service.restartCount == 1)
        relaunched.restore()
        #expect(service.stored[.tileSize] as? Int == 45)
    }

    @Test("A launch with the switch off finishes an interrupted restore")
    func finishesInterruptedRestore() {
        let service = InMemorySystemDockPreferences([.tileSize: 45])
        controller(service).tuckAway()
        var record = SystemDockTuckRepository(defaults: defaults).load()!
        record.isOn = false
        SystemDockTuckRepository(defaults: defaults).save(record)

        let relaunched = controller(service)
        relaunched.start()
        defer { relaunched.stop() }
        #expect(service.stored[.tileSize] as? Int == 45)
        #expect(!relaunched.isTucked)
    }

    @Test("The Dock goes right when DOKK's main dock sits on the left")
    func avoidsLeftEdge() {
        let service = InMemorySystemDockPreferences()
        let tuck = controller(service)
        tuck.mainDockEdge = .left
        tuck.tuckAway()
        expectTucked(service, "right")
    }

    @Test("Moving DOKK onto the left edge moves the Dock right once, and restore still deletes the key")
    func followsEdge() async throws {
        let service = InMemorySystemDockPreferences()
        let tuck = controller(service)
        tuck.start()
        defer { tuck.stop() }
        tuck.mainDockEdge = .bottom
        tuck.tuckAway()
        tuck.mainDockEdge = .left
        let follow = try #require(tuck.followTask)
        await follow.value
        expectTucked(service, "right")
        #expect(service.restartCount == 2)
        tuck.restore()
        #expect(service.stored[.orientation] == nil)
    }

    @Test("Following DOKK's edge leaves a position the person chose alone")
    func followRespectsPersonsChoice() async throws {
        let service = InMemorySystemDockPreferences()
        let tuck = controller(service)
        tuck.start()
        defer { tuck.stop() }
        tuck.tuckAway()
        service.stored[.orientation] = "bottom"
        tuck.mainDockEdge = .left
        let follow = try #require(tuck.followTask)
        await follow.value
        #expect(service.stored[.orientation] as? String == "bottom")
        #expect(service.restartCount == 1)
    }

    @Test("Managed Dock settings are refused without writing anything")
    func refusesManagedSettings() {
        let service = InMemorySystemDockPreferences([.tileSize: 45])
        service.managedKeys = [.autohide]
        let tuck = controller(service)
        tuck.tuckAway()
        #expect(tuck.failure == .managed)
        #expect(!tuck.isOn)
        #expect(!tuck.isTucked)
        #expect(service.stored[.tileSize] as? Int == 45)
        #expect(service.restartCount == 0)
    }

    @Test("A rejected write changes nothing, reports it, and keeps Restore available")
    func rejectedWrite() {
        let service = InMemorySystemDockPreferences([.tileSize: 45])
        service.synchronizeSucceeds = false
        let tuck = controller(service)
        tuck.tuckAway()
        #expect(tuck.failure == .write)
        #expect(!tuck.isOn)
        #expect(service.stored[.tileSize] as? Int == 45)
        #expect(service.restartCount == 0)

        service.synchronizeSucceeds = true
        tuck.restore()
        #expect(!tuck.isTucked)
        #expect(service.stored[.tileSize] as? Int == 45)
    }

    @Test("An unreadable record still offers a way back when the Dock carries DOKK's values")
    func unreadableRecord() {
        defaults.set(Data("not json".utf8), forKey: SystemDockTuckRepository.key)
        let service = InMemorySystemDockPreferences([.autohide: true, .autohideDelay: 10.0, .tileSize: 16, .orientation: "right"])
        let tuck = controller(service)
        #expect(tuck.tuckedOrientation == .right)
        tuck.restore()
        #expect(service.stored.isEmpty)
        #expect(service.restartCount == 1)
    }

    @Test("Values compare by meaning, not by stored type")
    func semanticComparison() {
        #expect(SystemDockValue.bool(true).matches(1))
        #expect(SystemDockValue.integer(16).matches(16.0))
        #expect(!SystemDockValue.number(10).matches(nil))
        #expect(!SystemDockValue.string("left").matches("bottom"))
    }
}

/// Each test gets its own preferences, so one test's record never leaks into another.
@MainActor
private func scratchDefaults() -> UserDefaults {
    let suite = "systemDockTuck.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
