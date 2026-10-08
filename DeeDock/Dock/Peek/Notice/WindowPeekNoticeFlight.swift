import AppKit
import SwiftUI

/// Carries a badged tile's hover label into Window Peek's notice strip.
///
/// The label is drawn by the dock's panel and the strip by Peek's, so neither window can draw the
/// whole path. This controller owns a click-through overlay above both for the length of one flight.
/// One display link samples ``WindowPeekNoticeMotion`` and applies each sample to the flyer, the
/// strip's reveal, and Peek's frame together, so the strip grows exactly as the banner arrives.
///
/// The coordinator stops a flight when Peek closes. A finished flight stops itself, orders out its
/// overlay, and reports through `finished`.
@MainActor
final class WindowPeekNoticeFlight {
    private let panel: NSPanel
    private let model: WindowPeekNoticeFlightModel
    private weak var peek: WindowPeekPanelController?
    /// The label's frame in screen coordinates; the overlay recomputes local frames from it.
    private let labelFrame: CGRect
    private var clock: CADisplayLink?
    private var clockTarget: WindowPeekNoticeClockTarget?
    private var startTime: CFTimeInterval?
    private var landed = false
    var finished: (() -> Void)?

    /// Prepares a flight and hides Peek's strip until it lands. Call before Peek is shown, so its
    /// first frame does not already contain the strip.
    init(peek: WindowPeekPanelController, label: WindowPeekNoticeHandoff.Label, notice: WindowPeekNotice,
         reduceTransparency: Bool) {
        self.peek = peek
        labelFrame = label.frame
        model = WindowPeekNoticeFlightModel(start: CGRect(origin: .zero, size: label.frame.size))
        panel = NSPanel(contentRect: label.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Peek's level; ordered in after Peek, so it stays in front of it.
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        let hosting = NSHostingView(rootView: WindowPeekNoticeFlightView(
            model: model, label: label.artwork, notice: notice, reduceTransparency: reduceTransparency))
        hosting.sizingOptions = []
        panel.contentView = hosting
        peek.holdNotice()
    }

    /// Shows the label in the overlay where the dock drew it and starts the clock. The dock clears
    /// its own label in the same turn, so the swap is not visible.
    func start() {
        guard clock == nil, let view = panel.contentView else { return }
        layout(target: nil)
        panel.orderFrontRegardless()
        let relay = WindowPeekNoticeClockTarget(flight: self)
        let link = view.displayLink(target: relay, selector: #selector(WindowPeekNoticeClockTarget.tick(_:)))
        clockTarget = relay
        clock = link
        link.add(to: .main, forMode: .common)
    }

    /// Ends the flight at once. Peek, if still open, shows its strip in full.
    func stop() {
        clock?.invalidate()
        clock = nil
        clockTarget = nil
        if !landed {
            landed = true
            peek?.landNotice()
        }
        panel.orderOut(nil)
        panel.contentView = nil
        let callback = finished
        finished = nil
        callback?()
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard let peek else { stop(); return }
        let now = link.targetTimestamp
        let target = peek.noticeScreenFrame
        let delay = WindowPeekNoticeMotion.handOffDelay
        let begun = startTime ?? now
        // The clock holds at the hand-off until Peek has laid out the strip it aims for.
        let elapsed = target == nil ? min(now - begun, delay) : now - begun
        startTime = now - elapsed
        let t = elapsed - delay
        let progress = WindowPeekNoticeMotion.progress(at: t)
        if !landed {
            peek.revealNotice(min(max(progress, 0), 1))
            if t >= WindowPeekNoticeMotion.settleTime {
                landed = true
                peek.landNotice()
                model.carrying = false
            }
        }
        model.progress = progress
        model.glint = WindowPeekNoticeMotion.glint(at: t)
        layout(target: target)
        if t >= WindowPeekNoticeMotion.duration { stop() }
    }

    /// Sizes the overlay around the label and the strip, with room for the arc, the lift shadow,
    /// and the landing glow, and maps both frames into its top-left-origin space.
    private func layout(target: CGRect?) {
        let destination = target ?? labelFrame
        let distance = hypot(destination.midX - labelFrame.midX, destination.midY - labelFrame.midY)
        let margin = max(64, 0.22 * distance + 40)
        let bounds = labelFrame.union(destination).insetBy(dx: -margin, dy: -margin).integral
        if panel.frame != bounds { panel.setFrame(bounds, display: false) }
        func local(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX - bounds.minX, y: bounds.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        let start = local(labelFrame)
        if model.start != start { model.start = start }
        let mapped = target.map(local)
        if model.target != mapped { model.target = mapped }
    }
}

/// CADisplayLink retains its target. This relay keeps that retention from owning the flight.
private final class WindowPeekNoticeClockTarget: NSObject {
    weak var flight: WindowPeekNoticeFlight?
    init(flight: WindowPeekNoticeFlight) { self.flight = flight }
    @objc func tick(_ link: CADisplayLink) { flight?.tick(link) }
}
