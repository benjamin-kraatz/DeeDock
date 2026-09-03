import AppKit
import Observation

/// Watches whether the macOS Dock is still reserving desktop space, so the guide can confirm
/// the change while a person is standing in System Settings.
///
/// macOS posts `didChangeScreenParametersNotification` when the Dock's reserved space appears or
/// disappears, so nothing here polls. `NSScreen` is read directly rather than
/// `DockCoordinator.enabledDisplays`, which is empty when every dock is switched off and would
/// leave the guide unable to answer. Constructing the monitor registers nothing; `start()` does.
@MainActor @Observable
final class SystemDockMonitor {
    /// The edge the system Dock currently takes space from, or nil when it takes none.
    private(set) var reservedEdge: DockEdge?

    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var screens: () -> [(frame: CGRect, visibleFrame: CGRect)]

    /// The screen source is injectable so previews and tests never depend on the real desktop.
    init(screens: @escaping () -> [(frame: CGRect, visibleFrame: CGRect)] = {
        NSScreen.screens.map { ($0.frame, $0.visibleFrame) }
    }) {
        self.screens = screens
        reservedEdge = SystemDockReservation.reservedEdge(in: screens())
    }

    var reservesSpace: Bool { reservedEdge != nil }

    /// Begins observing. Calling it again while observing re-reads without adding an observer.
    func start() {
        refresh()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    func refresh() { reservedEdge = SystemDockReservation.reservedEdge(in: screens()) }

    /// Removes the observer with the view that owns it; the monitor can be started again.
    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// Opens System Settings at the pane holding the Dock's automatic-hiding switch.
    ///
    /// The guide's numbered instructions stand on their own if the deep link cannot be opened,
    /// so a failure needs no separate error path.
    func openDesktopAndDockSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
