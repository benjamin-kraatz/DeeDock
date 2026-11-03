import AppKit
import Observation
import SwiftUI

/// Swipe-to-clear for the open notification feed: one row at a time follows a two-finger
/// trackpad swipe or a mouse drag, snaps open on its Clear action, or flies out.
///
/// SwiftUI's gestures cannot see trackpad scroll phases, so a local `.scrollWheel` monitor reads
/// them while the popover is open. ``start()`` installs it and ``stop()`` removes it; the feed's
/// coordinator calls both with the popover's lifetime. The monitor claims a gesture only once it
/// is clearly horizontal and lands on a swipeable row. Until then, and for every vertical
/// gesture, events pass through untouched so the list keeps scrolling. Once claimed, the rest of
/// the gesture and its momentum are consumed, so the list does not scroll underneath.
///
/// Rows find themselves through ``NotificationFeedSwipeProbe`` views, which register here while
/// they are in a window. A collapsed stack swipes as a whole through its front row.
@MainActor @Observable
final class NotificationFeedSwipeTracker {
    typealias ID = NotificationFeedEntry.ID
    private typealias Physics = NotificationFeedSwipePhysics

    /// The row following the pointer, or flying out.
    private(set) var activeID: ID?
    private(set) var activeReveal: CGFloat = 0
    /// The row resting open on its Clear action.
    private(set) var revealedID: ID?
    /// Rows that have flown out and faded, kept invisible until the feed drops them.
    private(set) var committed: [ID: CGFloat] = [:]

    /// Removes a row, or the whole stack when `isStack`, once it has flown out.
    @ObservationIgnored var onCommit: ((ID, _ isStack: Bool) -> Void)?
    /// Read once per gesture; tests and previews can pin it.
    @ObservationIgnored var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    @ObservationIgnored private var probes: [ID: Probe] = [:]
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var scroll: ScrollGesture?
    /// True from a claimed gesture's end until its momentum stops.
    @ObservationIgnored private var swallowingMomentum = false
    @ObservationIgnored private var drag: DragState?
    /// Set while a horizontal mouse drag is under way and until the click it ends has been
    /// delivered, so the release does not also count as a click on the row.
    @ObservationIgnored private(set) var swallowsTap = false

    private struct Probe {
        weak var view: NSView?
        var isStack: Bool
    }

    private struct ScrollGesture {
        let id: ID
        let isStack: Bool
        let width: CGFloat
        let start: CGFloat
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var intent: Physics.Intent?
        var samples: [(time: TimeInterval, x: CGFloat)] = []

        /// Content speed in points per second over the last tenth of a second.
        var velocity: CGFloat {
            guard let last = samples.last,
                  let first = samples.first(where: { last.time - $0.time <= 0.1 }),
                  last.time > first.time else { return 0 }
            return (last.x - first.x) / CGFloat(last.time - first.time)
        }
    }

    private struct DragState {
        let id: ID
        let start: CGFloat
        var intent: Physics.Intent?
    }

    // MARK: - Reading

    /// How far a row is moved left of its resting place.
    func reveal(for id: ID) -> CGFloat {
        if let committed = committed[id] { return committed }
        if activeID == id { return activeReveal }
        return revealedID == id ? Physics.actionWidth : 0
    }

    func isCommitted(_ id: ID) -> Bool { committed[id] != nil }
    var hasRevealed: Bool { revealedID != nil }

    // MARK: - Lifetime

