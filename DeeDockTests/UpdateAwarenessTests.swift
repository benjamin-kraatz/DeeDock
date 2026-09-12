import Foundation
import Testing
@testable import DeeDock

@MainActor
struct UpdateAwarenessTests {
    @Test("Idle install preference defaults off and persists")
    func idleInstallDefaultsOff() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateAwarenessStore(defaults: defaults)
        #expect(store.installWhenIdle == false)
        store.setInstallWhenIdle(true)
        #expect(store.installWhenIdle == true)
        #expect(defaults.bool(forKey: UpdateAwarenessStore.idleInstallKey) == true)
        #expect(UpdateAwarenessStore(defaults: defaults).installWhenIdle == true)
        store.setInstallWhenIdle(false)
        #expect(UpdateAwarenessStore(defaults: defaults).installWhenIdle == false)
    }

    @Test("Scheduled discovery shows indicators until dismiss")
    func scheduledOfferShowsThenQuiets() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateAwarenessStore(defaults: defaults)
        store.noteWaitingOffer(identity: "0.6.0", version: "0.6.0", userInitiated: false)
        #expect(store.showsIndicators)
        store.dismiss()
        #expect(!store.showsIndicators)
        store.noteWaitingOffer(identity: "0.6.0", version: "0.6.0", userInitiated: false)
        #expect(!store.showsIndicators)
    }

    @Test("Opening the Update window clears indicators for this offer")
    func openingWindowClearsIndicators() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateAwarenessStore(defaults: defaults)
        store.noteWaitingOffer(identity: "0.6.0", version: "0.6.0", userInitiated: false)
        store.noteWindowOpened()
        #expect(!store.showsIndicators)
        #expect(store.windowIsOpen)
        store.noteWindowClosed()
        store.noteWaitingOffer(identity: "0.6.0", version: "0.6.0", userInitiated: false)
        #expect(!store.showsIndicators)
    }

    @Test("A user-initiated check does not badge")
    func userInitiatedDoesNotBadge() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateAwarenessStore(defaults: defaults)
        store.noteWaitingOffer(identity: "0.6.0", version: "0.6.0", userInitiated: true)
        #expect(!store.showsIndicators)
    }

    @Test("A later offer identity can show indicators again")
    func newOfferReappears() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateAwarenessStore(defaults: defaults)
        store.noteWaitingOffer(identity: "0.6.0", version: "0.6.0", userInitiated: false)
        store.dismiss()
        store.noteWaitingOffer(identity: "0.6.1", version: "0.6.1", userInitiated: false)
        #expect(store.showsIndicators)
        #expect(store.offerVersion == "0.6.1")
    }

    @Test("Install or skip clears the waiting offer")
    func sessionEndClearsOffer() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateAwarenessStore(defaults: defaults)
        store.noteWaitingOffer(identity: "0.6.0", version: "0.6.0", userInitiated: false)
        store.noteSessionEnded()
        #expect(!store.showsIndicators)
        #expect(store.offerIdentity == nil)
        #expect(!store.canAttemptIdleInstall)
    }

    @Test("Idle install is a single attempt after the preference is on")
    func idleInstallIsOneShot() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateAwarenessStore(defaults: defaults)
        store.noteWaitingOffer(identity: "0.6.0", version: "0.6.0", userInitiated: false)
        #expect(!store.canAttemptIdleInstall)
        store.setInstallWhenIdle(true)
        #expect(store.canAttemptIdleInstall)
        store.noteWindowOpened()
        #expect(!store.canAttemptIdleInstall)
        store.noteWindowClosed()
        #expect(store.canAttemptIdleInstall)
        store.markIdleInstallAttempted()
        #expect(!store.canAttemptIdleInstall)
    }

    @Test("A new process can discover the same offer again")
    func coldDiscoveryShowsAgain() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UpdateAwarenessStore(defaults: defaults)
        first.noteWaitingOffer(identity: "0.6.0", version: "0.6.0", userInitiated: false)
        first.dismiss()
        let second = UpdateAwarenessStore(defaults: defaults)
        second.noteWaitingOffer(identity: "0.6.0", version: "0.6.0", userInitiated: false)
        #expect(second.showsIndicators)
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "DeeDockUpdateAwarenessTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }
}

struct UpdateIdleGateTests {
    @Test("Busy gates block idle even with a long quiet period")
    func busyBlocksIdle() {
        var gate = UpdateIdleGate(secondsSinceInput: 120)
        #expect(gate.isIdle)
        gate.isDragging = true
        #expect(gate.isBusy)
        #expect(!gate.isIdle)
        gate.isDragging = false
        gate.isFocusSessionPanelOpen = true
        #expect(!gate.isIdle)
        gate.isFocusSessionPanelOpen = false
        gate.isUpdateWindowOpen = true
        #expect(!gate.isIdle)
    }

    @Test("Idle requires the input quiet period")
    func inputThreshold() {
        var gate = UpdateIdleGate(secondsSinceInput: UpdateIdleGate.idleInputThreshold - 1)
        #expect(!gate.isIdle)
        gate.secondsSinceInput = UpdateIdleGate.idleInputThreshold
        #expect(gate.isIdle)
    }

    @Test("File picker, popover, and menu tracking are busy")
    func extraBusyGates() {
        #expect(UpdateIdleGate(isFilePickerActive: true, secondsSinceInput: 120).isBusy)
        #expect(UpdateIdleGate(isPopoverOpen: true, secondsSinceInput: 120).isBusy)
        #expect(UpdateIdleGate(isMenuTracking: true, secondsSinceInput: 120).isBusy)
    }
}

@MainActor
struct UpdateIdleInstallControllerTests {
    @Test("Installs once when idle and ready")
    func installsOnceWhenIdle() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let awareness = UpdateAwarenessStore(defaults: defaults)
        awareness.setInstallWhenIdle(true)
        awareness.noteWaitingOffer(identity: "0.6.0", version: "0.6.0", userInitiated: false)
        let controller = UpdateIdleInstallController(awareness: awareness)
        var installs = 0
        controller.isReadyToInstall = { true }
        controller.gateSnapshot = {
            UpdateIdleGate(secondsSinceInput: UpdateIdleGate.idleInputThreshold)
        }
        controller.install = { installs += 1 }
        controller.tick()
        controller.tick()
        #expect(installs == 1)
        #expect(awareness.idleInstallAttempted)
    }

    @Test("Does not install while a busy gate is set")
    func skipsWhenBusy() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let awareness = UpdateAwarenessStore(defaults: defaults)
        awareness.setInstallWhenIdle(true)
        awareness.noteWaitingOffer(identity: "0.6.0", version: "0.6.0", userInitiated: false)
        let controller = UpdateIdleInstallController(awareness: awareness)
        var installs = 0
        controller.isReadyToInstall = { true }
        controller.gateSnapshot = {
            UpdateIdleGate(isDragging: true, secondsSinceInput: UpdateIdleGate.idleInputThreshold)
        }
        controller.install = { installs += 1 }
        controller.tick()
        #expect(installs == 0)
        #expect(!awareness.idleInstallAttempted)
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "DeeDockUpdateIdleInstallTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }
}
