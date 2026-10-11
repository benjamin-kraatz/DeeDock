import AppKit
import os

/// Everything outside the index service that should make it sync: FSEvents in the chosen folders
/// (`LookoutFolderWatcher`), drives mounted or ejected, and wake from sleep. Reports events on the main actor; the
/// engine debounces folder changes.
///
/// Only folders that exist are watched. A missing one (an unplugged drive) is picked up when a volume mounts, which
/// re-watches the roots. The FSEvents stream and the workspace observers exist only between `start` and `stop`.
@MainActor final class LookoutMonitor: LookoutMonitoring {
    /// FSEvents' own latency. The engine adds its debounce on top.
    static let latency: TimeInterval = 0.25

    private let watchQueue = DispatchQueue(label: "Lookout.watch", qos: .utility)
    private var watcher: LookoutFolderWatcher?
    private var observers: [NSObjectProtocol] = []
    private var onEvent: ((LookoutMonitorEvent) -> Void)?

    init() {}

    isolated deinit {
        stop()
    }

    func start(roots: [String], onEvent: @escaping (LookoutMonitorEvent) -> Void) {
        stop()
        self.onEvent = onEvent
        let center = NSWorkspace.shared.notificationCenter
        for (name, event) in [(NSWorkspace.didMountNotification, LookoutMonitorEvent.volumesChanged),
                              (NSWorkspace.didUnmountNotification, .volumesChanged),
                              (NSWorkspace.didWakeNotification, .didWake)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onEvent?(event) }
            })
        }
        watch(roots: roots)
    }

    func watch(roots: [String]) {
        watcher = nil
        guard onEvent != nil else { return }
        let present = roots.filter { root in
            var isFolder: ObjCBool = false
            return FileManager.default.fileExists(atPath: root, isDirectory: &isFolder) && isFolder.boolValue
        }
        watcher = LookoutFolderWatcher(paths: present, latency: Self.latency, queue: watchQueue) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onEvent?(.foldersChanged) } }
        }
        if watcher == nil, !present.isEmpty { LookoutLog.logger.error("Can't watch the Lookout folders") }
    }

    func stop() {
        watcher = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        onEvent = nil
    }
}
