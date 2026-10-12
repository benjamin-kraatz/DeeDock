import Foundation
import Observation

/// What Lookout's Settings section shows and does: the switch, the folders with their indexed counts, the battery
/// choice, the index's size on disk, "Read everything again" and "Delete index and model".
///
/// One exists for the app's lifetime (`HubCoordinator` makes it, beside the onboarding it can open). Changes go
/// through the engine (`LookoutEngine.apply`), which saves them and tells the index service; each is reported as
/// `setting_changed` (`AnalyticsFeatureSetting.lookout…`) with counts and flags only.
///
/// Main actor. Folder reads and the size of the index run off it.
@MainActor @Observable
final class LookoutSettingsModel {
    /// Something to say under the folder list.
    enum Notice: Equatable {
        case refused(LookoutFolderChoice.Refusal)
        case alreadyIncluded(String)
        /// macOS didn't let Lookout read the folder the person added; it wasn't added.
        case notAllowed
        case missing
        /// "Delete index and model" couldn't delete everything; `reason` is the system's description.
        case deleteFailed(String)
        /// "Delete index and model" deleted nothing: the index service didn't confirm it closed the index in time.
        case deleteWaitedTooLong
    }

    let engine: LookoutEngine
    let home: String
    private(set) var folderCounts: [String: Int] = [:]
    private(set) var indexBytes: Int64?
    private(set) var notice: Notice?
    private(set) var isDeleting = false

    /// Opens Lookout's onboarding over the Hub ("Search by content" before setup).
    @ObservationIgnored var presentSetup: () -> Void = {}

    @ObservationIgnored private let setup: LookoutSetupCoordinator?
    @ObservationIgnored private let inspector: any LookoutFolderInspecting
    @ObservationIgnored private let picker: any LookoutFolderPicking
    @ObservationIgnored private var previewStatus: LookoutStatus?
    @ObservationIgnored private var previewMissing: [String] = []
    @ObservationIgnored private var previewNotPermitted: [String] = []
    /// The progress card a preview pins; `progress` reads the engine otherwise.
    @ObservationIgnored private(set) var previewProgress: LookoutProgressDisplay?
    /// A preview model, over an inert engine: its status and progress are what `preview(…)` pinned.
    @ObservationIgnored private(set) var isPreview = false

    init(engine: LookoutEngine, setup: LookoutSetupCoordinator?, inspector: any LookoutFolderInspecting,
         picker: any LookoutFolderPicking, home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.engine = engine
        self.setup = setup
        self.inspector = inspector
        self.picker = picker
        self.home = LookoutFolderChoice.normalized(home)
    }

    /// The real model; under the test host and in previews it reads no folder and opens no panel.
    static func live(engine: LookoutEngine, setup: LookoutSetupCoordinator) -> LookoutSettingsModel {
        let inert = HostEnvironment.isTestHost || HostEnvironment.isPreview
        return LookoutSettingsModel(
            engine: engine, setup: setup,
            inspector: inert ? LookoutStubFolderInspector() : LookoutLiveFolderInspector(),
            picker: inert ? LookoutStubFolderPicker() : LookoutOpenPanelPicker())
    }

    // MARK: State

    var status: LookoutStatus { previewStatus ?? engine.status }
    var settings: LookoutSettings { engine.settings }
    /// Onboarding has completed setup.
    var isSetUp: Bool { settings.setupCompleted }
    /// "Search by content": set up and on.
    var isOn: Bool { settings.isActive }
    var folders: [String] { settings.folders }

    /// The searchable files in all folders.
    var totalCount: Int { folders.reduce(0) { $0 + (folderCounts[$1] ?? 0) } }

    /// A chosen folder that isn't there right now (an unplugged drive). Its files stay in the index.
    func isMissing(_ folder: String) -> Bool {
        contains(previewMissing.isEmpty ? engine.missingFolders : previewMissing, folder)
    }

    /// A chosen folder macOS doesn't let Lookout read (Files and Folders).
    func isNotPermitted(_ folder: String) -> Bool {
        contains(previewNotPermitted.isEmpty ? engine.notPermittedFolders : previewNotPermitted, folder)
    }

    /// The service reports real paths (/private/var); Settings keeps folders as chosen.
    private func contains(_ roots: [String], _ folder: String) -> Bool {
        let real = FolderSelection.realPath(LookoutFolderChoice.normalized(folder))
        return roots.contains { $0 == folder || $0 == real }
    }

    // MARK: Changes

    /// "Search by content". Before setup, turning it on opens onboarding instead (the switch stays off until setup
    /// completes). Turning it off stops Lookout and keeps the index.
    func setOn(_ on: Bool) {
        guard isSetUp else {
            if on { presentSetup() }
            return
        }
        var settings = settings
        settings.enabled = on
        apply(settings, reporting: .lookoutEnabled, from: AnalyticsValue(isOn), to: AnalyticsValue(on))
    }

    func setIndexOnBattery(_ on: Bool) {
        var settings = settings
        settings.indexOnBattery = on
        apply(settings, reporting: .lookoutIndexOnBattery, from: AnalyticsValue(self.settings.indexOnBattery),
              to: AnalyticsValue(on))
    }

