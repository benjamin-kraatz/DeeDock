import SwiftUI

/// App browsing in the Hub's Apps tab: Suggested cards, the section header with its controls, the
/// grouped grid or list, and DOKK's own tools.
///
/// Lazy stacks keep native icon loading proportional to visible content; stable IDs survive
/// sorting and filtering.
struct LauncherResultsView<Header: View>: View {
    let state: LauncherState
    /// Grid columns, computed by the caller from the content width with
    /// ``HubAppsStyle/columns(forContentWidth:)``; keyboard navigation uses the same count.
    let columns: Int
    let groups: [LauncherState.Group]
    /// When the tab appeared; tiles created right after it run the staggered entrance.
    var appearedAt: Date = .distantPast
    /// The "All Apps" row with sort chips and options, shown below the Suggested cards.
    @ViewBuilder var header: Header

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !state.suggestedApplications.isEmpty {
                        LauncherSuggestedSection(state: state, appearedAt: appearedAt)
                            .padding(.bottom, 22)
                    }
                    header
                    if groups.allSatisfy({ $0.applications.isEmpty }) {
                        LauncherNoResultsView(loading: state.library.isLoading)
                    } else {
                        ForEach(groups) { group in
                            section(group)
                        }
                    }
                    if state.showsToolsInBrowse {
                        LauncherToolsSection(state: state, tools: LauncherTool.allCases, columns: columns,
                                             grid: state.layout == .grid)
                            .padding(.top, 22)
                    }
                }
                .padding(HubAppsStyle.contentInsets)
            }
            .onChange(of: state.selectedID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
            .task(id: state.suggestionAvailabilityKey) {
                await state.suggestions.updateAvailability(applications: state.library.applications,
                                                           store: state.catalog.suggestions)
            }
            .onChange(of: groups.flatMap(\.applications).map(\.id)) { _, ids in
                if case .application(let selected) = state.selectedID, !ids.contains(selected) {
                    state.selectedID = nil
                }
            }
        }
    }

    @ViewBuilder private func section(_ group: LauncherState.Group) -> some View {
        if !group.id.isEmpty {
            HubAppsSectionHeader(title: Text(group.id))
                .padding(.top, 10)
        }
        if state.layout == .grid {
            LazyVGrid(columns: LauncherGridColumns.items(columns), spacing: HubAppsStyle.gridRowSpacing) {
                ForEach(Array(group.applications.enumerated()), id: \.element.id) { index, app in
                    result(app).hubAppsEntrance(index: index, appearedAt: appearedAt)
                }
            }
        } else {
            LazyVStack(spacing: 2) {
                ForEach(group.applications) { app in result(app) }
            }
        }
    }

    private func result(_ application: LauncherApplication) -> some View {
        LauncherResultButton(application: application, state: state)
            .id(LauncherBrowseID.application(application.id))
    }
}

/// Grid items matching ``HubAppsStyle``: equal flexible columns with the mockup's 6 pt gap.
enum LauncherGridColumns {
    static func items(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: HubAppsStyle.gridColumnSpacing), count: max(1, count))
    }
}

/// Empty browse results: still discovering, or nothing matches the filters.
struct LauncherNoResultsView: View {
    let loading: Bool

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(loading ? .launcherDiscovering : .launcherNoResults)
            } icon: {
                Image(systemName: "magnifyingglass")
            }
        } description: {
            Text(.launcherNoResultsDetail)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
