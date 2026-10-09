import AppKit
import Quartz
import SwiftUI

/// Owns the Hub's window: its frames in both modes, the open, close, and detach transitions, and
/// the event monitors that exist only while the Hub is on screen.
///
/// ## Geometry
/// AppKit owns the window frame; SwiftUI draws the glass at ``HubShellState/layout`` inside it.
/// While anchored, the window is the glass plus ``shadowMargin`` on the three sides away from the
/// dock, so the glass's own shadow is not clipped; on the dock side it ends at the pointer tip, so
/// the transparent margin never covers dock tiles. While detached, the window is exactly the glass.
/// A detach or attach first grows the window to the union of the start and end frames, then
/// animates only the glass insets inside it, and settles the window on the end frame afterwards.
/// The glass therefore never jumps while two animation systems disagree about timing.
///
/// ## Monitors
/// Key-down events in the panel are offered to ``keyDown`` before any view sees them. Mouse-down
/// monitors exist only while anchored, to detect outside clicks. All monitors are installed on
/// show and removed on close; nothing here polls.
@MainActor
final class HubPanelController {
    /// Room for the glass's shadow around an anchored Hub.
    static let shadowMargin: CGFloat = 28

    private let panel: HubPanel
    private let state: HubShellState
    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var frameObservers: [NSObjectProtocol] = []
    /// Bumped by every show, close, and mode change, so a stale animation completion does nothing.
    private var generation = 0
    /// The anchored placement while anchored; nil while detached or hidden.
    private(set) var anchoredPlacement: HubAnchoredPlacement?

    /// True from ``show`` until the close animation has finished.
    private(set) var isVisible = false
    /// Key-down events while the panel is key. Returning true consumes the event.
    var keyDown: ((NSEvent) -> Bool)?
    /// A mouse-down outside an anchored Hub. The event is nil for clicks in other apps. Returning
    /// true consumes a local event so it does not reach the window under it.
    var outsideClick: ((NSEvent?) -> Bool)?
    /// The panel stopped being key.
    var resignedKey: (() -> Void)?
    /// The traffic-light close button.
    var closeRequested: (() -> Void)?
    /// The detached window moved or was resized by the person.
    var detachedFrameChanged: ((CGRect) -> Void)?

