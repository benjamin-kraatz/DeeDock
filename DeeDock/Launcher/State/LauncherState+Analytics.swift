import Foundation

/// `launcher_result_activated` for every way an app or search result opens from the Apps tab.
///
/// Each report runs synchronously in the entry point, before the open starts, so
/// ``Analytics/trigger(keyboard:)`` still sees the ambient trigger its caller set (keyboard, menu,
/// VoiceOver). Reports carry kinds, positions, and flags only, never which app or result.
extension LauncherState {
    /// Whether the app grid or list is scrolled away from the top, read from the retained browse
    /// offset that ``LauncherBrowseScrollRestoration`` keeps current.
    var browseScrolled: Bool { (browseScroll?.offset ?? 0) > LauncherVisit.scrollThreshold }

    /// Reports an app opened or revealed from browsing, Robi's picks, or a Suggested card.
    ///
    /// `position` is the app's 0-based index among the Suggested cards, or among the grid's apps
    /// section by section (Suggested cards and DOKK's tools excluded).
    func reportBrowseActivation(_ application: LauncherApplication, suggested: Bool, reveal: Bool) {
        let source: AnalyticsLauncherSource = suggested ? .suggestion : robiIDs != nil ? .robi : .browse
        let position = suggested
            ? suggestedApplications.firstIndex { $0.id == application.id }
            : groups.flatMap(\.applications).firstIndex { $0.id == application.id }
        Analytics.track(.launcherResultActivated(.application, reveal: reveal, trigger: Analytics.trigger(),
                                                 source: source, position: position, scrolled: browseScrolled))
        recordVisit(reveal ? .revealed : .launched)
    }

    /// Reports a mixed search result the search state accepted, before it is dispatched.
    ///
    /// `position` is the result's 0-based index in ``LauncherSearchResult/displayOrder(_:)`` of the
    /// visible results. Matching DOKK tools sit above the results and are not counted.
    func reportSearchActivation(_ result: LauncherSearchResult, reveal: Bool) {
        let position = LauncherSearchResult.displayOrder(search.visible).firstIndex { $0.id == result.id }
        Analytics.track(.launcherResultActivated(result.kind, reveal: reveal, trigger: Analytics.trigger(),
                                                 source: query.isEmpty ? .browse : .search, position: position,
                                                 scrolled: search.scrolled))
        recordVisit(reveal ? .revealed : result.kind == .application ? .launched : .openedResult)
    }
}
