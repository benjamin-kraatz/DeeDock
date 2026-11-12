import AppKit
import SwiftUI

/// Vapor's four windows: the orb, the panel, the suggestion bubbles and the callout capsule.
///
/// The panel's and the bubbles' windows both cover the orb and sit behind the orb's window.
///
/// Each is a separate ``VaporPanel`` placed from the orb's centre and the visible frame of the
/// orb's display, in AppKit global coordinates. This object only shows, hides and places them;
/// what they show comes from ``VaporController``, and when comes from ``VaporCoordinator``.
///
/// The panel's window is larger than the panel and covers the orb (see
/// ``VaporGeometry/panelWindowFrame(panelFrame:opensLeft:)``), so the panel can grow out of the
/// orb and, on delete, rows can fly into it. The orb's window is kept in front of it.
///
/// Delete sequence: the controller raises ``VaporController/deletion`` and closes the panel in
/// one step. If the panel was showing, the rows are pulled into the orb first, the panel
/// shrinks after ``VaporMotion/panelCloseDelay(rows:)``, and the capsule waits until the orb
/// has started to evaporate.
@MainActor
final class VaporWindows {
    /// Called while the orb is dragged, with its centre and the event time.
    var orbMoved: ((CGPoint, TimeInterval) -> Void)? {
        get { orbView.moved }
        set { orbView.moved = newValue }
    }
    /// Called when an orb drag ends, with the orb's centre.
    var orbMoveEnded: ((CGPoint) -> Void)? {
        get { orbView.moveEnded }
        set { orbView.moveEnded = newValue }
    }
    var makeMenu: (() -> NSMenu)? {
        get { orbView.makeMenu }
        set { orbView.makeMenu = newValue }
    }
    /// A file drag moved over the orb (`overPanel` false) or the panel (true), or left (nil).
    var dragMoved: ((CGPoint?, _ overPanel: Bool) -> Void)?
    /// Files were dropped on the orb or the panel. Returns whether anything was added.
    var dropped: (([URL]) -> Bool)?
    /// A window's content changed size, so placement should run again.
    var needsLayout: (() -> Void)?

    private let controller: VaporController
    private let orbPanel = VaporPanel(size: VaporGeometry.orbWindowSize)
    private let orbView: VaporOrbInteractionView
    private let orbPointerGate: VaporOrbPointerGate
    private let panel = VaporPanel()
    private let panelDrop = VaporDropView(frame: .zero)
    private let presentation = VaporPanelPresentation()
    private let suggestionsPanel = VaporPanel()
    private let suggestionsHost: VaporHostingView<VaporSuggestionsView>
    private let calloutPanel = VaporPanel()
    private let calloutHost: VaporHostingView<VaporCalloutView>

    /// The panel window is on screen (growing, open, pulling rows or shrinking).
    private var panelOnScreen = false
    /// The panel was asked to open before its size was known; it grows once measured.
    private var growWhenMeasured = false
    /// The panel's frame in global coordinates while open, for drops and outside clicks.
    private var panelContentFrame: CGRect?
    private var handledDeletion: UUID?
    /// Rows are flying into the orb; the panel stays until the task closes it.
    private var pullTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    /// What the suggestions view was last built for; it is rebuilt only when the orb moves.
    private var suggestionsPlacement: (orbCenter: CGPoint, visibleFrame: CGRect)?
    /// The capsule stays hidden until this moment, so it follows the delete animation.
    private var calloutHeldUntil: Date?
    private var calloutTask: Task<Void, Never>?

    init(controller: VaporController) {
        self.controller = controller
        orbView = VaporOrbInteractionView(frame: CGRect(origin: .zero, size: VaporGeometry.orbWindowSize))
        let orbHost = VaporHostingView(rootView: VaporOrbView(controller: controller))
        orbHost.frame = orbView.bounds
        orbHost.autoresizingMask = [.width, .height]
        orbView.addSubview(orbHost)
        orbPanel.contentView = orbView
        orbPointerGate = VaporOrbPointerGate(view: orbView)

        let panelHost = VaporHostingView(rootView: VaporPanelStage(controller: controller, presentation: presentation))
        panelHost.sizingOptions = []
        panelHost.autoresizingMask = [.width, .height]
        panelDrop.addSubview(panelHost)
        panel.contentView = panelDrop

        suggestionsHost = VaporHostingView(rootView: VaporSuggestionsView(controller: controller, orbCenter: .zero,
                                                                          visibleFrame: .zero))
        suggestionsPanel.contentView = suggestionsHost

        calloutHost = VaporHostingView(rootView: VaporCalloutView(controller: controller))
        calloutHost.sizingOptions = [.intrinsicContentSize]
        calloutPanel.contentView = calloutHost

        orbView.dragMoved = { [weak self] point in self?.dragMoved?(point, false) }
        orbView.dropped = { [weak self] urls in self?.dropped?(urls) ?? false }
        orbView.hoverChanged = { [weak controller] hovered in controller?.isOrbHovered = hovered }
        panelDrop.dragMoved = { [weak self] point in self?.dragMoved?(point, true) }
        panelDrop.dropped = { [weak self] urls in self?.dropped?(urls) ?? false }
        presentation.sizeChanged = { [weak self] in self?.needsLayout?() }
        calloutHost.intrinsicSizeChanged = { [weak self] in self?.needsLayout?() }
    }

