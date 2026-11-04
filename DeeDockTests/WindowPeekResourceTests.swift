import Foundation
import Testing
@testable import DeeDock

@MainActor
struct WindowPeekResourceTests {
    @Test("The readout stays off for existing settings, and a preset does not change it")
    func settingsMigration() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var settings = DockSettings.defaults
        #expect(!settings.windowPeekResourcesEnabled)
        settings.windowPeekResourcesEnabled = true
        let data = try encoder.encode(settings)
        #expect(try decoder.decode(DockSettings.self, from: data).windowPeekResourcesEnabled)
        #expect(DockSettingsOverrides().resolving(settings).windowPeekResourcesEnabled)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "windowPeekResourcesEnabled")
        let migrated = try decoder.decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(!migrated.windowPeekResourcesEnabled)
        #expect(!DockSettingsOverrides().resolving(migrated).windowPeekResourcesEnabled)
        for preset in WindowPeekPreset.allCases {
            var candidate = settings
            preset.apply(to: &candidate)
            #expect(candidate.windowPeekResourcesEnabled)
        }
    }

    @Test("CPU waits for an interval, and the total includes helpers")
    func reading() {
        var usage = AppHealthAppUsage()
        usage.add(AppHealthProcessCounters(cpuSeconds: 0.2, idleWakeups: 0, energy: 0),
                  footprint: 1_000, reportsEnergy: false, isMain: true)
        usage.add(AppHealthProcessCounters(cpuSeconds: 0.3, idleWakeups: 0, energy: 0),
                  footprint: 2_000, reportsEnergy: false, isMain: false)
        let waiting = WindowPeekResourceReading(usage: usage, interval: nil)
        #expect(waiting?.cpuPercent == nil)
        #expect(waiting?.memoryBytes == 3_000)
        #expect(WindowPeekResourceReading(usage: usage, interval: 0) == waiting)
        let live = WindowPeekResourceReading(usage: usage, interval: 1)
        #expect(live?.cpuPercent == 50)
        #expect(live?.memoryBytes == 3_000)
        #expect(WindowPeekResourceReading(usage: AppHealthAppUsage(), interval: 1) == nil)
    }

    @Test("VoiceOver names CPU only once a rate exists, and network only with a throughput")
    func spoken() {
        let english = Locale(identifier: "en_US")
        let waiting = WindowPeekResourceReading(cpuPercent: nil, memoryBytes: 1_500_000)
        let live = WindowPeekResourceReading(cpuPercent: 140, memoryBytes: 1_500_000)
        #expect(!WindowPeekResourceText.spoken(waiting, locale: english).contains("CPU"))
        let text = WindowPeekResourceText.spoken(live, locale: english)
        #expect(text.contains("CPU"))
        #expect(text.contains(WindowPeekResourceText.percent(140, locale: english)))
        #expect(!text.contains("per second"))
        let withNetwork = WindowPeekResourceReading(
            cpuPercent: 140, memoryBytes: 1_500_000,
            network: WindowPeekNetworkRate(receivedPerSecond: 2_000, sentPerSecond: 400))
        let networkText = WindowPeekResourceText.spoken(withNetwork, locale: english)
        #expect(networkText.contains("per second"))
        #expect(networkText.contains(WindowPeekResourceText.amount(2_000, locale: english)))
        #expect(networkText.contains(WindowPeekResourceText.amount(400, locale: english)))
    }

    @Test("Rates never fall below kilobytes, so a trickle does not spell out bytes")
    func amount() {
        let english = Locale(identifier: "en_US")
        #expect(WindowPeekResourceText.amount(0, locale: english) == "0 kB")
        #expect(WindowPeekResourceText.amount(152, locale: english) == "< 1 kB")
        #expect(WindowPeekResourceText.amount(28_400, locale: english) == "28 kB")
        #expect(!WindowPeekResourceText.rate(286, locale: Locale(identifier: "de_DE")).contains("Byte"))
    }

    @Test("A network rate is the difference over the interval, and a backwards counter is not a rate")
    func networkRate() {
        let previous = WindowPeekNetworkTotals(received: 1_000, sent: 200)
        let current = WindowPeekNetworkTotals(received: 3_000, sent: 200)
        let rate = WindowPeekNetworkRate.make(current: current, previous: previous, interval: 2)
        #expect(rate?.receivedPerSecond == 1_000)
        #expect(rate?.sentPerSecond == 0)
        #expect(WindowPeekNetworkRate.make(current: previous, previous: current, interval: 2) == nil)
        #expect(WindowPeekNetworkRate.make(current: current, previous: previous, interval: 0) == nil)
    }

    @Test("A description without counts is not a baseline, so earlier traffic is not one interval")
    func networkBaseline() {
        var ledger = WindowPeekNetworkLedger()
        let pid: pid_t = 42
        ledger.describe(key: 1, pid: pid)
        #expect(ledger.take(matching: [pid]) == WindowPeekNetworkTotals(received: 0, sent: 0))
        ledger.counts(key: 1, pid: pid, received: 5_000_000, sent: 1_000_000)
        #expect(ledger.take(matching: [pid]) == WindowPeekNetworkTotals(received: 0, sent: 0))
        ledger.counts(key: 1, pid: nil, received: 5_000_100, sent: 1_000_040)
        #expect(ledger.take(matching: [pid]) == WindowPeekNetworkTotals(received: 100, sent: 40))

        var early = WindowPeekNetworkLedger()
        early.describe(key: 7, pid: pid)
        early.counts(key: 7, pid: pid, received: 5_000_000, sent: 0)
        early.counts(key: 7, pid: pid, received: 5_000_200, sent: 10)
        #expect(early.take(matching: [pid]) == WindowPeekNetworkTotals(received: 200, sent: 10))
        early.counts(key: 7, pid: pid, received: 5_000_150, sent: 10)
        #expect(early.take(matching: [pid]) == WindowPeekNetworkTotals(received: 0, sent: 0))

        var closed = WindowPeekNetworkLedger()
        closed.describe(key: 3, pid: pid)
        closed.remove(key: 3)
        #expect(closed.take(matching: [pid]) == WindowPeekNetworkTotals(received: 0, sent: 0))
        closed.counts(key: 9, pid: pid, received: 1_000, sent: 0)
        closed.counts(key: 9, pid: pid, received: 1_250, sent: 5)
        closed.remove(key: 9)
        #expect(closed.take(matching: [pid]) == WindowPeekNetworkTotals(received: 250, sent: 5))
        #expect(closed.take(matching: [99]) == WindowPeekNetworkTotals(received: 0, sent: 0))
    }
}
