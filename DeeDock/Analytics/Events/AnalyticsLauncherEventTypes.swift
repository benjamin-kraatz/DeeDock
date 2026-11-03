import Foundation

/// Where an item activated in the Hub's Apps tab was shown, for `launcher_result_activated`.
nonisolated enum AnalyticsLauncherSource: String, AnalyticsToken {
    /// Mixed search results for typed text.
    case search
    /// The app grid or list with no search text, including a chosen result type such as Windows.
    case browse
    /// One of the Suggested cards above the grid.
    case suggestion
    /// The apps Robi picked for a task, shown in place of the grid.
    case robi
}

/// How one visit to the Apps tab ended, for `launcher_closed`.
///
/// The strongest action of the visit wins, in the order listed; a visit without one ends in
/// ``switchedTab`` or ``none``. ``LauncherVisit`` applies that order.
nonisolated enum AnalyticsLauncherOutcome: String, AnalyticsToken {
    /// An app opened, from search, browsing, a suggestion, or Robi's picks.
    case launched
    /// A window, capsule, Shelf file, or Shortcut from search.
    case openedResult = "opened_result"
    /// A file action ran, Find Similar included.
    case fileAction = "file_action"
    /// A DOKK tool, a capsule from an app, Capture & image search, or DOKK Settings opened.
    case tool
    /// Show in Finder.
    case revealed
    /// A favorite, a pin, or an uninstall changed, or launch history was cleared.
    case managed
    /// Feedback on a Suggested card: useful, not useful right now, or never suggest this app.
    case feedback
    /// Robi was asked, and nothing above followed.
    case robi
    /// No action; another Hub tab was selected.
    case switchedTab = "switched_tab"
    /// No action; the Hub closed.
    case none
}

/// A browse option chosen in the Apps tab, for `launcher_option_changed`.
nonisolated enum AnalyticsLauncherOption: Equatable, Sendable {
    case resultType(LauncherSearchKind)
    case filter(LauncherFilter)
    case location(LauncherLocationFilter)
    case nestedApps(Bool)
    case sort(LauncherSort)
    case grouping(LauncherGrouping)
    case layout(LauncherLayout)
    /// "Reset" in the options menu.
    case reset

    /// The `option` property.
    nonisolated enum Name: String, AnalyticsToken {
        case resultType = "result_type", filter, location, nestedApps = "nested_apps", sort, grouping, layout, reset
    }

    var name: Name {
        switch self {
        case .resultType: .resultType
        case .filter: .filter
        case .location: .location
        case .nestedApps: .nestedApps
        case .sort: .sort
        case .grouping: .grouping
        case .layout: .layout
        case .reset: .reset
        }
    }

    /// The `value` property: the chosen case, or the switch's new state. Nil for ``reset``.
    var value: AnalyticsValue? {
        switch self {
        case let .resultType(kind): AnalyticsValue(kind)
        case let .filter(filter): AnalyticsValue(filter)
        case let .location(location): AnalyticsValue(AnalyticsLauncherLocation(location))
        case let .nestedApps(shown): AnalyticsValue(shown)
        case let .sort(sort): AnalyticsValue(sort)
        case let .grouping(grouping): AnalyticsValue(grouping)
        case let .layout(layout): AnalyticsValue(layout)
        case .reset: nil
        }
    }
}

/// ``LauncherLocationFilter`` in snake case; its raw values are camel case.
nonisolated enum AnalyticsLauncherLocation: String, AnalyticsToken {
    case all, applicationsFolders = "applications_folders", standardMacLocations = "standard_mac_locations"

    init(_ location: LauncherLocationFilter) {
        switch location {
        case .all: self = .all
        case .applicationsFolders: self = .applicationsFolders
        case .standardMacLocations: self = .standardMacLocations
        }
    }
}

extension LauncherFilter: AnalyticsToken {}
extension LauncherSort: AnalyticsToken {}
extension LauncherGrouping: AnalyticsToken {}
extension LauncherLayout: AnalyticsToken {}
