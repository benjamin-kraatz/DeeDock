import AppKit

/// Notices pasteboard changes by comparing `changeCount`.
///
/// AppKit has no public change notification for `NSPasteboard`, so this is the one polling loop in
/// the feature. `changeCount` is metadata and does not read clipboard contents. The timer exists
/// only while collecting is on, uses generous tolerance, and the owner stops it on quit.
@MainActor
final class ClipboardMuseumWatcher {
    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount = 0
    /// Called once per observed change, on the main actor.
    var changed: (() -> Void)?

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    var isRunning: Bool { timer != nil }

    /// Starts from the current change count, so whatever is already on the clipboard when
    /// collecting turns on is not collected.
    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: ClipboardMuseumLimits.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = ClipboardMuseumLimits.pollInterval / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Marks the current contents as seen, so DDock's own writes are not collected again.
    func acknowledgeCurrentChange() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        changed?()
    }
}
