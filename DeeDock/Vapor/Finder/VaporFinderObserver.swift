import AppKit
import ApplicationServices

/// Tells Vapor when the folder in Finder's front window may have changed.
///
/// It listens for Finder becoming active. While Finder stays active and DOKK has Accessibility
/// trust, an `AXObserver` on Finder's process adds focused-window, main-window and title changes;
/// a window's title follows folder navigation. Every signal is debounced by 250 ms. Without trust
/// Vapor reads only on activation.
///
/// Ownership: `start()` installs the workspace observers, `stop()` removes them and the AX
/// observer and cancels a pending debounce. The AX callback context is this object, unretained,
/// so the AX observer is always removed before the object goes away.
@MainActor
final class VaporFinderObserver {
    /// Called on the main actor after the debounce, while Finder is frontmost.
    var changed: (() -> Void)?
    /// Called when Finder stops being the frontmost app.
    var finderResigned: (() -> Void)?

    static let debounce: Duration = .milliseconds(250)
    private static let notifications = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                                        kAXTitleChangedNotification]

    private var workspaceObservers: [NSObjectProtocol] = []
    private var axObserver: AXObserver?
    private var axApplication: AXUIElement?
    private var debounceTask: Task<Void, Never>?

    /// Whether Finder is the frontmost app right now.
    var isFinderFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == VaporFinderReader.finderBundleIdentifier
    }

    func start() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            let isFinder = app?.bundleIdentifier == VaporFinderReader.finderBundleIdentifier
            MainActor.assumeIsolated { self?.applicationActivated(isFinder: isFinder, pid: pid) }
        })
        if let finder = NSWorkspace.shared.frontmostApplication, isFinderFrontmost {
            applicationActivated(isFinder: true, pid: finder.processIdentifier)
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
        removeAXObserver()
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func applicationActivated(isFinder: Bool, pid: pid_t?) {
        guard isFinder, let pid else {
            removeAXObserver()
            debounceTask?.cancel()
            debounceTask = nil
            finderResigned?()
            return
        }
        installAXObserver(pid: pid)
        schedule()
    }

    /// Restarts the 250 ms debounce. The last signal in a burst wins.
    private func schedule() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.changed?()
        }
    }

    private func installAXObserver(pid: pid_t) {
        removeAXObserver()
        guard AXIsProcessTrusted() else { return }
        var observer: AXObserver?
        let status = AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<VaporFinderObserver>.fromOpaque(context).takeUnretainedValue().schedule()
            }
        }, &observer)
        guard status == .success, let observer else { return }
        let application = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.notifications {
            _ = AXObserverAddNotification(observer, application, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
        axApplication = application
    }

    private func removeAXObserver() {
        guard let axObserver else { return }
        if let axApplication {
            for name in Self.notifications { AXObserverRemoveNotification(axObserver, axApplication, name as CFString) }
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        self.axObserver = nil
        axApplication = nil
    }
}
