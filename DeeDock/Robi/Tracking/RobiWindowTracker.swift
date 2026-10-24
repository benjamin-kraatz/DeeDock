import AppKit
import ApplicationServices
import Carbon

/// Follows the frontmost app's focused standard window, the one Robi sits on.
///
/// Focus changes come from `NSWorkspace` and an AX observer on the frontmost app. Geometry comes
/// from three sources, each covering what the others cannot:
/// - **Title-bar drags** are predicted from global mouse events (`RobiDragPrediction`), which keeps
///   the tab on the window instead of a frame behind it.
/// - **Other moves and resizes** (edge drags, tiling, window managers) come from window-server
///   notifications (`RobiWindowServerEvents`) where that private interface is available.
/// - **AX moved/resized notifications** are the public fallback, at about 10 Hz during live drags.
///
/// Every observer, monitor and subscription is removed in `stop()`.
@MainActor
final class RobiWindowTracker {
    /// The window changed, including to none.
    var targetChanged: ((RobiWindowTarget?) -> Void)?
    /// The current window moved or resized. Global top-left points.
    var frameChanged: ((CGRect) -> Void)?
    /// Apps the person excluded in Settings, by bundle identifier.
    var excludedBundleIdentifiers: Set<String> = [] { didSet { if oldValue != excludedBundleIdentifiers { scheduleRefresh() } } }
    /// While true, focus changes are not followed. Robi pins the target during selection and
    /// answering so its own key panel never retargets it.
    var isPinned = false
    /// While pinned, called when the person moved to a different window or app, or the window
    /// went away, so the interaction can end or be set aside and the tracker can follow them.
    var leftWhilePinned: ((Departure) -> Void)?

    /// Why a pinned interaction lost its window.
    enum Departure {
        /// Focus moved to another window, another app, or something Robi does not sit on.
        /// The window is still there and can come back.
        case switchedAway
        /// The window closed or was minimized.
        case windowGone
    }

    private(set) var target: RobiWindowTarget?
    private(set) var window: AXUIElement?

    private var observer: AXObserver?
    private var observedApplication: AXUIElement?
    private var observedProcess: pid_t?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var appTokens: [NSObjectProtocol] = []
    private var monitors: [Any] = []
    private let serverEvents = RobiWindowServerEvents()
    private var drag: RobiDragPrediction?
    /// True once a drag since the last mouse-down moved the tab by prediction, so mouse-up
    /// reconciles with the real frame even if the prediction was abandoned on the way.
    private var predictedSinceMouseDown = false
    private var refreshPending = false
    private var running = false

