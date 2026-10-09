import Foundation

/// Watches one folder for added, removed, and renamed items.
///
/// Wraps `FolderDirectoryMonitor` (a kqueue vnode source, no polling). Events are coalesced:
/// a burst of writes, such as a copy landing, produces one `onChange` call about 120 ms after the
/// first event. The source opens on `VolumeReads` because `open` can block on a wedged volume.
/// Owned by the pane that shows the folder; `stop()` or deinit removes the source.
@MainActor
final class HubDirectoryWatcher {
    private let onChange: @MainActor () -> Void
    private let events: AsyncStream<Void>.Continuation
    private var monitor: FolderDirectoryMonitor?
    private var setup: Task<Void, Never>?
    private var listener: Task<Void, Never>?
    private var pending: Task<Void, Never>?
    private var isStopped = false

    /// Starts watching `folder`. `onChange` runs on the main actor until `stop()`.
    init(folder: URL, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        // The monitor's handler runs on a utility queue; a stream hands its events to the main
        // actor without the handler capturing the watcher.
        let (stream, events) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.events = events
        setup = Task { [weak self] in
            let monitor = await VolumeReads.run(qos: .userInitiated) { () -> FolderDirectoryMonitor? in
                FolderDirectoryMonitor(url: folder) { events.yield() }
            }
            guard let self, !self.isStopped else { monitor?.stop(); return }
            self.monitor = monitor
        }
        listener = Task { [weak self] in
            for await _ in stream {
                self?.eventArrived()
            }
        }
    }

    private func eventArrived() {
        guard !isStopped, pending == nil else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled, !self.isStopped else { return }
            self.pending = nil
            self.onChange()
        }
    }

    /// Stops watching. Pending notifications are dropped. Safe to call more than once.
    func stop() {
        isStopped = true
        setup?.cancel()
        listener?.cancel()
        events.finish()
        pending?.cancel()
        pending = nil
        monitor?.stop()
        monitor = nil
    }

    isolated deinit { stop() }
}
