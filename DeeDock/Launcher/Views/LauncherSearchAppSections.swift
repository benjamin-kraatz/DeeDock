import SwiftUI

/// Search uses the same app cells and grouping choices as browsing, while other result kinds keep their own rows.
struct LauncherSearchAppSections: View {
    let launcher: LauncherState
    let results: [LauncherSearchResult]

    private var groups: [String] { LauncherSearchResult.applicationGroups(results) }

    var body: some View {
        ForEach(groups, id: \.self) { group in
            let applications = results.filter { $0.application != nil && $0.group == group }
            VStack(alignment: .leading, spacing: 0) {
                if !group.isEmpty {
                    HubAppsSectionHeader(title: Text(group))
                }
                if launcher.layout == .grid {
                    LazyVGrid(columns: LauncherGridColumns.items(launcher.navigationColumns),
                              spacing: HubAppsStyle.gridRowSpacing) {
                        ForEach(applications) { result in
                            if let app = result.application {
                                LauncherResultButton(application: app, state: launcher, searchResult: result).id(result.id)
                            }
                        }
                    }
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(applications) { result in
                            if let app = result.application {
                                LauncherResultButton(application: app, state: launcher, searchResult: result).id(result.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
