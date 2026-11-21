import Foundation
import Observation

/// What phase B2's providers share: Lookout through ``semantic``, the "about" topic cache, the
/// file analysis cache, and narrow views of Flix Files' settings, history, read policy, and drag
/// state.
///
/// One per `FlixCoordinator`, made by `installSmartProviders(lookout:robi:)`. Providers hold it;
/// it holds Flix Files' objects without owning them. ``stop()`` flushes the caches and cancels
/// nothing itself: each provider cancels its own work in its `stop()`. Main actor.
@MainActor
final class FlixSmartServices {
    let semantic: FlixSemanticIndex
    let topics = FlixTopicCache()
    let analyses: FlixAnalysisStore
    /// Flix Files' Application Support folder, or nil in tests and previews (caches stay in memory).
    let storage: URL?

    private let settingsStore: FlixSettingsStore
    private let history: FlixHistory
    private let intelligence: FlixIntelligence
    private let panelState: FlixPanelState?
    private let policy: () -> FlixReadPolicy
    /// Called with the whole history on every annotation pass, so learners (drag memory's usage
    /// counts) see activity as it happens.
    var activityObservers: [([FlixItem]) -> Void] = []

    init(lookout: LookoutEngine?, settingsStore: FlixSettingsStore, history: FlixHistory, intelligence: FlixIntelligence,
         panelState: FlixPanelState?, storage: URL?, policy: @escaping () -> FlixReadPolicy) {
        semantic = FlixSemanticIndex(lookout: lookout)
        analyses = FlixAnalysisStore(folder: storage)
        self.storage = storage
        self.settingsStore = settingsStore
        self.history = history
        self.intelligence = intelligence
        self.panelState = panelState
        self.policy = policy
    }

    /// The live storage folder, or nil under the test host and in previews.
    static var liveStorage: URL? {
        HostEnvironment.isTestHost || HostEnvironment.isPreview ? nil : FlixStorageLocation.folder()
    }

    var settings: FlixSettings { settingsStore.settings }
    var readPolicy: FlixReadPolicy { policy() }
    var items: [FlixItem] { history.items }
    var smartFilters: [FlixSmartFilter] { history.smartFilters }
    func item(_ id: FlixItem.ID) -> FlixItem? { history.item(id) }

    func load() { analyses.load() }

    func stop() { analyses.flush() }

    /// Asks Flix Files for a fresh annotation and Threads pass, which it coalesces for two seconds.
    /// Background work calls this after it cached new results, so the next pass picks them up.
    func requestRefresh() {
        intelligence.historyChanged(items: history.items)
    }

    /// Tells the learners about the history, once per annotation pass.
    func observeActivity(_ items: [FlixItem]) {
        for observer in activityObservers { observer(items) }
    }

    /// A drag out of the panel is in progress.
    var isDragging: Bool { panelState?.drag != nil }

    /// Returns once no drag is in progress, so background reading and model calls never compete
    /// with one. Waits on the drag state's next change (observation, no polling). A task cancelled
    /// while waiting returns when the drag ends.
    func waitWhileDragging() async {
        guard let panelState else { return }
        while panelState.drag != nil, !Task.isCancelled {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = panelState.drag
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }
}
