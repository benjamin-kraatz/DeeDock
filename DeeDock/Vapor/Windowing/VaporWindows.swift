import AppKit
import SwiftUI

/// Vapor's four windows: the orb, the panel, the suggestion bubbles and the callout capsule.
///
/// Each is a separate ``VaporPanel`` placed from the orb's centre and the visible frame of the
/// orb's display, in AppKit global coordinates. This object only shows, hides and places them;
/// what they show comes from ``VaporController``, and when comes from ``VaporCoordinator``.
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
    private let panel = VaporPanel()
    private let panelHost: VaporHostingView<VaporPanelView>
    private let suggestionsPanel = VaporPanel()
    private let suggestionsHost: VaporHostingView<VaporSuggestionsView>
    private let calloutPanel = VaporPanel()
    private let calloutHost: VaporHostingView<VaporCalloutView>
    private var panelShown = false

    init(controller: VaporController) {
        self.controller = controller
        orbView = VaporOrbInteractionView(frame: CGRect(origin: .zero, size: VaporGeometry.orbWindowSize))
        let orbHost = VaporHostingView(rootView: VaporOrbView(controller: controller))
        orbHost.frame = orbView.bounds
        orbHost.autoresizingMask = [.width, .height]
        orbView.addSubview(orbHost)
        orbPanel.contentView = orbView

        panelHost = VaporHostingView(rootView: VaporPanelView(controller: controller))
        panelHost.sizingOptions = [.intrinsicContentSize]
        let panelDrop = VaporDropView(frame: .zero)
        panelHost.autoresizingMask = [.width, .height]
        panelDrop.addSubview(panelHost)
        panel.contentView = panelDrop

        let emptyLayout = VaporSatelliteLayout(windowFrame: .zero, bubbleCenters: [], capsuleCenter: .zero, orbCenter: .zero)
        suggestionsHost = VaporHostingView(rootView: VaporSuggestionsView(controller: controller, layout: emptyLayout))
        suggestionsPanel.contentView = suggestionsHost

        calloutHost = VaporHostingView(rootView: VaporCalloutView(controller: controller))
        calloutHost.sizingOptions = [.intrinsicContentSize]
        calloutPanel.contentView = calloutHost

        orbView.dragMoved = { [weak self] point in self?.dragMoved?(point, false) }
        orbView.dropped = { [weak self] urls in self?.dropped?(urls) ?? false }
        orbView.hoverChanged = { [weak controller] hovered in controller?.isOrbHovered = hovered }
        panelDrop.dragMoved = { [weak self] point in self?.dragMoved?(point, true) }
        panelDrop.dropped = { [weak self] urls in self?.dropped?(urls) ?? false }
        panelHost.intrinsicSizeChanged = { [weak self] in self?.needsLayout?() }
        calloutHost.intrinsicSizeChanged = { [weak self] in self?.needsLayout?() }
    }

    /// Frames of the windows on screen, for telling clicks inside Vapor from clicks outside.
    var visibleFrames: [CGRect] {
        [orbPanel, panel, suggestionsPanel, calloutPanel].filter(\.isVisible).map(\.frame)
    }

    /// The open panel's frame, or nil.
    var panelFrame: CGRect? { panel.isVisible ? panel.frame : nil }

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
    }

    /// Places the panel, bubbles and callout around the orb from the controller's state.
    func layout(orbCenter: CGPoint, visibleFrame: CGRect) {
        layoutPanel(orbCenter: orbCenter, visibleFrame: visibleFrame)
        layoutSuggestions(orbCenter: orbCenter, visibleFrame: visibleFrame)
        layoutCallout(orbCenter: orbCenter, visibleFrame: visibleFrame)
    }

    private func layoutPanel(orbCenter: CGPoint, visibleFrame: CGRect) {
        guard controller.isPanelOpen else {
            guard panelShown else { return }
            panelShown = false
            fadeOut(panel)
            return
        }
        let size = panelHost.fittingSize
        let frame = VaporGeometry.panelFrame(orbCenter: orbCenter, size: size, visibleFrame: visibleFrame)
        panel.setFrame(frame, display: true)
        if !panelShown {
            panelShown = true
            fadeIn(panel)
        }
    }

    private func layoutSuggestions(orbCenter: CGPoint, visibleFrame: CGRect) {
        let bubbles = controller.bubbleSuggestions
        guard !bubbles.isEmpty else {
            if suggestionsPanel.isVisible { fadeOut(suggestionsPanel) }
            return
        }
        let layout = VaporGeometry.satelliteLayout(orbCenter: orbCenter, count: bubbles.count,
                                                   capsuleSize: VaporSuggestionsView.capsuleSize, visibleFrame: visibleFrame)
        suggestionsHost.rootView = VaporSuggestionsView(controller: controller, layout: layout)
        suggestionsPanel.setFrame(layout.windowFrame, display: true)
        if !suggestionsPanel.isVisible { fadeIn(suggestionsPanel) }
    }

    private func layoutCallout(orbCenter: CGPoint, visibleFrame: CGRect) {
        guard controller.callout != nil else {
            calloutPanel.orderOut(nil)
            return
        }
        let size = calloutHost.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        calloutPanel.setFrame(VaporGeometry.statusFrame(orbCenter: orbCenter, size: size, visibleFrame: visibleFrame),
                              display: true)
        calloutPanel.orderFrontRegardless()
    }

    /// The panel fades in; Phase 2 replaces this with a spring that grows out of the orb.
    private func fadeIn(_ window: NSWindow) {
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 1
        }
    }

    private func fadeOut(_ window: NSWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                // A show that started meanwhile wins.
                if window.alphaValue == 0 { window.orderOut(nil) }
            }
        }
    }

    /// Hides every window. They can be shown again.
    func hideAll() {
        [orbPanel, panel, suggestionsPanel, calloutPanel].forEach { $0.orderOut(nil) }
        panelShown = false
    }

    /// Hides and releases everything; call when Vapor turns off or DOKK quits.
    func tearDown() {
        hideAll()
        orbView.unregisterDraggedTypes()
        panel.contentView?.unregisterDraggedTypes()
        orbView.moved = nil
        orbView.moveEnded = nil
        orbView.makeMenu = nil
        orbView.clicked = nil
        orbView.hoverChanged = nil
        orbView.dragMoved = nil
        orbView.dropped = nil
        panelHost.intrinsicSizeChanged = nil
        calloutHost.intrinsicSizeChanged = nil
        [orbPanel, panel, suggestionsPanel, calloutPanel].forEach { $0.close() }
    }

    /// Click on the orb (without moving it).
    var orbClicked: (() -> Void)? {
        get { orbView.clicked }
        set { orbView.clicked = newValue }
    }
}
