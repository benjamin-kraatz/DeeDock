import Foundation
import Testing
@testable import DeeDock

/// The Apps tab's visit outcome, the positions `launcher_result_activated` reports, and the
/// properties of the launcher events DEE-154 added or extended. Nothing here opens an app.
@MainActor
struct LauncherVisitAnalyticsTests {
    private func values(_ event: AnalyticsEvent) -> [String: String] {
        event.properties.values.mapValues(\.displayText)
    }

    // MARK: - Visit outcome

    @Test("A visit without an action ends in none, or switched_tab when another tab took over")
    func noAction() {
        var visit = LauncherVisit()
        visit.recordOptionChange()
        visit.recordScrolled()
        #expect(visit.outcome(.closed) == .none)
        #expect(visit.outcome(.switchedTab) == .switchedTab)
        #expect(visit.actionCount == 0)
        #expect(visit.optionCount == 1)
        #expect(visit.scrolled)
    }

    @Test("The strongest action decides the outcome, whatever the order; every action counts")
    func strongestWins() {
        var visit = LauncherVisit()
        visit.record(.robi)
        visit.record(.managed)
        visit.record(.launched)
        visit.record(.revealed)
        #expect(visit.outcome(.closed) == .launched)
        #expect(visit.outcome(.switchedTab) == .launched)
        #expect(visit.actionCount == 4)
    }

    @Test("Each action alone maps to its own outcome token")
    func actionTokens() {
        let tokens = LauncherVisit.Action.allCases.map { action -> String in
            var visit = LauncherVisit()
            visit.record(action)
            return visit.outcome(.switchedTab).rawValue
        }
        #expect(tokens == ["launched", "opened_result", "file_action", "tool", "revealed", "managed", "feedback",
                           "robi"])
    }

    @Test("Actions and options count only while the tab is presented")
    func stateRecordsOnlyWhileActive() {
        let launcher = LauncherState(catalog: ApplicationCatalog(service: ApplicationService(),
            launcherHistory: LauncherHistory(defaults: nil), launcherLibrary: LauncherLibrary(applications: [])))
        launcher.recordVisit(.tool)
        launcher.recordScrolled()
        #expect(launcher.visit == LauncherVisit())
        launcher.activateForPreview()
        launcher.recordVisit(.tool)
        launcher.choose(\.sort, .recent, as: AnalyticsLauncherOption.sort)
        launcher.choose(\.sort, .recent, as: AnalyticsLauncherOption.sort)
        #expect(launcher.sort == .recent)
        #expect(launcher.visit.actionCount == 1)
        #expect(launcher.visit.optionCount == 1, "Choosing the current value is not a change")
        #expect(launcher.visit.outcome(.closed) == .tool)
    }

    // MARK: - Positions

    @Test("Search positions follow the drawn order: app sections first, then other results")
    func searchDisplayOrder() {
        func app(_ index: Int, group: String) -> LauncherSearchResult {
            let application = LauncherApplication(reference: ApplicationReference(bundleIdentifier: "example.app\(index)",
                url: URL(fileURLWithPath: "/Applications/App \(index).app"), name: "App \(index)"))
            return LauncherSearchResult(id: .application(application.id), kind: .application, title: "App \(index)",
                                        source: "", action: .unifiedAll, score: index, tieBreak: "\(index)",
                                        application: application, group: group)
        }
        let window = LauncherSearchResult(id: .window(UUID()), kind: .window, title: "Window", source: "",
                                          action: .unifiedAll, score: 0, tieBreak: "w")
        let ranked = [app(0, group: "B"), window, app(1, group: "A"), app(2, group: "B")]
        let order = LauncherSearchResult.displayOrder(ranked).map(\.id)
        #expect(order == [ranked[0].id, ranked[3].id, ranked[2].id, window.id])
        #expect(LauncherSearchResult.applicationGroups(ranked) == ["B", "A"])
    }

    // MARK: - Event properties

    @Test("launcher_closed carries outcome, counts and the scrolled flag beside duration and had_query")
    func closedProperties() {
        let event = AnalyticsEvent.launcherClosed(duration: 2, hadQuery: false, outcome: .switchedTab,
                                                  actionCount: 0, optionCount: 3, scrolled: true)
        #expect(event.name == "launcher_closed")
        #expect(values(event) == ["duration": "2.0", "had_query": "false", "outcome": "switched_tab",
                                  "action_count": "0", "option_count": "3", "scrolled": "true"])
    }

    @Test("launcher_result_activated adds source, position and scrolled; an unknown position is omitted")
    func activationProperties() {
        let browse = AnalyticsEvent.launcherResultActivated(.application, reveal: false, trigger: .keyboard,
                                                            source: .browse, position: 17, scrolled: true)
        #expect(values(browse) == ["kind": "application", "reveal": "false", "trigger": "keyboard",
                                   "source": "browse", "position": "17", "scrolled": "true"])
        let stale = AnalyticsEvent.launcherResultActivated(.window, reveal: false, trigger: .click,
                                                           source: .search, position: nil, scrolled: false)
        #expect(values(stale)["position"] == nil)
    }

    @Test("launcher_option_changed reports snake-case options and values; Reset has no value")
    func optionProperties() {
        #expect(values(.launcherOptionChanged(.location(.applicationsFolders)))
            == ["option": "location", "value": "applications_folders"])
        #expect(values(.launcherOptionChanged(.resultType(.window))) == ["option": "result_type", "value": "window"])
        #expect(values(.launcherOptionChanged(.nestedApps(true))) == ["option": "nested_apps", "value": "true"])
        #expect(values(.launcherOptionChanged(.reset)) == ["option": "reset"])
        #expect(AnalyticsEvent.launcherHistoryCleared.properties.isEmpty)
        #expect(values(.launcherFavoriteChanged(favorite: true)) == ["favorite": "true"])
        #expect(values(.launcherSuggestionFeedback(.excluded)) == ["feedback": "excluded"])
    }
}
