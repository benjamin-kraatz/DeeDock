import SwiftUI

/// What the stage shows when no group is left: nothing open on this display, or nothing matching
/// the search. Quiet, centered, and never in the way of a click on the wallpaper.
struct HarborEmptyState: View {
    let query: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: query.isEmpty ? "macwindow" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            if query.isEmpty {
                Text(.harborNoWindows)
            } else {
                Text(.harborNoMatches(query: query))
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Empty states") {
    VStack(spacing: 40) {
        HarborEmptyState(query: "")
        HarborEmptyState(query: "Angebot")
    }
    .padding(60)
    .background(HarborBackdrop(wallpaper: nil, reduceTransparency: false))
}
#endif
