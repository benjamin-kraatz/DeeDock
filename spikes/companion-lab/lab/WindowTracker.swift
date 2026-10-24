import AppKit
import ApplicationServices

/// Follows the frontmost app's focused standard window.
///
/// Focus changes come from NSWorkspace plus an AX observer on the frontmost app. Live moves and
/// resizes come from SkyLight 806/807 (`LAB_TRACKING=sls`, default), AX moved/resized only
/// (`LAB_TRACKING=ax`), or a 120 Hz poll while a mouse button is down (`LAB_TRACKING=poll`).
@MainActor
final class WindowTracker {
    struct Target: Equatable {
        let pid: pid_t
        let windowID: CGWindowID
        var frame: CGRect          // top-left global points
        let appName: String
        let bundleID: String?
        let isFullScreen: Bool
    }

    enum Mode: String { case sls, ax, poll, predict }
    let mode = Mode(rawValue: ProcessInfo.processInfo.environment["LAB_TRACKING"] ?? "") ?? .predict

    var onTarget: ((Target?) -> Void)?
    var onFrame: ((CGRect) -> Void)?
    private(set) var target: Target?
    private(set) var targetElement: AXUIElement?
    /// While the companion owns a modal interaction, focus moves to our own panels must not retarget.
    var isPinned = false

    private var appObserver: AXObserver?
    private var observedPID: pid_t?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var mouseMonitors: [Any] = []
    private var counts = (sls: 0, ax: 0, poll: 0)
    private var countReset = Date()
    nonisolated(unsafe) static weak var shared: WindowTracker?

    private static let excludedBundles: Set<String> = ["com.apple.dock", "com.apple.loginwindow", "com.apple.controlcenter",
                                                       "com.apple.notificationcenterui", "com.apple.Spotlight", "com.apple.WindowManager"]

