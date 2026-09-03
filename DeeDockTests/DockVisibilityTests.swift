import Foundation
import Testing

@MainActor struct DockVisibilityTests {
    private var settings: DockBehaviorSettings {
        var settings = DockBehaviorSettings(); settings.autoHide = true; return settings
    }

    @Test("Continuous dwell reveals once; exit cancels even an already-expired undelivered deadline")
    func dwell() {
        var state = DockVisibilityState(settings: settings)
        state.update(activation: true, retained: true, held: false, now: 0)
        state.update(activation: true, retained: true, held: false, now: 0.08)
        #expect(state.nextUpdate(after: 0.08) == 0.10)
        state.update(activation: false, retained: false, held: false, now: 0.11)
        #expect(state.phase == .hidden)
        #expect(state.nextUpdate(after: 0.11) == nil)
    }

    @Test("Independent panels cancel hiding on re-entry and hold for deliberate interaction")
    func independentHolds() {
        let clock = ManualDockScheduler()
        let first = DockVisibilityController(settings: settings, scheduler: clock)
        let second = DockVisibilityController(settings: settings, scheduler: clock)
        first.update(activation: true, retained: true, held: false)
        clock.advance(to: 0.4)
        #expect(first.progress == 0)
        #expect(second.progress == 1)
        first.update(activation: false, retained: false, held: false)
        #expect(first.phase == .hideDelay)
        clock.advance(to: 0.6)
        first.update(activation: false, retained: true, held: false)
        clock.advance(to: 1)
        #expect(first.phase == .visible)
        first.update(activation: false, retained: false, held: true)
        clock.advance(to: 2)
        #expect(first.progress == 0)
        first.update(activation: false, retained: false, held: false)
        clock.advance(to: 3)
        #expect(first.progress == 1)
        #expect(clock.pendingCount == 0)
        first.stop(); second.stop()
    }

    @Test("Returning during hiding reverses from current progress without a visual jump")
    func reversal() {
        var state = DockVisibilityState(settings: settings)
        state.showImmediately()
        state.update(activation: false, retained: false, held: false, now: 0)
        state.advance(now: 0.4)
        let before = state.progress(at: 0.5)
        #expect(before > 0 && before < 1)
        state.update(activation: false, retained: true, held: false, now: 0.5)
        #expect(state.progress(at: 0.5) == before)
        #expect(state.phase == .revealing)
        state.advance(now: 0.7)
        #expect(state.progress(at: 0.7) == 0)
    }

    @Test("Explicit focus reveals immediately; error holds reveal without the dwell delay")
    func forcedVisibility() {
        let clock = ManualDockScheduler()
        let controller = DockVisibilityController(settings: settings, scheduler: clock)
        #expect(!controller.exposesContent)
        controller.showImmediately()
        #expect(controller.exposesContent)
        #expect(controller.progress == 0)
        controller.update(activation: false, retained: false, held: true)
        clock.advance(to: 1)
        #expect(controller.phase == .visible)
        controller.update(activation: false, retained: false, held: false)
        clock.advance(to: 2)
        #expect(controller.phase == .hidden)
        #expect(!controller.exposesContent)
        controller.update(activation: false, retained: false, held: true)
        #expect(controller.phase == .revealing)
        clock.advance(to: 2.3)
        #expect(controller.progress == 0)
        controller.stop()
    }

    @Test("Zero duration and Reduce Motion settle without ongoing animation work")
    func accessibleTiming() {
        var instant = settings; instant.animationDuration = 0; instant.revealDelay = 0
        var state = DockVisibilityState(settings: instant)
        state.update(activation: true, retained: true, held: false, now: 0)
        #expect(state.progress(at: 0) == 0)
        #expect(state.nextUpdate(after: 0) == nil)
        let clock = ManualDockScheduler()
        let reduced = DockVisibilityController(settings: settings, reduceMotion: true, scheduler: clock)
        reduced.update(activation: false, retained: false, held: true)
        clock.advance(to: 0.11)
        #expect(reduced.progress == 0)
        #expect(clock.pendingCount == 0)
        reduced.stop()
    }

    @Test("Teardown and geometry changes invalidate old deadlines and resample the pointer")
    func staleCallbacks() throws {
        let clock = ManualDockScheduler()
        let controller = DockVisibilityController(settings: settings, scheduler: clock)
        controller.update(activation: true, retained: true, held: false)
        let first = try #require(clock.lastID)
        controller.configure(settings, reduceMotion: false, geometryChanged: true)
        clock.deliverStale(first)
        #expect(controller.progress == 1)
        controller.update(activation: true, retained: true, held: false)
        controller.refreshInput = { [weak controller] in controller?.update(activation: false, retained: false, held: false) }
        clock.advance(to: 0.2)
        #expect(controller.progress == 1)
        controller.update(activation: true, retained: true, held: false)
        let last = try #require(clock.lastID)
        controller.stop(); clock.deliverStale(last)
        #expect(controller.phase == .hidden)
        #expect(clock.pendingCount == 0)
    }

    @Test("Preview expiration, replacement, and explicit close release only the matching lease")
    func previewLifetime() throws {
        let clock = ManualDockScheduler()
        let lease = DockPreviewLease(scheduler: clock)
        var ends = 0
        lease.didEnd = { ends += 1 }
        lease.begin(displayID: "one")
        let old = try #require(clock.lastID)
        clock.advance(to: 5)
        lease.begin(displayID: "two")
        clock.deliverStale(old)
        #expect(lease.displayID == "two")
        #expect(ends == 1)
        clock.advance(to: 15)
        #expect(lease.displayID == nil)
        #expect(ends == 2)
        lease.begin(displayID: "three")
        lease.stop()
        clock.advance(to: 30)
        #expect(ends == 3)
        #expect(clock.pendingCount == 0)
    }
}
