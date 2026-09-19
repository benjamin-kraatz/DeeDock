import AppKit
import QuartzCore
import SwiftUI

/// Owns the native merging glass and its short-lived, display-synchronized spring.
/// SwiftUI updates endpoints and content, never the frame-by-frame animation state.
final class LauncherLiquidGlassView: NSView {
    private let glassContainer = NSGlassEffectContainerView()
    private let canvas = LauncherFlippedView()
    private let dockGlass = NSGlassEffectView()
    private let bubbleGlass = NSGlassEffectView()
    /// Clips the dock's icons to the dock glass without placing them inside it. Content hosted by
    /// NSGlassEffectView receives glass legibility treatment, which the resting dock (icons drawn
    /// beside its SwiftUI glass) does not, so hosting it there tinted icons and indicators
    /// until the swap back to the plain dock.
    private let dockClip = LauncherFlippedView()
    private let dockContent: LauncherGlassContentView
    private let launcherContent: LauncherGlassContentView
    private var geometry: LauncherLiquidGeometry
    private var clock: CADisplayLink?
    private var clockTarget: LauncherGlassClockTarget?
    private var timestamp: CFTimeInterval = 0
    private var progress = 0.0
    private var velocity = 0.0
    private var target = 1.0
    private var settledTarget: Double?
    private var reduceMotion = false
    private var renderedSample: LauncherLiquidGeometry.Sample?
    var onSettled: ((Bool) -> Void)?
    override var isFlipped: Bool { true }

    init(geometry: LauncherLiquidGeometry, dock: AnyView, launcher: AnyView) {
        self.geometry = geometry
        dockContent = LauncherGlassContentView(rootView: dock)
        launcherContent = LauncherGlassContentView(rootView: launcher)
        super.init(frame: .zero)
        wantsLayer = true
        // Nearby glass shapes meld into one outline while the dock is absorbed.
        glassContainer.spacing = 10
        glassContainer.contentView = canvas
        addSubview(glassContainer)
        dockGlass.style = .regular
        bubbleGlass.style = .regular
        bubbleGlass.contentView = launcherContent
        canvas.addSubview(bubbleGlass)
        canvas.addSubview(dockGlass)
        // Above the whole glass container, so neither merging shape refracts the returning icons.
        dockClip.wantsLayer = true
        dockClip.autoresizesSubviews = false
        dockClip.layer?.masksToBounds = true
        dockClip.layer?.cornerCurve = .continuous
        dockClip.addSubview(dockContent)
        addSubview(dockClip)
    }

    /// Progress below this renders the resting dock exactly. Closing completes on entry instead of
    /// waiting out the spring's sub-pixel tail, during which only a hidden seed bubble moved.
    private static let restZone = 0.04

    required init?(coder: NSCoder) { nil }

    func update(geometry: LauncherLiquidGeometry, dock: AnyView, launcher: AnyView,
                dockCanvas: CGRect, expanded: Bool, reduceMotion: Bool, reduceTransparency: Bool) {
        self.geometry = geometry
        self.reduceMotion = reduceMotion
        dockContent.update(rootView: dock)
        launcherContent.update(rootView: launcher)
        dockContent.contentSize = dockCanvas.size
        // Window coordinates: the clip moves over the icons, the icons never move.
        dockContent.contentOffset = dockCanvas.origin
        if dockContent.frame.size != bounds.size { dockContent.setFrameSize(bounds.size) }
        launcherContent.contentSize = geometry.destination.size
        // Native glass also observes accessibility preferences. An opaque content backing
        // preserves DDock's explicit Reduce Transparency treatment without fading the glass.
        let backing = reduceTransparency ? NSColor.windowBackgroundColor.cgColor : nil
        dockContent.layer?.backgroundColor = backing
        launcherContent.layer?.backgroundColor = backing
        let newTarget = expanded ? 1.0 : 0.0
        if target != newTarget {
            target = newTarget; settledTarget = nil
            // Pointer highlights belong to the resting launcher, not to a shape in flight.
            bubbleGlass.effectIsInteractive = false
        }
        render()
        startIfNeeded()
    }

    override func layout() {
        super.layout()
        if glassContainer.frame != bounds { glassContainer.frame = bounds }
        if dockContent.frame.size != bounds.size { dockContent.setFrameSize(bounds.size) }
        render()
        startIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else { startIfNeeded() }
    }

    /// Stops on detachment and representable teardown, including display removal and app quit.
    func stop() {
        clock?.invalidate()
        clock = nil
        clockTarget = nil
        timestamp = 0
    }