    /// Frames on screen that belong to Vapor, for telling clicks inside from clicks outside.
    /// The panel counts with its own frame, not its larger transparent window.
    var visibleFrames: [CGRect] {
        var frames = [orbPanel, suggestionsPanel, calloutPanel].filter(\.isVisible).map(\.frame)
        if let panelContentFrame { frames.append(panelContentFrame) }
        return frames
    }

    /// The open panel's frame, or nil.
    var panelFrame: CGRect? { panelContentFrame }

    /// Shows the orb centred at `center`.
    func showOrb(at center: CGPoint, animated: Bool) {
        let frame = VaporGeometry.orbWindowFrame(center: center)
        if animated, orbPanel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                orbPanel.animator().setFrame(frame, display: true)
            }
        } else {
            orbPanel.setFrame(frame, display: true)
        }
        orbPanel.orderFrontRegardless()
        orbPointerGate.start()
    }

    /// Places the panel, bubbles and callout around the orb from the controller's state.
    func layout(orbCenter: CGPoint, visibleFrame: CGRect) {
        startPullIfNeeded()
        layoutPanel(orbCenter: orbCenter, visibleFrame: visibleFrame)
        layoutSuggestions(orbCenter: orbCenter, visibleFrame: visibleFrame)
        layoutCallout(orbCenter: orbCenter, visibleFrame: visibleFrame)
    }

    // MARK: Panel

    /// A delete from the open panel: keep the panel up while its rows fly into the orb, then
    /// shrink it. Without the panel (VoiceOver's Delete All), or under Reduce Motion, nothing
    /// waits.
    private func startPullIfNeeded() {
        guard let deletion = controller.deletion, deletion.token != handledDeletion else { return }
        handledDeletion = deletion.token
        let fromPanel = deletion.payload.fromPanel && panelOnScreen && !controller.reduceMotion
        let rows = deletion.payload.folders.count
        let evaporate = VaporMotion.evaporateDelay(rows: rows, fromPanel: fromPanel)
        calloutHeldUntil = evaporate > 0 ? Date.now.addingTimeInterval(evaporate) : nil
        guard fromPanel else { return }
        presentation.pull = deletion.payload
        pullTask?.cancel()
        pullTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(VaporMotion.panelCloseDelay(rows: rows)))
            guard !Task.isCancelled, let self else { return }
            self.pullTask = nil
            self.needsLayout?()
        }
    }

    private func layoutPanel(orbCenter: CGPoint, visibleFrame: CGRect) {
        guard controller.isPanelOpen else {
            // Rows are still flying into the orb: the panel closes when the pull task ends.
            guard pullTask == nil else { return }
            hidePanel()
            return
        }
        // Reopened during a pull or a shrink: show the live rows again.
        pullTask?.cancel()
        pullTask = nil
        hideTask?.cancel()
        hideTask = nil
        presentation.pull = nil

        let opensLeft = VaporGeometry.opensLeft(orbCenter: orbCenter, visibleFrame: visibleFrame)
        let size = presentation.panelSize ?? CGSize(width: VaporPanelView.width, height: 260)
        let content = VaporGeometry.panelFrame(orbCenter: orbCenter, size: size, visibleFrame: visibleFrame)
        let window = VaporGeometry.panelWindowFrame(panelFrame: content, opensLeft: opensLeft)
        let origin = VaporGeometry.panelOrigin(opensLeft: opensLeft)
        panel.setFrame(window, display: true)
        presentation.panelOrigin = origin
        presentation.orbPoint = VaporGeometry.local(orbCenter, in: window)
        panelContentFrame = content
        panelDrop.dropArea = CGRect(x: origin.x, y: window.height - origin.y - content.height,
                                    width: content.width, height: content.height)

        if !panelOnScreen {
            panelOnScreen = true
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            // The orb stays in front, so rows flying into it pass behind the glass.
            orbPanel.orderFrontRegardless()
            growWhenMeasured = presentation.panelSize == nil
        }
        if growWhenMeasured, presentation.panelSize != nil { growWhenMeasured = false }
        if !growWhenMeasured, !presentation.isShown {
            // Let the window show the shrunken panel for one pass before the spring starts.
            Task { @MainActor [weak self] in
                guard let self, self.controller.isPanelOpen else { return }
                self.presentation.isShown = true
            }
        }
    }

    private func hidePanel() {
        panelContentFrame = nil
        panelDrop.dropArea = .zero
        guard panelOnScreen else { return }
        presentation.isShown = false
        guard hideTask == nil else { return }
        let delay = controller.reduceMotion ? 0.22 : VaporMotion.panelCloseDuration
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.hideTask = nil
            guard !self.controller.isPanelOpen else { return }
            self.panelOnScreen = false
            self.presentation.pull = nil
            self.panel.orderOut(nil)
        }
    }

    // MARK: Suggestions

    private func layoutSuggestions(orbCenter: CGPoint, visibleFrame: CGRect) {
        let bubbles = controller.bubbleSuggestions
        guard !bubbles.isEmpty else {
            if suggestionsPanel.isVisible { fadeOut(suggestionsPanel) }
            return
        }
        // The frame depends only on where the orb is, so it stays put while bubbles come and go
        // and they can glide inside it. The view lays its bubbles out itself.
        let frame = VaporSuggestionsView.layout(orbCenter: orbCenter, count: bubbles.count, visibleFrame: visibleFrame).windowFrame
        if suggestionsPlacement?.orbCenter != orbCenter || suggestionsPlacement?.visibleFrame != visibleFrame {
            suggestionsPlacement = (orbCenter, visibleFrame)
            suggestionsHost.rootView = VaporSuggestionsView(controller: controller, orbCenter: orbCenter, visibleFrame: visibleFrame)
        }
        if suggestionsPanel.frame != frame { suggestionsPanel.setFrame(frame, display: true) }
        if !suggestionsPanel.isVisible || suggestionsPanel.alphaValue < 1 {
            // The bubbles spring out of the orb themselves; the window only needs to be there.
            suggestionsPanel.alphaValue = 1
            suggestionsPanel.orderFrontRegardless()
            // This window covers the orb so bubbles can fly into it. The orb stays in front: it
            // keeps its clicks and drops, and bubbles pass behind the glass.
            orbPanel.orderFrontRegardless()
        }
    }

    // MARK: Callout

    private func layoutCallout(orbCenter: CGPoint, visibleFrame: CGRect) {
        if let until = calloutHeldUntil, until > .now {
            calloutPanel.orderOut(nil)
            scheduleCalloutLayout(at: until)
            return
        }
        calloutHeldUntil = nil
        guard controller.callout != nil else {
            if calloutPanel.isVisible, calloutPanel.alphaValue > 0 { fadeOut(calloutPanel) }
            return
        }
        let fitting = calloutHost.fittingSize
        let margin = VaporCalloutView.margin
        let size = CGSize(width: fitting.width - margin * 2, height: fitting.height - margin * 2)
        guard size.width > 0, size.height > 0 else { return }
        let frame = VaporGeometry.statusFrame(orbCenter: orbCenter, size: size, visibleFrame: visibleFrame)
        calloutPanel.setFrame(frame.insetBy(dx: -margin, dy: -margin), display: true)
        calloutPanel.alphaValue = 1
        calloutPanel.orderFrontRegardless()
        // The capsule's window reaches a few points into the orb's; the orb stays in front.
        orbPanel.orderFrontRegardless()
    }

    private func scheduleCalloutLayout(at date: Date) {
        calloutTask?.cancel()
        calloutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(date.timeIntervalSinceNow, 0) + 0.01))
            guard !Task.isCancelled, let self else { return }
            self.calloutTask = nil
            self.needsLayout?()
        }
    }

    private func fadeOut(_ window: NSWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                // A show that started meanwhile wins.
                if window.alphaValue == 0 { window.orderOut(nil) }
            }
        }
    }

    // MARK: Teardown

    /// Hides every window. They can be shown again.
    func hideAll() {
        [pullTask, hideTask, calloutTask].forEach { $0?.cancel() }
        pullTask = nil
        hideTask = nil
        calloutTask = nil
        calloutHeldUntil = nil
        orbPointerGate.stop()
        [orbPanel, panel, suggestionsPanel, calloutPanel].forEach { $0.orderOut(nil) }
        panelOnScreen = false
        panelContentFrame = nil
        presentation.isShown = false
        presentation.pull = nil
    }

    /// Hides and releases everything; call when Vapor turns off or DOKK quits.
    func tearDown() {
        hideAll()
        orbView.unregisterDraggedTypes()
        panelDrop.unregisterDraggedTypes()
        orbView.moved = nil
        orbView.moveEnded = nil
        orbView.makeMenu = nil
        orbView.clicked = nil
        orbView.hoverChanged = nil
        orbView.dragMoved = nil
        orbView.dropped = nil
        panelDrop.dragMoved = nil
        panelDrop.dropped = nil
        presentation.sizeChanged = nil
        calloutHost.intrinsicSizeChanged = nil
        [orbPanel, panel, suggestionsPanel, calloutPanel].forEach { $0.close() }
    }

    /// Click on the orb (without moving it).
    var orbClicked: (() -> Void)? {
        get { orbView.clicked }
        set { orbView.clicked = newValue }
    }
}
