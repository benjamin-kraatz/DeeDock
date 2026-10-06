import Testing
@testable import DeeDock

struct ApplicationUpdateLaunchTests {
    private let previous = ApplicationUpdateLaunch.Snapshot(version: "0.13.4", build: "45")

    @Test("The first install sends nothing")
    func firstInstall() {
        let change = ApplicationUpdateLaunch.change(
            from: nil, to: previous, analyticsEnabled: true, channel: .direct)
        #expect(change == nil)
    }

    @Test("The same version and build sends nothing")
    func sameVersion() {
        let change = ApplicationUpdateLaunch.change(
            from: previous, to: previous, analyticsEnabled: true, channel: .direct)
        #expect(change == nil)
    }

    @Test("A version bump reports both versions")
    func versionBump() {
        let current = ApplicationUpdateLaunch.Snapshot(version: "0.13.5", build: "46")
        let change = ApplicationUpdateLaunch.change(
            from: previous, to: current, analyticsEnabled: true, updateSource: .automatic, channel: .direct)
        #expect(change == ApplicationUpdateLaunch.Change(
            previous: previous, current: current, updateSource: .automatic, channel: .direct))
    }

    @Test("A build-only bump still reports the update")
    func buildOnly() {
        let current = ApplicationUpdateLaunch.Snapshot(version: "0.13.4", build: "46")
        let change = ApplicationUpdateLaunch.change(
            from: previous, to: current, analyticsEnabled: true, channel: .direct)
        #expect(change?.previous.version == "0.13.4")
        #expect(change?.current.version == "0.13.4")
        #expect(change?.previous.build == "45")
        #expect(change?.current.build == "46")
        #expect(change?.updateSource == nil)
    }

    @Test("Opting out sends nothing even when the version changed")
    func optedOut() {
        let current = ApplicationUpdateLaunch.Snapshot(version: "0.13.5", build: "46")
        let change = ApplicationUpdateLaunch.change(
            from: previous, to: current, analyticsEnabled: false, updateSource: .manual, channel: .direct)
        #expect(change == nil)
    }

    @Test("Only a user or background check has an update source")
    func updateSource() {
        #expect(ApplicationUpdateSource(.user) == .manual)
        #expect(ApplicationUpdateSource(.background) == .automatic)
        #expect(ApplicationUpdateSource(.information) == nil)
    }
}
