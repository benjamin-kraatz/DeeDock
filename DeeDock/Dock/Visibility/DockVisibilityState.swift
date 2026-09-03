import Foundation

/// Deterministic auto-hide policy. Its owner supplies monotonic time and schedules only the next event.
struct DockVisibilityState {
    enum Phase: Equatable { case hidden, revealDelay, revealing, visible, hideDelay, hiding }
    private struct Transition {
        let from: Double
        let to: Double
        let start: TimeInterval
        let duration: TimeInterval
    }
    private(set) var settings: DockBehaviorSettings
    private(set) var reduceMotion: Bool
    private var settled: Double
    private var transition: Transition?
    private var deadline: (time: TimeInterval, hide: Bool)?
    private var targetHidden: Bool
    private var active = true

    init(settings: DockBehaviorSettings, reduceMotion: Bool = false) {
        self.settings = settings
        self.reduceMotion = reduceMotion
        targetHidden = settings.autoHide
        settled = settings.autoHide ? 1 : 0
    }

    var phase: Phase {
        if let deadline { return deadline.hide ? .hideDelay : .revealDelay }
        if let transition { return transition.to == 1 ? .hiding : .revealing }
        return targetHidden ? .hidden : .visible
    }
    func progress(at now: TimeInterval) -> Double {
        guard let transition else { return settled }
        let t = min(1, max(0, (now - transition.start) / transition.duration))
        let eased = t * t * (3 - 2 * t)
        return transition.from + (transition.to - transition.from) * eased
    }
    func nextUpdate(after now: TimeInterval) -> TimeInterval? {
        guard active else { return nil }
        let frame = transition.map { min($0.start + $0.duration, now + 1.0 / 60) }
        return [frame, deadline?.time].compactMap { $0 }.min()
    }

    /// Repeated input preserves the existing dwell deadline. A return during hiding reverses immediately.
    mutating func update(activation: Bool, retained: Bool, held: Bool, now: TimeInterval) {
        guard active else { return }
        // Fresh pointer/hold input wins over an expired but not yet delivered deadline.
        if let pending = deadline {
            if (pending.hide && (retained || held || !settings.autoHide))
                || (!pending.hide && (!activation || held || !settings.autoHide)) { deadline = nil }
        }
        advance(now: now)
        if !settings.autoHide || held {
            deadline = nil
            move(hidden: false, now: now)
        } else if targetHidden {
            if activation || (progress(at: now) < 1 && retained) {
                if progress(at: now) < 1 { deadline = nil; move(hidden: false, now: now) }
                else { schedule(hide: false, delay: settings.revealDelay, now: now) }
            } else { deadline = nil }
        } else if retained {
            deadline = nil
        } else { schedule(hide: true, delay: settings.hideDelay, now: now) }
    }
    mutating func advance(now: TimeInterval) {
        guard active else { return }
        if let transition, now >= transition.start + transition.duration { settled = transition.to; self.transition = nil }
        if let deadline, now >= deadline.time { self.deadline = nil; move(hidden: deadline.hide, now: now) }
    }
    private mutating func schedule(hide: Bool, delay: Double, now: TimeInterval) {
        guard deadline?.hide != hide else { return }
        if delay == 0 { deadline = nil; move(hidden: hide, now: now) }
        else { deadline = (now + delay, hide) }
    }
    private mutating func move(hidden: Bool, now: TimeInterval) {
        guard targetHidden != hidden else { return }
        let from = progress(at: now)
        targetHidden = hidden
        let to = hidden ? 1.0 : 0.0
        let duration = (reduceMotion ? min(0.10, settings.animationDuration) : settings.animationDuration) * abs(to - from)
        if duration == 0 { settled = to; transition = nil }
        else { transition = Transition(from: from, to: to, start: now, duration: duration) }
    }
    /// Configuration changes settle obsolete motion but preserve whether the dock was shown.
    mutating func configure(_ settings: DockBehaviorSettings, reduceMotion: Bool) {
        self.settings = settings
        self.reduceMotion = reduceMotion
        transition = nil
        deadline = nil
        if !settings.autoHide { targetHidden = false }
        settled = targetHidden ? 1 : 0
    }
    mutating func showImmediately() { targetHidden = false; settled = 0; transition = nil; deadline = nil }
    mutating func stop() { active = false; transition = nil; deadline = nil; settled = 1; targetHidden = true }
}
