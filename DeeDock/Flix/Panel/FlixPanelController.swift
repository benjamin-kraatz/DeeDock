import AppKit
import QuickLookUI
import SwiftUI

/// The Flix panel's borderless key window.
private final class FlixPanelWindow: NSPanel {
    var resignedKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() {
        super.resignKey()
        resignedKey?()
    }
    /// Escape that no view consumed. The key monitor handles Escape first; this keeps AppKit quiet.
    override func cancelOperation(_ sender: Any?) {}
}

/// Hosts the panel's SwiftUI content and answers Quick Look's responder-chain question.
private final class FlixHostingView<Content: View>: NSHostingView<Content> {
    weak var quickLook: FlixQuickLook?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { quickLook != nil }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { quickLook?.begin(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { quickLook?.end(panel) }
}

/// Owns the Flix panel window: its placement in both modes, the open and close transitions, stepping
/// aside during a drag out, and the monitors that exist only while it is on screen.
///
/// Opening is always a deliberate request (a click, the shortcut, the menu bar, a Discovery tip),
/// so the panel activates DOKK through `ExplicitWindowPresenter` and becomes key: arrows, Return,
/// and type-to-search work at once. Hover never reaches this path. Outside clicks, Escape, and
/// another app becoming active close it, except while a drag out is in flight or Quick Look is up.
@MainActor
final class FlixPanelController {
    private let window: FlixPanelWindow
    private let state: FlixPanelState
    let quickLook = FlixQuickLook()
    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var generation = 0
    private(set) var isVisible = false
    /// The body frame on screen, without the shadow margin.
    private(set) var bodyFrame: CGRect = .zero

    /// A click outside the panel. Returns true to consume a click in one of DOKK's windows.
    var outsideClick: ((NSEvent?) -> Bool)?
    /// DOKK stopped being the active app while the panel was open.
    var applicationResigned: (() -> Void)?
    /// The open or close animation finished, with the panel's visibility afterwards.
    var visibilityChanged: ((Bool) -> Void)?
    /// A mouse button went down inside the panel (for `keyboard_only`).
    var pointerPressed: (() -> Void)?
    /// The panel's first frame after ``show(body:growth:)`` is on screen: the turn after SwiftUI drew
    /// the entering pose in the newly sized window.
    var firstFrame: (() -> Void)?

    init<Content: View>(state: FlixPanelState, content: Content) {
        self.state = state
        window = FlixPanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        window.title = String(localized: .flixName)
        let hosting = FlixHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.quickLook = quickLook
        window.contentView = hosting
        // Escape belongs to Quick Look while it is key: it closes the preview, not the panel.
        quickLook.handleKey = { [weak state] event in
            event.keyCode == 53 ? false : state?.handleKey(event) ?? false
        }
    }

    var nsWindow: NSWindow { window }

    /// Whether a screen point is over the panel body.
    func contains(_ point: CGPoint) -> Bool { isVisible && bodyFrame.contains(point) }

    // MARK: Show and close

    /// Places the panel's body at `body` and springs it open from `growth`.
    func show(body: CGRect, growth: FlixGrowthAnchor) {
        generation += 1
        let token = generation
        bodyFrame = body
        state.growthAnchor = growth
        window.setFrame(FlixPanelGeometry.window(around: body), display: false)
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { state.phase = .entering }
        isVisible = true
        installMonitors()
        window.orderFrontRegardless()
        ExplicitWindowPresenter.shared.present(window)
        // Spring from the entering pose once SwiftUI has drawn it in the newly sized window.
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == token else { return }
            firstFrame?()
            withAnimation(FlixMotion.resolved(FlixMotion.panel, reduceMotion: state.reduceMotion)) {
                self.state.phase = .shown
            }
        }
        visibilityChanged?(true)
    }

    /// Follows the tile when the dock moves while the panel is anchored.
    func reanchor(body: CGRect, growth: FlixGrowthAnchor) {
        guard isVisible, body != bodyFrame else { return }
        bodyFrame = body
        state.growthAnchor = growth
        window.setFrame(FlixPanelGeometry.window(around: body), display: true)
    }

    /// Animates away and orders out. `completion` runs once it is off screen.
    ///
    /// The window lets clicks through from the moment it starts leaving, and orders out when the
    /// fade's completion runs or, at the latest, shortly after the fade's duration. SwiftUI does
    /// not always run an animation's completion, and a window left on screen at zero opacity
    /// swallows every click over where the panel was.
    func close(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard isVisible else { completion?(); return }
        generation += 1
        let token = generation
        removeMonitors()
        quickLook.close()
        ExplicitWindowPresenter.shared.cancel(window)
        isVisible = false
        window.ignoresMouseEvents = true
        var finished = false
        let finish = { [weak self] in
            guard let self, generation == token, !finished else { return }
            finished = true
            window.orderOut(nil)
            window.alphaValue = 1
            window.ignoresMouseEvents = false
            completion?()
        }
        visibilityChanged?(false)
        guard animated else { finish(); return }
        let duration = state.reduceMotion ? 0.12 : 0.16
        let animation: Animation = state.reduceMotion ? .easeOut(duration: duration) : .easeIn(duration: duration)
        withAnimation(animation) { state.phase = .leaving } completion: { finish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.15) { finish() }
    }

    /// Fades the panel to a ghost and lets the pointer through while a drag is outside it, so the
    /// window underneath can take the drop; brings it back when the drag returns.
    func stepAside(_ outside: Bool) {
        guard isVisible else { return }
        window.ignoresMouseEvents = outside
        let target: CGFloat = outside ? 0.06 : 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = state.reduceMotion ? 0.12 : 0.2
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)
            window.animator().alphaValue = target
        }
    }

    func toggleQuickLook(_ urls: [URL]) { quickLook.toggle(urls, from: window) }

    // MARK: Monitors

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === window else { return event }
            return state.handleKey(event) ? nil : event
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            if belongsToPanel(event) {
                pointerPressed?()
                return event
            }
            return outsideClick?(event) == true ? nil : event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            _ = self?.outsideClick?(nil)
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationResigned?() }
        }
    }

    private func removeMonitors() {
        [keyMonitor, localMouseMonitor, globalMouseMonitor].compactMap(\.self).forEach(NSEvent.removeMonitor)
        keyMonitor = nil; localMouseMonitor = nil; globalMouseMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    /// Clicks inside the body, on Quick Look, or on a menu or sheet of the panel belong to it. A
    /// click on the transparent shadow margin does not.
    private func belongsToPanel(_ event: NSEvent) -> Bool {
        guard let eventWindow = event.window else { return false }
        if eventWindow === window {
            return bodyFrame.contains(window.convertPoint(toScreen: event.locationInWindow))
        }
        return eventWindow is QLPreviewPanel || eventWindow.parent === window || eventWindow.sheetParent === window
            || eventWindow.className.contains("Menu")
    }

    /// Closes immediately and releases the window's content. The controller must not be used after.
    func stop() {
        close(animated: false)
        outsideClick = nil; applicationResigned = nil; visibilityChanged = nil; pointerPressed = nil; firstFrame = nil
        window.resignedKey = nil
        window.contentView = nil
    }
}
