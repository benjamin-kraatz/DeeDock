import AppKit

/// Keeps ``DropPlacementWindowMemory`` current by reading an app's front window frame once when
/// the app deactivates or hides.
///
/// This is one Accessibility read per workspace notification, only while Accessibility is
/// granted, and never a poll. Reads run on `DropPlacementAccessibility`'s queue. Observers are
/// added in ``start()`` and removed in ``stop()``; the coordinator owns both calls.
@MainActor
final class DropPlacementWindowRecorder {
    private let memory: DropPlacementWindowMemory
    private let accessibility: DropPlacementAccessibility
    private let displays: () -> [DisplaySnapshot]
    private var observers: [NSObjectProtocol] = []
    /// Reads in flight, by process, so a burst of notifications for one app reads once.
    private var reading: Set<pid_t> = []
    /// Bumped by ``stop()``, so a read still in flight cannot save or clear state afterwards.
    private var generation = 0

    init(memory: DropPlacementWindowMemory, accessibility: DropPlacementAccessibility,
         displays: @escaping () -> [DisplaySnapshot]) {
        self.memory = memory
        self.accessibility = accessibility
        self.displays = displays
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didDeactivateApplicationNotification, NSWorkspace.didHideApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { if let app { self?.record(app) } }
            })
        }
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        reading.removeAll()
        generation += 1
    }

    private func record(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard AXIsProcessTrusted(), pid != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular, let bundleIdentifier = app.bundleIdentifier,
              reading.insert(pid).inserted else { return }
        let generation = generation
        Task { [weak self, accessibility] in
            let quartz = await accessibility.frontWindowFrame(processIdentifier: pid)
            guard let self, self.generation == generation else { return }
            reading.remove(pid)
            guard let quartz else { return }
            remember(DropPlacementService.appKit(quartz), for: bundleIdentifier)
        }
    }

    /// Saves an AppKit frame under the display that holds most of it.
    func remember(_ frame: CGRect, for bundleIdentifier: String) {
        guard let display = Self.display(for: frame, among: displays()) else { return }
        memory.record(frame, displayID: display.id, for: bundleIdentifier)
    }

    /// The display with the largest overlap, else the one holding the window's top-left corner.
    static func display(for frame: CGRect, among displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        let best = displays.max { lhs, rhs in
            let a = lhs.frame.intersection(frame), b = rhs.frame.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }
        if let best, best.frame.intersects(frame) { return best }
        return displays.first { $0.frame.contains(CGPoint(x: frame.minX, y: frame.maxY - 1)) }
    }
}
