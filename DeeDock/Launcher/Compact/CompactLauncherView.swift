import SwiftUI

/// The compact Launcher: a title, an app search field, and a scrolling grid of apps in a popover
/// that points at the dock's Launcher tile.
struct CompactLauncherView: View {
    let model: CompactLauncherModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            CompactLauncherHeader(model: model, focused: $searchFocused)
                .padding(.horizontal, CompactLauncherLayout.padding)
            CompactLauncherGrid(model: model)
        }
        .dockPopoverChrome(model.chrome, opaque: reduceTransparency)
        .onAppear { searchFocused = true }
        // Arrow keys and Return go through the controller, so the field can keep focus throughout.
        .onChange(of: searchFocused) { _, focused in if !focused { searchFocused = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.launcherTitle))
    }
}

/// The results grid, or a short message when the search matches nothing.
private struct CompactLauncherGrid: View {
    let model: CompactLauncherModel
    private let columns = Array(repeating: GridItem(.fixed(CompactLauncherLayout.tileWidth),
                                                    spacing: CompactLauncherLayout.spacing),
                                count: CompactLauncherLayout.columns)

    var body: some View {
        let results = model.results
        if results.isEmpty {
            Text(.launcherNoResults)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: CompactLauncherLayout.spacing) {
                        ForEach(results) { application in
                            CompactLauncherTile(application: application, launcher: model.launcher,
                                                selected: model.selectedID == application.id)
                                .id(application.id)
                        }
                    }
                    .padding(.horizontal, CompactLauncherLayout.padding)
                    .padding(.bottom, CompactLauncherLayout.padding)
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }
}
