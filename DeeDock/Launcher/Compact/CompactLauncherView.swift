import SwiftUI

/// The compact Launcher: a title, an app search field, and a scrolling grid of apps, led by any
/// suggested apps, in a popover that points at the dock's Launcher tile.
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
        .compactLauncherChrome(model.chrome, opaque: reduceTransparency)
        .onAppear { searchFocused = true }
        // Suggestions need an existence check before they show, so this runs whether or not any do.
        .task(id: model.launcher.suggestionAvailabilityKey) {
            await model.launcher.suggestions.updateAvailability(applications: model.launcher.library.applications,
                                                                store: model.launcher.catalog.suggestions)
        }
        // Arrow keys and Return go through the controller, so the field can keep focus throughout.
        .onChange(of: searchFocused) { _, focused in if !focused { searchFocused = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.launcherTitle))
    }
}

/// The Suggested row and the results grid, or a short message when the search matches nothing.
private struct CompactLauncherGrid: View {
    let model: CompactLauncherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = Array(repeating: GridItem(.fixed(CompactLauncherLayout.tileWidth),
                                                    spacing: CompactLauncherLayout.spacing),
                                count: CompactLauncherLayout.columns)

    var body: some View {
        let results = model.results
        let suggestions = model.suggestions
        if results.isEmpty {
            Text(.launcherNoResults)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !suggestions.isEmpty {
                            CompactLauncherSuggestions(model: model, applications: suggestions)
                                .transition(.opacity.combined(with: .offset(y: -8)))
                        }
                        LazyVGrid(columns: columns, spacing: CompactLauncherLayout.spacing) {
                            ForEach(results) { application in
                                CompactLauncherTile(application: application, launcher: model.launcher,
                                                    selected: model.selectedID == .application(application.id))
                                    .id(LauncherBrowseID.application(application.id))
                            }
                        }
                        // Tiles swap in place when the query changes; only the grid's position animates.
                        .animation(nil, value: results.map(\.id))
                    }
                    // Suggestions arrive a moment after the panel opens. Slide the grid down to make
                    // room rather than jumping, but leave typing instant: the row leaves with the query.
                    .animation(model.query.isEmpty && !reduceMotion ? .smooth(duration: 0.3) : nil,
                               value: suggestions.map(\.id))
                    // Leading-aligned at a fixed width: an always-visible scroller takes its width
                    // from the trailing gutter, so the grid never shifts when results stop scrolling.
                    .frame(width: CompactLauncherLayout.gridWidth)
                    .padding(.leading, CompactLauncherLayout.padding)
                    .padding(.bottom, CompactLauncherLayout.padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }
}