    /// - Parameter content: The Hub's root view. It is hosted for the app's lifetime and reads
    ///   `state` for its geometry and transitions.
    init<Content: View>(state: HubShellState, content: Content) {
        self.state = state
        panel = HubPanel(contentRect: .zero, styleMask: Self.anchoredStyle, backing: .buffered, defer: true)
        panel.title = String(localized: .hubTitle)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.minSize = HubStyle.minimumDetachedSize
        let hosting = HubHostingView(rootView: content)
        hosting.sizingOptions = []
        // The Hub draws its own header where a detached window's title bar and toolbar sit, so
        // SwiftUI must not see them as a safe area. Otherwise a ScrollView at the top of a tab
        // (the Apps tab's browse grid) extends itself up under the title bar, over the header,
        // and takes every click meant for the tab switcher, search, pin, and close buttons.
        hosting.safeAreaRegions = []
        panel.contentView = hosting
        applyAnchoredWindowStyle()
        panel.resignedKey = { [weak self] in self?.resignedKey?() }
        panel.closeRequested = { [weak self] in self?.closeRequested?() }
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            frameObservers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.reportDetachedFrame() }
            })
        }
        // AppKit re-tiles the title bar on every resize and key change, putting the traffic lights
        // back where it wants them; the Hub puts them back on its header right after.
        for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            frameObservers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.placeTrafficLights() }
            })
        }
    }

    /// The window, for focus checks and hit tests by the owner.
    var window: NSWindow { panel }

    /// The detached window's frame, or nil while anchored or hidden.
    var detachedFrame: CGRect? { state.isDetached && isVisible ? panel.frame : nil }

    // MARK: - Show and close

    /// Shows the Hub anchored above its tile and makes it key.
    func showAnchored(_ placement: HubAnchoredPlacement) {
        generation += 1
        anchoredPlacement = placement
        state.isDetached = false
        applyAnchoredWindowStyle()
        let (frame, layout) = Self.anchoredFrame(placement)
        state.layout = layout
        panel.setFrame(frame, display: false)
        present()
    }

    /// Shows the Hub as a detached window at `frame` and makes it key.
    func showDetached(_ frame: CGRect) {
        generation += 1
        anchoredPlacement = nil
        state.isDetached = true
        applyDetachedWindowStyle()
        state.layout = .detached
        panel.setFrame(frame, display: false)
        present()
        scheduleTrafficLightPlacement()
    }

    /// Follows the tile when the dock moves, resizes, or scrolls while anchored.
    func reanchor(_ placement: HubAnchoredPlacement) {
        guard isVisible, !state.isDetached, placement != anchoredPlacement else { return }
        anchoredPlacement = placement
        let (frame, layout) = Self.anchoredFrame(placement)
        state.layout = layout
        panel.setFrame(frame, display: true)
    }

    /// Brings a detached Hub to the front and makes it key, as a click on its tile does.
    func bringToFront() {
        guard isVisible else { return }
        ExplicitWindowPresenter.shared.present(panel)
    }

    /// Animates the Hub away and orders it out. `completion` runs once it is off screen, or right
    /// away when it was not visible.
    func close(completion: (() -> Void)? = nil) {
        guard isVisible else { completion?(); return }
        generation += 1
        let token = generation
        removeMonitors()
        ExplicitWindowPresenter.shared.cancel(panel)
        let finish = { [weak self] in
            guard let self, generation == token else { return }
            isVisible = false
            anchoredPlacement = nil
            panel.orderOut(nil)
            completion?()
        }
        // Reduce Motion: a short fade. Otherwise a quick ease-in toward the pointer.
        let animation: Animation = state.reduceMotion ? .easeOut(duration: 0.12) : .easeIn(duration: HubStyle.closeDuration)
        withAnimation(animation) { state.phase = .leaving } completion: { finish() }
    }

    /// Hides immediately, for display changes, sleep, and teardown.
    func closeImmediately() {
        guard isVisible else { return }
        generation += 1
        removeMonitors()
        ExplicitWindowPresenter.shared.cancel(panel)
        isVisible = false
        anchoredPlacement = nil
        state.phase = .entering
        panel.orderOut(nil)
    }

    private func present() {
        let token = generation
        isVisible = true
        state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        state.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        // Start from the entering pose with no animation, then spring to rest on the next turn of
        // the run loop, once SwiftUI has rendered the starting pose in the newly sized window.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { state.phase = .entering }
        installMonitors()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        // Opening is a deliberate request, so DOKK activates and the search field gets a normal
        // field editor. Hover never reaches this path.
        ExplicitWindowPresenter.shared.present(panel)
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == token else { return }
            let animation: Animation = state.reduceMotion ? .easeOut(duration: 0.15) : HubStyle.motion
            withAnimation(animation) { self.state.phase = .shown }
        }
    }

    // MARK: - Detach and attach

    /// Morphs the anchored panel into a titled window at `frame`.
    func detach(to frame: CGRect) {
        guard isVisible, !state.isDetached else { return }
        generation += 1
        let token = generation
        let start = panel.frame
        anchoredPlacement = nil
        state.isDetached = true
        removeMouseMonitors()
        morph(from: start, startLayout: state.layout, to: frame, endLayout: .detached, token: token) { [weak self] in
            self?.applyDetachedWindowStyle()
            self?.panel.setFrame(frame, display: true)
            self?.scheduleTrafficLightPlacement()
        }
    }

    /// Morphs the detached window back into a panel anchored at `placement`.
    func attach(to placement: HubAnchoredPlacement) {
        guard isVisible, state.isDetached else { return }
        generation += 1
        let token = generation
        let start = panel.frame
        anchoredPlacement = placement
        state.isDetached = false
        // Drop the title bar first, so the traffic lights do not ride along with the morph.
        applyAnchoredWindowStyle()
        panel.setFrame(start, display: false)
        let (end, endLayout) = Self.anchoredFrame(placement)
        morph(from: start, startLayout: .detached, to: end, endLayout: endLayout, token: token) { [weak self] in
            self?.installMouseMonitors()
        }
    }

    /// Grows the window to cover both frames, then animates the glass from one to the other.
    ///
    /// `startLayout` and `endLayout` are relative to `start` and `end`; they are re-expressed
    /// relative to the union window so the glass keeps its screen position at both ends.
    private func morph(from start: CGRect, startLayout: HubBodyLayout, to end: CGRect, endLayout: HubBodyLayout,
                       token: Int, settle: @escaping () -> Void) {
        let union = start.union(end)
        var from = startLayout
        from.insets = Self.insets(of: Self.glass(in: start, insets: startLayout.insets), in: union)
        var to = endLayout
        to.insets = Self.insets(of: Self.glass(in: end, insets: endLayout.insets), in: union)
        let finish = { [weak self] in
            guard let self, generation == token else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { self.state.layout = endLayout }
            panel.setFrame(end, display: true)
            settle()
        }
        guard !state.reduceMotion else {
            finish()
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { state.layout = from }
        panel.setFrame(union, display: true)
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == token else { return }
            withAnimation(HubStyle.motion) { self.state.layout = to } completion: { finish() }
        }
    }

    // MARK: - Window styles

    private static let anchoredStyle: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]
    private static let detachedStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable,
                                                             .nonactivatingPanel, .fullSizeContentView]

    private func applyAnchoredWindowStyle() {
        panel.styleMask = Self.anchoredStyle
        panel.toolbar = nil
        // Above ordinary windows and the dock; menus and Quick Look still order above it.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = false
        panel.isMovable = false
    }

    private func applyDetachedWindowStyle() {
        panel.styleMask = Self.detachedStyle
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // An empty unified toolbar makes the transparent title bar 52 points tall. That is what
        // lets ``placeTrafficLights()`` move the buttons onto the 58-point header while they stay
        // inside the title bar's hit region; a bare 28-point title bar would clip their clicks.
        // Content under a transparent title bar receives its own clicks; the header's drag
        // gesture (see `HubHeaderView`) moves the window from the rest of the header.
        let toolbar = NSToolbar(identifier: "hub.detached")
        toolbar.allowsUserCustomization = false
        panel.toolbar = toolbar
        panel.toolbarStyle = .unified
        panel.titlebarSeparatorStyle = .none
        panel.level = .normal
        panel.collectionBehavior = [.managed, .participatesInCycle, .fullScreenNone]
        panel.isMovable = true
        panel.hasShadow = true
        panel.invalidateShadow()
    }

    // MARK: - Traffic lights

    /// Where the mockup's header puts the close button: 20 points in, then 8-point gaps.
    private static let trafficLightLeading: CGFloat = 20
    private static let trafficLightPitch: CGFloat = 20

    /// Moves the standard window buttons onto the Hub's header: the close button 20 points from
    /// the leading edge, 8-point gaps, all centered on the 58-point header, left of the wordmark.
    ///
    /// AppKit tiles the buttons for its own 52-point title bar (3 points too high for the header)
    /// on each resize and key change; this runs after each of those. No-op while anchored.
    private func placeTrafficLights() {
        guard state.isDetached, panel.styleMask.contains(.titled) else { return }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        // Window coordinates: origin at the window's bottom-left, y up.
        let centerY = panel.frame.height - HubStyle.headerHeight / 2
        for (index, type) in buttons.enumerated() {
            guard let button = panel.standardWindowButton(type), let superview = button.superview else { continue }
            let size = button.frame.size
            let centerX = Self.trafficLightLeading + size.width / 2 + CGFloat(index) * Self.trafficLightPitch
            let center = superview.convert(NSPoint(x: centerX, y: centerY), from: nil)
            let origin = NSPoint(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded())
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }

    /// Places the lights now and again on the next turn, once AppKit has created and tiled the
    /// buttons for a freshly titled window.
    private func scheduleTrafficLightPlacement() {
        placeTrafficLights()
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == token else { return }
            placeTrafficLights()
        }
    }

    // MARK: - Monitors

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === panel else { return event }
            return keyDown?(event) == true ? nil : event
        }
        if !state.isDetached { installMouseMonitors() }
    }

    private func installMouseMonitors() {
        removeMouseMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            if belongsToHub(event) { return event }
            return outsideClick?(event) == true ? nil : event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            _ = self?.outsideClick?(nil)
        }
    }

    private func removeMouseMonitors() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        removeMouseMonitors()
    }

    /// Clicks on the glass, on a sheet or child window of the Hub, or on Quick Look belong to the
    /// Hub. A click on the transparent shadow margin does not.
    private func belongsToHub(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        if window === panel {
            let bounds = panel.contentView?.bounds ?? .zero
            // The content view is flipped (top-left origin); window coordinates start at the bottom left.
            let point = CGPoint(x: event.locationInWindow.x, y: bounds.height - event.locationInWindow.y)
            return Self.glass(in: CGRect(origin: .zero, size: bounds.size), insets: state.layout.insets,
                              flipped: true).contains(point)
        }
        return window.sheetParent === panel || window.parent === panel || window is QLPreviewPanel
    }

    private func reportDetachedFrame() {
        guard isVisible, state.isDetached, panel.styleMask.contains(.titled) else { return }
        detachedFrameChanged?(panel.frame)
    }

    /// Removes monitors and observers. The controller must not be used afterwards.
    func stop() {
        closeImmediately()
        frameObservers.forEach { NotificationCenter.default.removeObserver($0) }
        frameObservers.removeAll()
        keyDown = nil; outsideClick = nil; resignedKey = nil; closeRequested = nil; detachedFrameChanged = nil
        panel.resignedKey = nil
        panel.closeRequested = nil
        panel.contentView = nil
    }

    // MARK: - Frame math

    /// The window frame and glass layout for an anchored placement, in screen coordinates.
    static func anchoredFrame(_ placement: HubAnchoredPlacement) -> (CGRect, HubBodyLayout) {
        let depth = HubStyle.pointerSize.height
        let margin = shadowMargin
        let body = placement.body
        // Glass = body plus the pointer strip on the dock side. Window = glass plus the margin on
        // the other three sides. Screen space is y-up, so "top" is maxY.
        let insets: EdgeInsets
        let window: CGRect
        switch placement.edge {
        case .bottom:
            window = CGRect(x: body.minX - margin, y: body.minY - depth,
                            width: body.width + margin * 2, height: body.height + depth + margin)
            insets = EdgeInsets(top: margin, leading: margin, bottom: 0, trailing: margin)
        case .top:
            window = CGRect(x: body.minX - margin, y: body.minY - margin,
                            width: body.width + margin * 2, height: body.height + depth + margin)
            insets = EdgeInsets(top: 0, leading: margin, bottom: margin, trailing: margin)
        case .left:
            window = CGRect(x: body.minX - depth, y: body.minY - margin,
                            width: body.width + depth + margin, height: body.height + margin * 2)
            insets = EdgeInsets(top: margin, leading: 0, bottom: margin, trailing: margin)
        case .right:
            window = CGRect(x: body.minX - margin, y: body.minY - margin,
                            width: body.width + depth + margin, height: body.height + margin * 2)
            insets = EdgeInsets(top: margin, leading: margin, bottom: margin, trailing: 0)
        }
        let layout = HubBodyLayout(insets: insets, edge: placement.edge, pointerOffset: placement.pointerOffset,
                                   pointerDepth: depth, cornerRadius: HubStyle.anchoredCornerRadius)
        return (window, layout)
    }

    /// The glass rectangle (body plus pointer strip) inside `frame`, in the same space as `frame`.
    ///
    /// - Parameter flipped: Whether `frame` is in a top-left, y-down space. Screen frames are not.
    static func glass(in frame: CGRect, insets: EdgeInsets, flipped: Bool = false) -> CGRect {
        let width = max(0, frame.width - insets.leading - insets.trailing)
        let height = max(0, frame.height - insets.top - insets.bottom)
        let y = flipped ? frame.minY + insets.top : frame.minY + insets.bottom
        return CGRect(x: frame.minX + insets.leading, y: y, width: width, height: height)
    }

    /// Insets that place the screen rectangle `glass` inside the screen rectangle `window`.
    static func insets(of glass: CGRect, in window: CGRect) -> EdgeInsets {
        EdgeInsets(top: window.maxY - glass.maxY, leading: glass.minX - window.minX,
                   bottom: glass.minY - window.minY, trailing: window.maxX - glass.maxX)
    }
}
