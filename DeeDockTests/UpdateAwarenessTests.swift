import Foundation
import Testing
@testable import DeeDock

@MainActor
struct UpdateAwarenessTests {
    @Test("Idle install preference defaults on and an opt-out persists")
    func idleInstallDefaultsOn() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateAwarenessStore(defaults: defaults)
        #expect(store.installWhenIdle == true)
        store.setInstallWhenIdle(false)
        #expect(store.installWhenIdle == false)
        #expect(defaults.bool(forKey: UpdateAwarenessStore.idleInstallKey) == false)
        #expect(UpdateAwarenessStore(defaults: defaults).installWhenIdle == false)
        store.setInstallWhenIdle(true)
        #expect(UpdateAwarenessStore(defaults: defaults).installWhenIdle == true)
    }

    @Test("A staged offer shows marks at once and its callout only after the patience period")
    func stagedOfferHoldsCallout() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateAwarenessStore(defaults: defaults)
        let staged = Date(timeIntervalSinceReferenceDate: 1_000)
        store.noteStagedOffer(identity: "42", version: "0.14.0", now: staged)
        #expect(store.showsIndicators)
        #expect(store.showsDockPip)
        #expect(!store.showsCallout(now: staged.addingTimeInterval(UpdateAwarenessStore.calloutPatience - 1)))
        #expect(store.showsCallout(now: staged.addingTimeInterval(UpdateAwarenessStore.calloutPatience)))
        // A repeated report of the same offer must not restart the wait.
        store.noteStagedOffer(identity: "42", version: "0.14.0", now: staged.addingTimeInterval(60))
        #expect(store.showsCallout(now: staged.addingTimeInterval(UpdateAwarenessStore.calloutPatience)))
    }

    @Test("A staged offer calls out at once when idle install is off")
    func stagedOfferWithoutIdleInstall() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateAwarenessStore(defaults: defaults)
        store.setInstallWhenIdle(false)
        let staged = Date(timeIntervalSinceReferenceDate: 1_000)
        store.noteStagedOffer(identity: "42", version: "0.14.0", now: staged)
        #expect(store.showsCallout(now: staged))
    }

    @Test("An offer that needs the user calls out at once")
    func waitingOfferCallsOut() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateAwarenessStore(defaults: defaults)
        store.noteWaitingOffer(identity: "42", version: "0.14.0", userInitiated: false)
        #expect(store.showsCallout())
    }

    @Test("A completed automatic install is announced until acknowledged")
    func installedNoticeLifecycle() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        UpdateAwarenessStore(defaults: defaults, currentVersion: "0.13.0", currentBuild: "41")
            .recordAutomaticInstall()

        let relaunched = UpdateAwarenessStore(defaults: defaults, currentVersion: "0.14.0", currentBuild: "42")
        #expect(relaunched.installedFromVersion == "0.13.0")
        #expect(relaunched.showsInstalledCallout)
        #expect(relaunched.showsMenuBadge)
        #expect(relaunched.showsDockPip)

        // Dismissing the callout keeps the menu notice, also across another launch.
        relaunched.noteInstalledCalloutSeen()
        #expect(!relaunched.showsDockPip)
        #expect(relaunched.showsMenuBadge)
        let again = UpdateAwarenessStore(defaults: defaults, currentVersion: "0.14.0", currentBuild: "42")
        #expect(again.installedFromVersion == "0.13.0")
        #expect(!again.showsInstalledCallout)

        again.acknowledgeInstalled()
        #expect(!again.showsMenuBadge)
        #expect(UpdateAwarenessStore(defaults: defaults, currentVersion: "0.14.0", currentBuild: "42")
            .installedFromVersion == nil)
    }

    @Test("An automatic install that did not replace the build is not announced")
    func failedInstallIsDiscarded() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        UpdateAwarenessStore(defaults: defaults, currentVersion: "0.13.0", currentBuild: "41")
            .recordAutomaticInstall()
        let sameBuild = UpdateAwarenessStore(defaults: defaults, currentVersion: "0.13.0", currentBuild: "41")
        #expect(sameBuild.installedFromVersion == nil)
        #expect(UpdateInstallRecord.load(from: defaults) == nil)
    }

    @Test("A newer offer replaces the installed notice")
    func newOfferClearsInstalledNotice() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        UpdateAwarenessStore(defaults: defaults, currentVersion: "0.13.0", currentBuild: "41")
            .recordAutomaticInstall()
        let store = UpdateAwarenessStore(defaults: defaults, currentVersion: "0.14.0", currentBuild: "42")
        store.noteStagedOffer(identity: "43", version: "0.14.1")
        #expect(store.installedFromVersion == nil)
        #expect(UpdateInstallRecord.load(from: defaults) == nil)
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
        store.setInstallWhenIdle(false)
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
        var gate = UpdateIdleGate(secondsSinceDockUse: UpdateIdleGate.idleThreshold)
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

    @Test("Idle requires the dock to go unused for the threshold")
    func inputThreshold() {
        var gate = UpdateIdleGate(secondsSinceDockUse: UpdateIdleGate.idleThreshold - 1)
        #expect(!gate.isIdle)
        gate.secondsSinceDockUse = UpdateIdleGate.idleThreshold
        #expect(gate.isIdle)
    }

    @Test("File picker, popover, menu tracking, and Window Peek are busy")
    func extraBusyGates() {
        #expect(UpdateIdleGate(isFilePickerActive: true, secondsSinceDockUse: UpdateIdleGate.idleThreshold).isBusy)
        #expect(UpdateIdleGate(isPopoverOpen: true, secondsSinceDockUse: UpdateIdleGate.idleThreshold).isBusy)
        #expect(UpdateIdleGate(isMenuTracking: true, secondsSinceDockUse: UpdateIdleGate.idleThreshold).isBusy)
        #expect(UpdateIdleGate(isWindowPeekOpen: true, secondsSinceDockUse: UpdateIdleGate.idleThreshold).isBusy)
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
            UpdateIdleGate(secondsSinceDockUse: UpdateIdleGate.idleThreshold)
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
            UpdateIdleGate(isDragging: true, secondsSinceDockUse: UpdateIdleGate.idleThreshold)
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

struct UpdateInstalledNotesTests {
    @Test("Only versions after the previous one and up to the current one are listed, newest first")
    func versionRange() {
        let names = ["0.9.3", "0.10.0", "0.10.0-comic", "0.11.2", "0.12.0", "0.13.0", "0.14.0", "COMIC-README"]
        #expect(UpdateInstalledNotes.versions(in: names, after: "0.9.3", through: "0.13.0")
            == ["0.13.0", "0.12.0", "0.11.2", "0.10.0"])
        #expect(UpdateInstalledNotes.versions(in: names, after: "0.13.0", through: "0.13.0").isEmpty)
    }

    @Test("A long absence is capped at the newest versions")
    func versionCap() {
        let names = (1...20).map { "0.\($0).0" }
        let versions = UpdateInstalledNotes.versions(in: names, after: "0.0.1", through: "0.20.0")
        #expect(versions.count == UpdateInstalledNotes.maximumVersions)
        #expect(versions.first == "0.20.0")
    }

    @Test("Bilingual notes split at the English marker")
    func localizedHalves() {
        let text = "DOKK 1.0.\n\n## Neue Funktionen\n\n- Eins\n\n## English\n\nDOKK 1.0.\n\n### New\n\n- One"
        #expect(UpdateInstalledNotes.localized(text, german: true) == "DOKK 1.0.\n\n## Neue Funktionen\n\n- Eins")
        #expect(UpdateInstalledNotes.localized(text, german: false) == "DOKK 1.0.\n\n### New\n\n- One")
        #expect(UpdateInstalledNotes.localized("Only one language.", german: false) == "Only one language.")
    }

    @Test("The releases index yields published versions only")
    func publishedVersions() throws {
        let index = Data("""
        [{"tag_name":"v0.13.0","draft":false,"prerelease":false},
         {"tag_name":"v0.12.1-beta","draft":false,"prerelease":true},
         {"tag_name":"v0.12.0","draft":true,"prerelease":false},
         {"tag_name":"v0.11.2"},
         {"tag_name":"nightly"}]
        """.utf8)
        #expect(UpdateInstalledNotes.publishedVersions(inIndex: index) == ["0.13.0", "0.11.2"])
        #expect(UpdateInstalledNotes.publishedVersions(inIndex: Data("not json".utf8)).isEmpty)
    }

    @Test("Notes and index URLs stay on the allowlist")
    func notesURLs() throws {
        let notes = try #require(UpdateComicResourcePolicy.notesURL(version: "0.13.0"))
        #expect(notes.absoluteString == "https://github.com/benjamin-kraatz/DeeDock/releases/download/v0.13.0/DDock.md")
        #expect(UpdateComicResourcePolicy.allowsInitial(notes))
        #expect(UpdateComicResourcePolicy.notesURL(version: "../evil") == nil)
        let index = try #require(UpdateComicResourcePolicy.releasesIndexURL)
        #expect(UpdateComicResourcePolicy.allowsInitial(index))
        #expect(!UpdateComicResourcePolicy.allowsInitial(try #require(URL(string: "https://api.github.com/repos/other/repo/releases"))))
    }
}
