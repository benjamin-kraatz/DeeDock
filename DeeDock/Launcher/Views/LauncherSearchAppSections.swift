import SwiftUI

/// Search uses the same app cells and grouping choices as browsing, while other result kinds keep their own rows.
struct LauncherSearchAppSections: View {
    let launcher: LauncherState
    let results: [LauncherSearchResult]

    private var groups: [String] {
        var seen: Set<String> = []
        return results.filter { $0.application != nil }.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
    }

    var body: some View {
        ForEach(groups, id: \.self) { group in
            let applications = results.filter { $0.application != nil && $0.group == group }
            VStack(alignment: .leading, spacing: 8) {
                if !group.isEmpty {
                    Text(group).font(.headline).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader).padding(.leading, 12)
                }
                if launcher.layout == .grid {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0),
                                             count: launcher.navigationColumns), spacing: 0) {
                        ForEach(applications) { result in
                            if let app = result.application {
                                LauncherResultButton(application: app, state: launcher, searchResult: result).id(result.id)
                            }
                        }
                    }
                } else {
                    LazyVStack(spacing: 0) {
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