    /// Windows of these apps are system UI, never something to help with.
    private static let systemBundles: Set<String> = [
        "com.apple.dock", "com.apple.loginwindow", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.Spotlight", "com.apple.WindowManager", "com.apple.screencaptureui", "com.apple.SecurityAgent",
        "com.apple.systemuiserver", "com.apple.ScreenSaver.Engine", "com.apple.UserNotificationCenter",
    ]
    private static let windowNotifications = [kAXMovedNotification, kAXResizedNotification,
                                              kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification]
    private static let applicationNotifications = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                                                   kAXFocusedUIElementChangedNotification, kAXWindowCreatedNotification]

    func start() {
        guard !running else { return }
        running = true
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceTokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        appTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        })
        serverEvents.changed = { [weak self] in self?.windowServerChanged() }
        serverEvents.start()
        installDragMonitors()
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        workspaceTokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        appTokens.forEach(NotificationCenter.default.removeObserver)
        workspaceTokens = []; appTokens = []
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        serverEvents.stop()
        drag = nil
        unobserveApplication()
        setTarget(nil, window: nil)
    }

    /// Coalesces bursts of notifications into one AX read on the next main-loop turn, and never
    /// queries AX from inside an AX callback.
    func scheduleRefresh() {
        guard running, !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            refreshPending = false
            refresh()
        }
    }

    func refresh() {
        guard running else { return }
        guard AXIsProcessTrusted(), let application = NSWorkspace.shared.frontmostApplication else {
            return clear()
        }
        let pid = application.processIdentifier
        // DOKK itself coming forward (its Settings, say) never ends an interaction.
        if isPinned && pid == ProcessInfo.processInfo.processIdentifier { return }
        if pid == ProcessInfo.processInfo.processIdentifier || application.activationPolicy != .regular
            || application.bundleIdentifier.map({ Self.systemBundles.contains($0) || excludedBundleIdentifiers.contains($0) }) == true {
            return clear()
        }
        if isPinned {
            // Only a different app or a different focused window ends the interaction. Focus moving
            // between controls inside the same window, or to Robi's own panel, does not.
            guard pid == target?.processIdentifier else { return clear() }
            let axApplication = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApplication, 0.15)
            if let focused = RobiAX.element(axApplication, kAXFocusedWindowAttribute), !Self.same(focused, window) {
                leftWhilePinned?(.switchedAway)
            }
            return
        }
        if observedProcess != pid { observeApplication(pid) }
        let axApplication = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApplication, 0.15)
        guard !Self.isInSecureField(axApplication),
              let focused = RobiAX.element(axApplication, kAXFocusedWindowAttribute),
              (RobiAX.value(focused, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole as String,
              (RobiAX.value(focused, kAXMinimizedAttribute) as? Bool) != true,
              let axFrame = RobiAX.frame(of: focused),
              let windowID = RobiWindowServer.windowID(of: focused, processIdentifier: pid, frame: axFrame)
        else { return setTarget(nil, window: nil) }
        let frame = RobiWindowServer.bounds(of: windowID) ?? axFrame
        guard RobiLayout.accepts(windowSize: frame.size) else { return setTarget(nil, window: nil) }
        let next = RobiWindowTarget(processIdentifier: pid, windowID: windowID, frame: frame,
                                    applicationName: application.localizedName ?? "",
                                    bundleIdentifier: application.bundleIdentifier,
                                    isFullScreen: (RobiAX.value(focused, "AXFullScreen") as? Bool) == true)
        setTarget(next, window: focused)
    }

    // MARK: Target

    /// No window to follow: ends a pinned interaction, otherwise clears the target.
    private func clear() {
        if isPinned { leftWhilePinned?(.switchedAway) } else { setTarget(nil, window: nil) }
    }

    private func setTarget(_ next: RobiWindowTarget?, window nextWindow: AXUIElement?) {
        if !Self.same(window, nextWindow) {
            if let observer, let window {
                for name in Self.windowNotifications { AXObserverRemoveNotification(observer, window, name as CFString) }
            }
            if let observer, let nextWindow {
                for name in Self.windowNotifications {
                    AXObserverAddNotification(observer, nextWindow, name as CFString, Unmanaged.passUnretained(self).toOpaque())
                }
            }
            window = nextWindow
        }
        let previous = target
        target = next
        if previous?.windowID != next?.windowID { serverEvents.watch(next?.windowID) }
        if previous?.windowID != next?.windowID || previous?.processIdentifier != next?.processIdentifier
            || previous?.isFullScreen != next?.isFullScreen {
            drag = nil
            targetChanged?(next)
        } else if let next, previous?.frame != next.frame {
            frameChanged?(next.frame)
        }
    }

    private static func same(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): CFEqual(a, b)
        default: false
        }
    }

    private func windowMoved() {
        guard var current = target else { return }
        guard let frame = RobiWindowServer.bounds(of: current.windowID) else { return scheduleRefresh() }
        guard frame != current.frame else { return }
        current.frame = frame
        target = current
        frameChanged?(frame)
    }

    private func windowServerChanged() {
        // A predicted title-bar drag owns the geometry until the mouse goes up.
        guard drag == nil else { return }
        windowMoved()
    }

    // MARK: AX observation

    private func observeApplication(_ pid: pid_t) {
        unobserveApplication()
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, notification, context in
            guard let context else { return }
            let name = notification as String
            MainActor.assumeIsolated {
                let tracker = Unmanaged<RobiWindowTracker>.fromOpaque(context).takeUnretainedValue()
                tracker.handle(name)
            }
        }, &created) == .success, let created else { return }
        observedProcess = pid
        observer = created
        let element = AXUIElementCreateApplication(pid)
        observedApplication = element
        for name in Self.applicationNotifications {
            AXObserverAddNotification(created, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    /// Removes the run-loop source before the unretained callback context can go away.
    private func unobserveApplication() {
        if let observer {
            if let window {
                for name in Self.windowNotifications { AXObserverRemoveNotification(observer, window, name as CFString) }
            }
            if let observedApplication {
                for name in Self.applicationNotifications { AXObserverRemoveNotification(observer, observedApplication, name as CFString) }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedApplication = nil
        observedProcess = nil
        window = nil
    }

    private func handle(_ notification: String) {
        switch notification {
        case kAXMovedNotification, kAXResizedNotification:
            // Late and throttled during live drags; only the fallback when SkyLight is missing.
            if drag == nil, !serverEvents.isAvailable { windowMoved() }
        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            // Registered on the target window only: it closed or went to the Dock. A pinned
            // interaction has nothing left to answer about, so it ends before following focus.
            if isPinned { leftWhilePinned?(.windowGone) } else { scheduleRefresh() }
        default:
            scheduleRefresh()
        }
    }

    private static func isInSecureField(_ application: AXUIElement) -> Bool {
        if IsSecureEventInputEnabled() { return true }
        guard let focused = RobiAX.element(application, kAXFocusedUIElementAttribute) else { return false }
        return (RobiAX.value(focused, kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole as String
    }

    // MARK: Drag prediction

    private func installDragMonitors() {
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }
        monitors = [down, dragged, up].compactMap { $0 }
    }

    private func pointer() -> CGPoint { RobiScreenSpace.current.topLeftPoint(fromAppKit: NSEvent.mouseLocation) }

    private func mouseDown() {
        predictedSinceMouseDown = false
        guard let target, !target.isFullScreen else { drag = nil; return }
        drag = RobiDragPrediction(pointer: pointer(), frame: target.frame)
    }

    private func mouseDragged() {
        guard var prediction = drag, let current = target else { return }
        let point = pointer()
        let predicted = prediction.frame(pointer: point, topLimit: RobiScreenSpace.current.topLimit(at: point))
        if prediction.events == RobiDragPrediction.verificationEvents {
            let actual = RobiWindowServer.bounds(of: current.windowID)
            if prediction.isStalled(actual: actual) {
                // Not a window drag after all: put the tab back where the window really is.
                drag = nil
                frameChanged?(actual ?? current.frame)
                return
            }
        }
        drag = prediction
        predictedSinceMouseDown = true
        frameChanged?(predicted)
    }

    private func mouseUp() {
        guard drag != nil || predictedSinceMouseDown else { return }
        drag = nil
        predictedSinceMouseDown = false
        // Reconcile with where the window server really put it (tiling can snap it elsewhere).
        if let current = target, let frame = RobiWindowServer.bounds(of: current.windowID) {
            var updated = current
            updated.frame = frame
            target = updated
            frameChanged?(frame)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.windowMoved() }
    }
}

/// Small typed readers over the AX C API.
nonisolated enum RobiAX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    /// The selected character range of a text element, if it reports one.
    static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value = value(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    /// The text of a character range of a text element.
    static func string(of element: AXUIElement, in range: CFRange) -> String? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                         parameter, &result) == .success else { return nil }
        return result as? String
    }

    /// Position and size of an AX element in global top-left points.
    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent),
              origin.x.isFinite, origin.y.isFinite, extent.width > 1, extent.height > 1 else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
