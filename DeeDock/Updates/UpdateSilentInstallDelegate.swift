import Foundation
import Sparkle

/// Takes over updates Sparkle downloaded silently.
///
/// Sparkle's automatic driver installs on quit and never calls the user driver, and a dock
/// stays running for weeks. Returning true hands DOKK the immediate-install handler, which
/// it calls from the Update window or once the dock is idle. Sparkle still installs on quit.
/// While the update is held, Sparkle starts no further update cycles.
final class UpdateSilentInstallDelegate: NSObject, SPUUpdaterDelegate {
    /// Receives the prepared item and Sparkle's install-and-relaunch handler.
    var stage: (SUAppcastItem, @escaping () -> Void) -> Void = { _, _ in }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        stage(item, immediateInstallHandler)
        return true
    }
}