    /// Installs the scroll-wheel monitor. Repeated calls do nothing.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return handleScroll(event)
        }
    }

    /// Removes the monitor and forgets every gesture. Rows already committed still reach
    /// ``onCommit`` when their animation finishes, so the feed stays consistent.
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        scroll = nil
        drag = nil
        swallowingMomentum = false
        revealedID = nil
        if committed.isEmpty { activeID = nil }
    }

    func register(_ view: NSView, id: ID, isStack: Bool) {
        probes[id] = Probe(view: view, isStack: isStack)
    }

    func unregister(_ view: NSView, id: ID) {
        guard probes[id]?.view === view else { return }
        probes[id] = nil
        committed[id] = nil
        if revealedID == id { revealedID = nil }
    }

    // MARK: - Commands

    /// Slides an open row closed.
    func closeRevealed() {
        guard revealedID != nil else { return }
        withAnimation(motion) { revealedID = nil }
    }

    /// Clears the open row, as a click on its revealed action does.
    func commitRevealed(_ id: ID) {
        guard revealedID == id else { return }
        commit(id, isStack: probes[id]?.isStack ?? false, from: Physics.actionWidth)
    }

    // MARK: - Mouse drag

    /// Follows a mouse drag on a row. Only a clearly horizontal drag moves it.
    func dragChanged(_ id: ID, translation: CGSize, isStack: Bool) {
        guard committed[id] == nil else { return }
        if drag?.id != id { drag = DragState(id: id, start: reveal(for: id)) }
        guard var state = drag else { return }
        if state.intent == nil {
            state.intent = Physics.intent(dx: translation.width, dy: translation.height)
            if state.intent == .horizontal { begin(id) }
        }
        drag = state
        guard state.intent == .horizontal else { return }
        swallowsTap = true
        activeID = id
        activeReveal = Physics.reveal(start: state.start, translation: translation.width, width: width(of: id))
    }

    /// Settles a dragged row: snaps it open or closed, or clears it.
    /// - Parameter velocity: Horizontal pointer speed in points per second.
    func dragEnded(_ id: ID, velocity: CGFloat, isStack: Bool) {
        defer {
            drag = nil
            // The click this drag ends is delivered after this handler; let it be swallowed first.
            DispatchQueue.main.async { [weak self] in self?.swallowsTap = false }
        }
        guard drag?.id == id, drag?.intent == .horizontal else { return }
        finish(id, isStack: isStack, velocity: velocity)
    }

    // MARK: - Trackpad

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        // Mouse wheels have no phases and scroll the list as usual.
        guard event.hasPreciseScrollingDeltas else { return event }
        if !event.momentumPhase.isEmpty {
            guard swallowingMomentum else { return event }
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                swallowingMomentum = false
            }
            return nil
        }
        let phase = event.phase
        if phase.contains(.began) {
            swallowingMomentum = false
            scroll = row(at: event).map { hit in
                ScrollGesture(id: hit.id, isStack: hit.isStack, width: hit.width, start: reveal(for: hit.id))
            }
        }
        guard var gesture = scroll else { return event }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            scroll = nil
            guard gesture.intent == .horizontal else { return event }
            swallowingMomentum = true
            finish(gesture.id, isStack: gesture.isStack, velocity: gesture.velocity)
            return nil
        }
        guard phase.contains(.began) || phase.contains(.changed) else { return event }
        // Follow the fingers whatever the scroll direction setting: natural scrolling already
        // reports finger movement, the classic setting reports the opposite.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        gesture.dx += event.scrollingDeltaX * sign
        gesture.dy += event.scrollingDeltaY * sign
        gesture.samples.append((event.timestamp, gesture.dx))
        if gesture.samples.count > 8 { gesture.samples.removeFirst() }
        if gesture.intent == nil {
            gesture.intent = Physics.intent(dx: gesture.dx, dy: gesture.dy)
            switch gesture.intent {
            case .horizontal: begin(gesture.id)
            case .vertical: closeRevealed()
            case nil: break
            }
        }
        scroll = gesture
        guard gesture.intent == .horizontal, committed[gesture.id] == nil else { return event }
        activeID = gesture.id
        activeReveal = Physics.reveal(start: gesture.start, translation: gesture.dx, width: gesture.width)
        return nil
    }

    private struct Hit {
        let id: ID
        let isStack: Bool
        let width: CGFloat
    }

    /// The registered row under the pointer, if the event belongs to its window and the row is
    /// not scrolled out of view. `visibleRect` excludes the parts the list's clip view hides.
    private func row(at event: NSEvent) -> Hit? {
        for (id, probe) in probes {
            guard let view = probe.view, let window = view.window, window === event.window else { continue }
            let point = view.convert(event.locationInWindow, from: nil)
            if view.visibleRect.contains(point) { return Hit(id: id, isStack: probe.isStack, width: view.bounds.width) }
        }
        return nil
    }

    // MARK: - Shared settling

    private var motion: Animation { NotificationFeedMotion.standard(reduceMotion: reduceMotion()) }

    private func width(of id: ID) -> CGFloat {
        probes[id]?.view?.bounds.width ?? 360
    }

    /// Starts moving `id`, closing any other open row.
    private func begin(_ id: ID) {
        if let revealedID, revealedID != id { withAnimation(motion) { self.revealedID = nil } }
        if revealedID == id {
            // Hand the open row to the gesture without a jump.
            activeReveal = Physics.actionWidth
            activeID = id
            revealedID = nil
        }
    }

    private func finish(_ id: ID, isStack: Bool, velocity: CGFloat) {
        let reveal = activeID == id ? activeReveal : self.reveal(for: id)
        switch Physics.outcome(reveal: reveal, width: width(of: id), velocity: velocity) {
        case .commit:
            commit(id, isStack: isStack, from: max(0, reveal))
        case .reveal:
            withAnimation(motion) {
                activeID = nil
                revealedID = id
            }
        case .close:
            withAnimation(motion) {
                activeID = nil
                if revealedID == id { revealedID = nil }
            }
        }
    }

    /// Flies the row out to the left, fades it, then hands it to ``onCommit``. Reduce Motion
    /// fades it where it is.
    private func commit(_ id: ID, isStack: Bool, from reveal: CGFloat) {
        if revealedID == id { revealedID = nil }
        activeID = id
        activeReveal = reveal
        let done: () -> Void = { [weak self] in self?.onCommit?(id, isStack) }
        if reduceMotion() {
            withAnimation(NotificationFeedMotion.reduced) { committed[id] = reveal } completion: { done() }
            return
        }
        let out = width(of: id) + 16
        withAnimation(.timingCurve(0.3, 0, 0.7, 0.4, duration: 0.2)) {
            activeReveal = out
        } completion: { [weak self] in
            guard let self else { return done() }
            withAnimation(.linear(duration: 0.12)) {
                self.committed[id] = out
                if self.activeID == id { self.activeID = nil }
            } completion: { done() }
        }
    }

    #if DEBUG
    /// Holds a row part-way open, for previews.
    func previewReveal(_ id: ID, by reveal: CGFloat) {
        activeID = id
        activeReveal = reveal
    }
    #endif
}
