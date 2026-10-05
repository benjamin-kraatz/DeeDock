import Foundation
import Sparkle
import Testing
@testable import DeeDock

struct AnalyticsVersionTests {
    @Test("Only dotted version numbers pass", arguments: ["0.13.5", "1", "1.0", "27.0.1.4"])
    func acceptsVersions(_ text: String) {
        #expect(AnalyticsVersion(text)?.text == text)
    }

    @Test("Anything else is dropped", arguments: ["", "0.14.0-beta", "1..2", ".1", "1.2.3.4.5", "v1.0",
                                                  "/Users/me/DOKK.app", "１.２"])
    func rejectsText(_ text: String) {
        #expect(AnalyticsVersion(text) == nil)
    }

    @Test("Builds are whole numbers")
    func builds() {
        #expect(AnalyticsVersion.build("46") == 46)
        #expect(AnalyticsVersion.build("46a") == nil)
        #expect(AnalyticsVersion.build(nil) == nil)
    }
}

@MainActor
struct UpdateAnalyticsTests {
    @Test("The first launch reports nothing; a later version reports a manual install")
    func manualInstallAcrossLaunches() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var events: [AnalyticsEvent] = []
        UpdateAnalytics(defaults: defaults, currentVersion: "0.13.4", currentBuild: "45", send: { events.append($0) })
            .reportLaunch()
        #expect(events.isEmpty)

        UpdateAnalytics(defaults: defaults, currentVersion: "0.13.4", currentBuild: "45", send: { events.append($0) })
            .reportLaunch()
        #expect(events.isEmpty)

