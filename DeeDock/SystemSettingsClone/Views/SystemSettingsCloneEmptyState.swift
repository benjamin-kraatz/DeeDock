import SwiftUI

/// Shown when search filters out every pane.
struct SystemSettingsCloneEmptyState: View {
    let query: String
    var clearSearch: () -> Void = {}

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(.systemSettingsCloneEmptySearch)
            } icon: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
        } description: {
            Text(.systemSettingsCloneEmptySearchDescription(query: query))
        } actions: {
            Button(.systemSettingsCloneClearSearch, action: clearSearch)
        }
    }
}

#if DEBUG
#Preview("Search miss") {
    SystemSettingsCloneEmptyState(query: "zxqv")
        .frame(width: 520, height: 360)
}

#Preview("Search miss — German") {
    SystemSettingsCloneEmptyState(query: "zxqv")
        .environment(\.locale, Locale(identifier: "de"))
        .frame(width: 520, height: 360)
}
#endif