    private func startIfNeeded() {
        guard window != nil, bounds.width > 0, bounds.height > 0, settledTarget != target else { return }
        if reduceMotion {
            progress = target; velocity = 0
            render()
            finish()
            return
        }
        guard clock == nil else { return }
        let relay = LauncherGlassClockTarget(view: self)
        let link = displayLink(target: relay, selector: #selector(LauncherGlassClockTarget.tick(_:)))
        clockTarget = relay
        clock = link
        link.add(to: .main, forMode: .common)
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        // The analytic spring remains stable across missed frames. Clamping elapsed time
        // would turn a busy main thread into a visibly slower animation.
        let dt = timestamp == 0 ? max(1.0 / 240, now - link.timestamp) : max(0, now - timestamp)
        timestamp = now
        // Analytic damped spring integration is independent of refresh rate. Retargeting keeps
        // both position and velocity, so Escape during expansion reverses the existing motion.
        let displacement = progress - target
        if target == 1 {
            // Opening: a lively spring with a little overshoot.
            let omega = 17.0, damping = 0.82
            let decay = omega * damping
            let frequency = omega * sqrt(1 - damping * damping)
            let b = (velocity + decay * displacement) / frequency
            let cosine = cos(frequency * dt), sine = sin(frequency * dt)
            let envelope = exp(-decay * dt)
            progress = target + envelope * (displacement * cosine + b * sine)
            velocity = envelope * ((-decay * displacement + frequency * b) * cosine
                                   + (-decay * b - frequency * displacement) * sine)
        } else {
            // Closing: critically damped, so it never crosses into the rest zone early and lands
            // in about a quarter second instead of creeping over the restored dock.
            let omega = 18.0
            let envelope = exp(-omega * dt)
            let c = velocity + omega * displacement
            progress = target + (displacement + c * dt) * envelope
            velocity = (velocity - omega * c * dt) * envelope
        }
        let landed = target == 0
            ? progress <= Self.restZone
            : abs(progress - target) < 0.0008 && abs(velocity) < 0.015
        if landed {
            progress = target; velocity = 0
            render()
            finish()
        } else {
            render()
        }
    }

    private func render() {
        let visual = max(0, (progress - Self.restZone) / (1 - Self.restZone))
        let sample = geometry.sample(at: visual)
        // AppKit layout and SwiftUI updates can revisit the same spring sample. Reapplying
        // glass frames here schedules more layout without producing a different image.
        guard sample != renderedSample else { return }
        renderedSample = sample
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dockGlass.isHidden = sample.dockHidden
        if !sample.dockHidden {
            if dockGlass.frame != sample.dock { dockGlass.frame = sample.dock }
            if dockGlass.cornerRadius != sample.dockRadius { dockGlass.cornerRadius = sample.dockRadius }
        }
        bubbleGlass.frame = sample.bubble
        bubbleGlass.cornerRadius = sample.bubbleRadius
        bubbleGlass.isHidden = sample.bubbleHidden
        // Only the clip resizes; the hosted dock just shifts so its icons hold their screen position.
        dockClip.isHidden = sample.dockHidden || sample.dockContentOpacity <= 0
        // The icons disappear early in expansion. Leave their hidden hierarchy alone until
        // they return on collapse, instead of moving and clipping it throughout the spring.
        if !dockClip.isHidden {
            if dockClip.frame != sample.dock { dockClip.frame = sample.dock }
            dockClip.layer?.cornerRadius = sample.dockRadius
            let origin = CGPoint(x: -sample.dock.minX, y: -sample.dock.minY)
            if dockContent.frame.origin != origin { dockContent.setFrameOrigin(origin) }
            dockContent.present(viewport: sample.dock.size, scale: 1, opacity: sample.dockContentOpacity)
        }
        // NSGlassEffectView owns its contentView frame through Auto Layout. Do not also
        // resize that view, or resize/rebound NSHostingView, from this display-link callback.
        launcherContent.present(viewport: sample.bubble.size, scale: sample.launcherContentScale,
                                opacity: sample.launcherContentOpacity)
        CATransaction.commit()
    }

    private func finish() {
        stop()
        settledTarget = target
        let expanded = target == 1
        if !expanded { progress = 0; velocity = 0; render() }
        bubbleGlass.effectIsInteractive = expanded
        // Completions can replace the hosting hierarchy. Keep them outside AppKit's layout
        // and SwiftUI's representable update, and discard them after a reversal or detachment.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.settledTarget == (expanded ? 1 : 0) else { return }
            self.onSettled?(expanded)
        }
    }

#if DEBUG
    /// Scrubs the real native renderer in Xcode without running services or changing preferences.
    func inspect(progress: Double) {
        stop()
        settledTarget = target
        self.progress = progress
        render()
    }
#endif
}

private final class LauncherFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// CADisplayLink retains its target. This relay keeps that retention from owning the view.
private final class LauncherGlassClockTarget: NSObject {
    weak var view: LauncherLiquidGlassView?
    init(view: LauncherLiquidGlassView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) { view?.tick(link) }
}