    func start() {
        WindowTracker.shared = self
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        if mode == .sls || mode == .predict, let cid = SkyLight.mainConnection?(), let register = SkyLight.registerConnectionNotify {
            for event in [SkyLight.windowMoved, SkyLight.windowResized] {
                _ = register(cid, { _, _, _, _, _ in
                    // Delivered on the main run loop by the window-server event port.
                    MainActor.assumeIsolated { WindowTracker.shared?.windowServerChanged(source: "sls") }
                }, event, nil)
            }
        }
        if mode == .poll {
            mouseMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.startPolling() }
            } as Any)
            mouseMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopPolling() }
            } as Any)
        }
        if mode == .predict { installPrediction() }
        lab("tracking mode: \(mode.rawValue)")
        refresh()
    }

    func refresh() {
        guard !isPinned else { return }
        let env = ProcessInfo.processInfo.environment
        let forced = env["LAB_TARGET_BUNDLE"].flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
            ?? env["LAB_TARGET_PID"].flatMap { pid_t($0) }.flatMap { NSRunningApplication(processIdentifier: $0) }
        guard let app = forced ?? NSWorkspace.shared.frontmostApplication else { return setTarget(nil, element: nil) }
        if app.processIdentifier == getpid() { return }
        if let bundle = app.bundleIdentifier, Self.excludedBundles.contains(bundle) { return setTarget(nil, element: nil) }
        if observedPID != app.processIdentifier { observeApp(app.processIdentifier) }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.15)
        guard let window = AX.element(axApp, kAXFocusedWindowAttribute) ?? (AX.copy(axApp, kAXWindowsAttribute) as? [AXUIElement])?.first,
              (AX.copy(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole as String,
              (AX.copy(window, kAXMinimizedAttribute) as? Bool) != true else { return setTarget(nil, element: nil) }
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &id) == .success, id != 0,
              let frame = windowServerBounds(id), frame.width >= 240, frame.height >= 140 else { return setTarget(nil, element: nil) }
        let fullScreen = (AX.copy(window, "AXFullScreen") as? Bool) == true
        setTarget(Target(pid: app.processIdentifier, windowID: id, frame: frame, appName: app.localizedName ?? "App",
                         bundleID: app.bundleIdentifier, isFullScreen: fullScreen), element: window)
    }

    private func setTarget(_ next: Target?, element: AXUIElement?) {
        if let old = targetElement, let observer = appObserver {
            for name in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification] {
                AXObserverRemoveNotification(observer, old, name as CFString)
            }
        }
        targetElement = element
        if let element, let observer = appObserver {
            for name in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification] {
                AXObserverAddNotification(observer, element, name as CFString, nil)
            }
        }
        guard next != target else { return }
        let windowChanged = next?.windowID != target?.windowID
        target = next
        if windowChanged, var id = next?.windowID, mode == .sls || mode == .predict, let cid = SkyLight.mainConnection?() {
            _ = SkyLight.requestNotifications?(cid, &id, 1)
        }
        onTarget?(next)
    }

    private func observeApp(_ pid: pid_t) {
        if let observer = appObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        appObserver = nil
        observedPID = pid
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, notification, _ in
            let name = notification as String
            MainActor.assumeIsolated {
                guard let tracker = WindowTracker.shared else { return }
                if name == kAXMovedNotification || name == kAXResizedNotification {
                    tracker.windowServerChanged(source: "ax")
                } else {
                    DispatchQueue.main.async { tracker.refresh() }
                }
            }
        }, &created) == .success, let created else { return }
        appObserver = created
        let element = AXUIElementCreateApplication(pid)
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXWindowCreatedNotification] {
            AXObserverAddNotification(created, element, name as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    func windowServerChanged(source: String) {
        switch source { case "sls": counts.sls += 1; case "ax": counts.ax += 1; default: counts.poll += 1 }
        if Date().timeIntervalSince(countReset) > 1 {
            if counts.sls + counts.ax + counts.poll > 3 { lab("updates/s  sls=\(counts.sls) ax=\(counts.ax) poll=\(counts.poll)") }
            counts = (0, 0, 0); countReset = Date()
        }
        // In sls mode AX callbacks only confirm; the window server already told us.
        if (mode == .sls || mode == .predict) && source == "ax" { return }
        if mode == .predict && source == "sls" && dragOrigin != nil { return }   // prediction owns live drags
        if mode == .ax && source != "ax" { return }
        guard var current = target, let frame = windowServerBounds(current.windowID), frame != current.frame else { return }
        current.frame = frame
        target = current
        onFrame?(frame)
    }

    /// Moves the tab from the same drag events the window server uses to move the window, then
    /// reconciles with real bounds on mouse-up. Only for drags that start in the title-bar band.
    private var dragOrigin: NSPoint?
    private var frameAtDown: CGRect?
    private var dragEvents = 0
    private func installPrediction() {
        mouseMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let target = self.target else { return }
                let mouse = NSEvent.mouseLocation
                let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                let cgY = primaryHeight - mouse.y
                let inTitleBand = mouse.x >= target.frame.minX && mouse.x <= target.frame.maxX && cgY >= target.frame.minY && cgY <= target.frame.minY + 40
                self.dragOrigin = inTitleBand ? mouse : nil
                self.dragEvents = 0
                self.frameAtDown = inTitleBand ? target.frame : nil
            }
        } as Any)
        mouseMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let origin = self.dragOrigin, let frame = self.frameAtDown else { return }
                let mouse = NSEvent.mouseLocation
                self.counts.poll += 1
                self.dragEvents += 1
                // A title-bar drag that does not move the window (tab tear-off, toolbar control): stop predicting.
                if self.dragEvents == 4, let current = self.target, windowServerBounds(current.windowID) == frame {
                    self.dragOrigin = nil
                    self.onFrame?(frame)
                    return
                }
                self.onFrame?(frame.offsetBy(dx: mouse.x - origin.x, dy: -(mouse.y - origin.y)))
            }
        } as Any)
        mouseMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dragOrigin = nil
                self.frameAtDown = nil
                if var current = self.target, let real = windowServerBounds(current.windowID) { current.frame = real; self.target = current; self.onFrame?(real) }
            }
        } as Any)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { _ in
            MainActor.assumeIsolated { WindowTracker.shared?.windowServerChanged(source: "poll") }
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        windowServerChanged(source: "poll")
    }
}