    /// Removes a folder; its files leave the index (the service prunes them).
    func removeFolder(_ folder: String) {
        var settings = settings
        settings.folders.removeAll { $0 == folder }
        settings.excludedFolders.removeAll { FolderSelection.isInside($0, folder) }
        notice = nil
        apply(settings, reporting: .lookoutFolderCount, from: AnalyticsValue(folders.count),
              to: AnalyticsValue(settings.folders.count))
    }

    /// "Add folder…": the open panel, then a read of the folder right away, so a macOS prompt appears now, in
    /// context. Only a folder Lookout may read is added.
    func addFolder() async {
        guard let url = await picker.pickFolder() else { return }
        switch LookoutFolderChoice.choose(url.path, chosen: folders, home: home) {
        case .refused(let refusal):
            notice = .refused(refusal)
        case .alreadyIncluded(let parent):
            notice = .alreadyIncluded(parent)
        case .add(let path, let replacing):
            let access = await inspector.access(path)
            if access == .allowed || access == .denied {
                Analytics.track(.lookoutAccessResult(access == .allowed ? .allowed : .denied, context: .settings))
            }
            switch access {
            case .allowed:
                var settings = settings
                settings.folders.removeAll { replacing.contains(LookoutFolderChoice.normalized($0)) }
                settings.folders.append(path)
                notice = nil
                apply(settings, reporting: .lookoutFolderCount, from: AnalyticsValue(folders.count),
                      to: AnalyticsValue(settings.folders.count))
            case .missing:
                notice = .missing
            case .denied, .unknown, .checking:
                notice = .notAllowed
            }
        }
    }

    /// "Read everything again".
    func readEverythingAgain() {
        engine.readEverythingAgain()
    }

    /// "Delete index and model", after the person confirmed: stops a download and forgets onboarding's draft, then
    /// the engine closes and deletes the index and the models. Lookout is not set up afterwards.
    func deleteEverything() async {
        guard !isDeleting else { return }
        isDeleting = true
        await setup?.reset()
        do {
            try await engine.deleteIndexAndModel()
            notice = nil
        } catch is LookoutIndexCloseError {
            notice = .deleteWaitedTooLong
        } catch {
            notice = .deleteFailed(error.localizedDescription)
        }
        // The partial download went with the rest: onboarding's download step starts from zero.
        setup?.downloader.refresh()
        folderCounts = [:]
        indexBytes = nil
        isDeleting = false
    }

    /// "Open Settings" beside a folder macOS doesn't let Lookout read.
    func openPrivacySettings() {
        LookoutPrivacySettings.openFilesAndFolders()
    }

    private func apply(_ settings: LookoutSettings, reporting setting: AnalyticsFeatureSetting,
                       from old: AnalyticsValue, to new: AnalyticsValue) {
        guard settings != self.settings else { return }
        engine.apply(settings)
        Analytics.shared.featureSettingChanged(setting, from: old, to: new)
    }

    // MARK: Refresh

    /// Reads the folders' indexed counts and the index's size again (the pane calls this as the index changes).
    func refresh() async {
        guard !isPreview else { return }
        folderCounts = await engine.searchableFileCounts()
        indexBytes = await Self.indexSize(engine.paths)
    }

    /// The database and its write-ahead log, off the main actor.
    @concurrent private static func indexSize(_ paths: LookoutPaths) async -> Int64 {
        IndexStore.size(of: paths.indexFile)
    }
}

// MARK: - Previews

extension LookoutSettingsModel {
    /// A model over an inert engine with `settings` and fixed counts and states. It reads no folder and opens no
    /// panel.
    static func preview(status: LookoutStatus = .ready, folders: [String] = LookoutSettingsModel.previewFolders,
                        counts: [String: Int] = LookoutSettingsModel.previewCounts, missing: [String] = [],
                        notPermitted: [String] = [], bytes: Int64? = 180_000_000,
                        notice: Notice? = nil, progress: LookoutProgressDisplay? = nil) -> LookoutSettingsModel {
        var settings = LookoutSettings()
        settings.setupCompleted = status != .notSetUp
        settings.enabled = status != .notSetUp && status != .off
        settings.folders = status == .notSetUp ? [] : folders
        let model = LookoutSettingsModel(engine: .inert(settings: settings), setup: nil,
                                         inspector: LookoutStubFolderInspector(), picker: LookoutStubFolderPicker(),
                                         home: "/Users/preview")
        model.isPreview = true
        model.previewStatus = status
        model.previewMissing = missing
        model.previewNotPermitted = notPermitted
        model.previewProgress = progress
        model.folderCounts = counts
        model.indexBytes = bytes
        model.notice = notice
        return model
    }

    nonisolated static let previewFolders = ["/Users/preview/Desktop", "/Users/preview/Documents", "/Users/preview/Downloads"]
    nonisolated static let previewCounts = ["/Users/preview/Desktop": 412, "/Users/preview/Documents": 2_860,
                                "/Users/preview/Downloads": 1_930]
}
