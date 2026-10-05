import Foundation
import Sparkle

/// DOKK's Sparkle delegate: takes over silently downloaded updates and reports every cycle.
///
/// Sparkle's automatic driver installs on quit and never calls the user driver, and a dock
/// stays running for weeks. Returning true hands DOKK the immediate-install handler, which
/// it calls from the Update window or once the dock is idle. Sparkle still installs on quit.
/// While the update is held, Sparkle starts no further update cycles.
///
/// The remaining callbacks only forward to ``UpdateAnalytics``. They are the one place that
/// sees scheduled checks and silent downloads, which never reach the user driver.
final class UpdateEngineDelegate: NSObject, SPUUpdaterDelegate {
    /// Receives the prepared item and Sparkle's install-and-relaunch handler.
    var stage: (SUAppcastItem, @escaping () -> Void) -> Void = { _, _ in }
    var analytics: UpdateAnalytics?

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        stage(item, immediateInstallHandler)
        return true
    }

    /// Never refuses. Sparkle asks before every check, which makes this the start of a cycle.
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        analytics?.checkStarted(updateCheck)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        analytics?.found(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        analytics?.notFound(error)
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        analytics?.downloadStarted(item)
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        analytics?.downloadFinished(.succeeded)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        analytics?.downloadFinished(.failed, error: error)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        analytics?.downloadFinished(.canceled)
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        analytics?.extractionStarted()
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        analytics?.extracted()
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        analytics?.installStarted(item)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        analytics?.aborted(error)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        analytics?.cycleFinished(updateCheck, error: error)
    }
}
