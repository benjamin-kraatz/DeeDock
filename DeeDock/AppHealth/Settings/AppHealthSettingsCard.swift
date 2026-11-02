import SwiftUI

/// Settings → Features → App Health, driven by the live controller.
///
/// Maps the controller's observable state to `AppHealthSettingsCardContent`, which holds every visual state and is
/// what the previews render.
struct AppHealthSettingsCard: View {
    let controller: AppHealthController

    var body: some View {
        AppHealthSettingsCardContent(
            state: AppHealthSettingsState(
                collecting: controller.settings.collecting,
                labelling: controller.settings.labelling,
                phase: controller.phase,
                summary: controller.storage,
                activity: controller.storageActivity,
                error: controller.storageError,
                pausedUntil: controller.labelling.isPaused ? controller.labelling.pausedUntil : nil,
                dontAsk: controller.labelling.dontAsk.sorted().map { AppHealthAppDisplay.live($0) }),
            actions: AppHealthSettingsActions(
                setCollecting: controller.setCollecting,
                setLabelling: controller.setLabelling,
                resumeLabelling: controller.resumeLabelling,
                allowAsking: controller.allowAsking(about:),
                export: { AppHealthExportPanel.present { controller.export(to: $0) } },
                deleteAll: controller.deleteAllData,
                dismissError: controller.clearStorageError,
                revealInFinder: revealRecordsFolder))
        .onAppear { controller.refreshSummary() }
    }

    /// Opens the records folder itself in a Finder window. The link only shows when the folder holds data.
    private func revealRecordsFolder() {
        let folder = AppHealthRecordStore.defaultDirectory
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path(percentEncoded: false))
    }
}

/// Everything the card shows, as plain values.
struct AppHealthSettingsState {
    var collecting: Bool
    var labelling: Bool
    /// What the collector is doing right now: off, sampling, or paused by sleep. Drives the status line.
    var phase: AppHealthController.Phase = .off
    var summary: AppHealthStorageSummary
    var activity: AppHealthController.StorageActivity = .idle
    var error: AppHealthController.StorageError?
    /// When labelling resumes, or nil when it is not paused.
    var pausedUntil: Date?
    /// Apps on the "Don't ask" list, sorted by bundle identifier, with names and icons from macOS.
    var dontAsk: [AppHealthAppDisplay] = []
}

/// What the card's controls do.
struct AppHealthSettingsActions {
    var setCollecting: (Bool) -> Void
    var setLabelling: (Bool) -> Void
    var resumeLabelling: () -> Void
    var allowAsking: (String) -> Void
    var export: () -> Void
    var deleteAll: () -> Void
    var dismissError: () -> Void
    /// Opens the records folder in Finder.
    var revealInFinder: () -> Void

    /// Actions that do nothing, for previews.
    static let inert = AppHealthSettingsActions(setCollecting: { _ in }, setLabelling: { _ in }, resumeLabelling: {},
                                                allowAsking: { _ in }, export: {}, deleteAll: {}, dismissError: {},
                                                revealInFinder: {})
}