        UpdateAnalytics(defaults: defaults, currentVersion: "0.13.5", currentBuild: "46", send: { events.append($0) })
            .reportLaunch()
        let record = try #require(events.only).record
        #expect(record.name == "update_installed")
        #expect(record.properties["path"] == AnalyticsValue(AnalyticsUpdateInstallPath.manual))
        #expect(record.properties["previous_version"] == AnalyticsValue(try #require(AnalyticsVersion("0.13.4"))))
        #expect(record.properties["previous_build"] == AnalyticsValue(45))
        #expect(record.properties["current_version"] == AnalyticsValue(try #require(AnalyticsVersion("0.13.5"))))
        #expect(record.properties["current_build"] == AnalyticsValue(46))
    }

    @Test("An install started before quitting is confirmed by a new build and failed by the same one",
          arguments: [true, false])
    func pendingInstallOutcome(completed: Bool) throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let started = Date(timeIntervalSinceReferenceDate: 1_000)
        UpdateLaunchRecord(version: "0.13.4", build: "45").save(to: defaults)
        UpdatePendingInstallRecord(fromVersion: "0.13.4", fromBuild: "45", offerVersion: "0.13.5", offerBuild: "46",
                                   path: AnalyticsUpdateInstallPath.idle.rawValue, startedAt: started)
            .save(to: defaults)
        var events: [AnalyticsEvent] = []
        let analytics = UpdateAnalytics(defaults: defaults, currentVersion: completed ? "0.13.5" : "0.13.4",
                                        currentBuild: completed ? "46" : "45",
                                        now: { started.addingTimeInterval(30) }, send: { events.append($0) })
        analytics.reportLaunch()

        let record = try #require(events.only).record
        #expect(record.name == (completed ? "update_installed" : "update_install_failed"))
        #expect(record.properties["path"] == AnalyticsValue(AnalyticsUpdateInstallPath.idle))
        #expect(record.properties["offer_version"] == AnalyticsValue(try #require(AnalyticsVersion("0.13.5"))))
        #expect(record.properties["offer_build"] == AnalyticsValue(46))
        #expect(record.properties["duration"] == AnalyticsValue(30.0))
        #expect(UpdatePendingInstallRecord.load(from: defaults) == nil)

        // The record is read once.
        events.removeAll()
        UpdateAnalytics(defaults: defaults, currentVersion: completed ? "0.13.5" : "0.13.4",
                        currentBuild: completed ? "46" : "45", send: { events.append($0) })
            .reportLaunch()
        #expect(events.isEmpty)
    }

    @Test("Every update event carries versions, update settings, and the phase")
    func factsOnEveryEvent() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var events: [AnalyticsEvent] = []
        let analytics = UpdateAnalytics(defaults: defaults, currentVersion: "0.13.5", currentBuild: "46",
            send: { events.append($0) })
        analytics.snapshot = {
            UpdateAnalytics.Snapshot(checksAutomatically: true, installsAutomatically: false, installsWhenIdle: true,
                                     automaticInstallAllowed: true, phase: .available)
        }
        analytics.opened(.dockTile, target: .currentSession)

        let record = try #require(events.only).record
        #expect(record.name == "update_opened")
        #expect(record.properties["source"] == AnalyticsValue(AnalyticsUpdateSource.dockTile))
        #expect(record.properties["target"] == AnalyticsValue(AnalyticsUpdateOpenTarget.currentSession))
        #expect(record.properties["phase"] == AnalyticsValue(UpdatePhase.available))
        #expect(record.properties["current_version"] == AnalyticsValue(try #require(AnalyticsVersion("0.13.5"))))
        #expect(record.properties["updates_check_automatically"] == AnalyticsValue(true))
        #expect(record.properties["updates_install_automatically"] == AnalyticsValue(false))
        #expect(record.properties["updates_install_when_idle"] == AnalyticsValue(true))
        #expect(record.properties["updates_automatic_install_allowed"] == AnalyticsValue(true))
    }

    @Test("Install on Quit at the ready step is reported at termination and checked on the next launch")
    func installOnQuit() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var events: [AnalyticsEvent] = []
        var phase = UpdatePhase.ready
        let analytics = UpdateAnalytics(defaults: defaults, currentVersion: "0.13.4", currentBuild: "45",
            send: { events.append($0) })
        analytics.snapshot = { UpdateAnalytics.Snapshot(phase: phase) }
        analytics.checkStarted(.updates)
        analytics.offerShown(SUAppcastItem.empty(), stage: .notDownloaded, userInitiated: true)
        analytics.action(.later, via: .button)
        phase = .idle
        analytics.reportTermination()

        let record = try #require(events.last).record
        #expect(record.name == "update_install_started")
        #expect(record.properties["path"] == AnalyticsValue(AnalyticsUpdateInstallPath.onQuit))
        #expect(record.properties["silent"] == AnalyticsValue(false))
        #expect(UpdatePendingInstallRecord.load(from: defaults)?.path == AnalyticsUpdateInstallPath.onQuit.rawValue)
    }

    @Test("Quitting without a real offer, as in the debug simulation, reports no install")
    func noInstallWithoutOffer() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var events: [AnalyticsEvent] = []
        let analytics = UpdateAnalytics(defaults: defaults, currentVersion: "0.13.4", currentBuild: "45",
            send: { events.append($0) })
        analytics.snapshot = { UpdateAnalytics.Snapshot(phase: .ready, staged: true) }
        analytics.reportTermination()
        #expect(events.isEmpty)
        #expect(UpdatePendingInstallRecord.load(from: defaults) == nil)
    }

    @Test("Errors are reduced to codes and \"no update\" is not a failure")
    func errorsAsCodes() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var events: [AnalyticsEvent] = []
        let analytics = UpdateAnalytics(defaults: defaults, currentVersion: "0.13.4", currentBuild: "45",
            send: { events.append($0) })
        analytics.aborted(NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue)))
        #expect(events.isEmpty)

        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        analytics.aborted(NSError(domain: SUSparkleErrorDomain, code: Int(SUError.downloadError.rawValue),
                                  userInfo: [NSUnderlyingErrorKey: underlying,
                                             NSLocalizedDescriptionKey: "/Users/me/secret"]))
        let record = try #require(events.only).record
        #expect(record.name == "update_failed")
        #expect(record.properties["error_code"] == AnalyticsValue(Int(SUError.downloadError.rawValue)))
        #expect(record.properties["error_domain"] == AnalyticsValue(AnalyticsErrorDomain.sparkle))
        #expect(record.properties["underlying_error_code"] == AnalyticsValue(NSURLErrorTimedOut))
        #expect(record.properties["underlying_error_domain"] == AnalyticsValue(AnalyticsErrorDomain.url))
        #expect(!record.properties.payload.values.contains { ($0 as? String)?.contains("secret") == true })
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "DeeDockUpdateAnalyticsTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }
}

private extension Array {
    /// The single element, or nil when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
