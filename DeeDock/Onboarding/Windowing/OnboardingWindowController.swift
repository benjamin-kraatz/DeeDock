import AppKit
import SwiftUI

/// Fixed dimensions for the tour window, shared with its previews so what is inspected in
/// Xcode is the size a person actually sees.
enum OnboardingWindowMetrics {
    static let size = CGSize(width: 760, height: 588)
}

/// Owns the first-launch tour window.
///
/// Constructing it creates no window and reads no preferences beyond the completion record;
/// `presentIfNeeded()` and `present()` do the work. DeeDock runs as an accessory application,
/// so the app has to be activated explicitly before the window can take keyboard focus — the
/// same thing `OpenDockSettingsButton` does for Settings.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let store: OnboardingStore
    private let systemDock = SystemDockMonitor()
    private let loginItems: LoginItemController
    private let settings: DockSettingsStore
    private let openSettings: () -> Void
    private var window: NSWindow?

    /// - Parameters:
    ///   - loginItems: the application's controller, so a registration started here is the same
    ///     request Settings shows afterwards.
    ///   - settings: the application's shared dock defaults, so the placement page moves the
    ///     real docks rather than a copy of them.
    ///   - openSettings: opens the Settings window from the tour's final page.
    init(store: OnboardingStore? = nil, loginItems: LoginItemController,
         settings: DockSettingsStore, openSettings: @escaping () -> Void) {
        self.store = store ?? OnboardingStore()
        self.loginItems = loginItems
        self.settings = settings
        self.openSettings = openSettings
    }

    /// Shows the tour only on a launch where it has not yet been completed or dismissed.
    func presentIfNeeded() {
        guard store.shouldPresentAutomatically else { return }
        present()
    }

    /// Shows the tour, starting it over when it is not already on screen. Bringing an open
    /// window forward never rewinds a person to the first page.
    func present() {
        if window == nil { store.restart() }
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the tour and releases its window. Dismissal counts as having seen it.
    func stop() {
        guard let window else { return }
        self.window = nil
        window.delegate = nil
        window.close()
        systemDock.stop()
    }

    /// Closing the window — by the final button, the close button, or Escape — is the same
    /// decision, and none of them should leave the tour queued for the next launch.
    func windowWillClose(_ notification: Notification) {
        store.complete()
        window = nil
        systemDock.stop()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: OnboardingWindowMetrics.size),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        // A hidden title bar over full-size content, so the demonstration reaches the top edge.
        // The title still names the window for VoiceOver and the Window menu.
        window.title = String(localized: .onboardingWindowTitle)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView:
            OnboardingView(store: store, systemDock: systemDock, loginItems: loginItems,
                           settings: settings,
                           openSettings: { [weak self] in self?.openSettingsFromTour() },
                           finish: { [weak self] in self?.finish() })
                .frame(width: OnboardingWindowMetrics.size.width, height: OnboardingWindowMetrics.size.height))
        return window
    }

    /// Opening Settings ends the tour: a person who wants the real controls has finished with
    /// the summary, and leaving both windows stacked would be clutter.
    private func openSettingsFromTour() {
        finish()
        openSettings()
    }

    private func finish() {
        store.complete()
        stop()
    }
}
