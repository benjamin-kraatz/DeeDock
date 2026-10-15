import Foundation
import Testing
@testable import DeeDock

/// Which of the index service's requests a pass takes, and which wait (`IndexRequests`).
struct LookoutIndexRequestsTests {
    private let configuration = LookoutIndexConfiguration(roots: ["/Users/tester/Documents"], modelsFolder: "/m",
                                                          indexFolder: "/i", backfillAllowed: true)

    @Test func aSyncAndAResetWhilePausedWaitForTheResume() {
        var requests = IndexRequests()
        requests.paused = true
        (requests.sync, requests.reset) = (true, true)
        let held = requests.take()
        #expect(held.isHeld && held.paused && !held.sync && !held.reset)
        #expect(requests.sync && requests.reset, "still waiting")
        #expect(requests.take().isHeld, "a second held pass keeps them too")

        requests.resume()
        let pass = requests.take()
        #expect(!pass.isHeld && pass.sync && pass.reset)
        let next = requests.take()
        #expect(!next.sync && !next.reset && next.configuration == nil, "performed once")
    }

    @Test func aConfigurationWhilePausedIsAppliedAndItsSyncWaits() {
        var requests = IndexRequests()
        requests.paused = true
        requests.configuration = configuration
        let held = requests.take()
        #expect(held.isHeld && held.configuration == configuration)
        #expect(requests.configuration == nil && requests.sync)
    }

    @Test func resumingAlwaysCrawls() {
        var requests = IndexRequests()
        requests.paused = true
        _ = requests.take()
        requests.resume()
        #expect(requests.take().sync)
    }

    @Test func requestsWaitWhileNoAppIsConnected() {
        var requests = IndexRequests()
        requests.appAway = true
        requests.sync = true
        let held = requests.take()
        #expect(held.isHeld && !held.paused && !held.sync)
        requests.appAway = false
        #expect(requests.take().sync)
    }

    @Test func closingTheIndexDropsWhatWasAskedBefore() {
        var requests = IndexRequests()
        requests.configuration = configuration
        (requests.sync, requests.reset) = (true, true)
        requests.dropWork()
        let pass = requests.take()
        #expect(pass.configuration == nil && !pass.sync && !pass.reset)
    }
}
