import SwiftUI

/// Lazy results keep native icon loading proportional to visible content; stable IDs survive sorting and filtering.
struct LauncherResultsView: View {
    let state: LauncherState
    let columns: Int
    let groups: [LauncherState.Group]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if groups.allSatisfy({ $0.applications.isEmpty }) {
                    ContentUnavailableView {
                        Label {
                            Text(
                                state.library.isLoading
                                    ? .launcherDiscovering : .launcherNoResults
                            )
                        } icon: {
                            Image(systemName: "magnifyingglass")
                        }
                    } description: {
                        Text(.launcherNoResultsDetail)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if !state.suggestedApplications.isEmpty {
                            LauncherSuggestedSection(state: state, columns: columns)
                            Divider()
                        }
                        ForEach(groups) { group in
                            VStack(alignment: .leading) {
                                if !group.id.isEmpty {
                                    Text(group.id).font(.headline).foregroundStyle(
                                        .secondary
                                    )
                                    .accessibilityAddTraits(.isHeader)
                                    .padding(.leading, 12)
                                }
                                if state.layout == .grid {
                                    LazyVGrid(
                                        columns: Array(
                                            repeating: GridItem(
                                                .flexible(),
                                                spacing: 0
                                            ),
                                            count: columns
                                        ),
                                        spacing: 0
                                    ) {
                                        ForEach(group.applications) { app in
                                            result(app)
                                        }
                                    }
                                } else {
                                    LazyVStack(spacing: 0) {
                                        ForEach(group.applications) { app in
                                            result(app)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(2)
                }
            }
            .onChange(of: state.selectedID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
            .task(id: state.suggestionAvailabilityKey) {
                await state.suggestions.updateAvailability(applications: state.library.applications)
            }
            .onChange(of: groups.flatMap(\.applications).map(\.id)) { _, ids in
                if case .application(let selected) = state.selectedID, !ids.contains(selected) {
                    state.selectedID = nil
                }
            }
        }
    }

    private func result(_ application: LauncherApplication) -> some View {
        LauncherResultButton(application: application, state: state).id(
            LauncherBrowseID.application(application.id)
        )
    }
}

struct LauncherResultButton: View {
    let application: LauncherApplication
    let state: LauncherState
    /// Mixed search retains typed membership and action guards; ordinary browsing uses its existing owner directly.
    var searchResult: LauncherSearchResult? = nil
    var isSuggestion = false
    @State private var icon: NSImage?
    @State private var hovered = false
    @State private var hoveredBadge: Badge?

    private enum Badge { case favorite, pinned }

    private var selected: Bool {
        state.usesMixedResults ? state.search.selectedID == .application(application.id)
            : state.selectedID == (isSuggestion ? .suggested(application.id) : .application(application.id))
    }
    private var favorite: Bool { state.favorites.ids.contains(application.id) }
    private var pinned: Bool { state.pinnedIDs.contains(application.id) }
    private var running: Bool {
        state.catalog.runningIDs.contains(application.id)
    }
    private var busy: Bool { state.catalog.launching.contains(application.id) }
    private var interactionBlocked: Bool {
        busy || (searchResult != nil && (state.search.actionBusy || state.search.ranking || !state.search.active))
    }

    var body: some View {
        Button {
            if let searchResult { state.search.activate(searchResult) }
            else if isSuggestion { state.openSuggested(application) }
            else { state.open(application) }
        } label: {
            Group {
                if state.layout == .grid {
                    VStack(spacing: 8) {
                        artwork(size: 60)
                        Text(
                            application.reference.name.replacingOccurrences(
                                of: "\u{00ad}",
                                with: ""
                            )
                        ).font(.callout).lineLimit(2)
                            .allowsTightening(true).minimumScaleFactor(0.9)
                            .multilineTextAlignment(.center).frame(
                                height: 34,
                                alignment: .top
                            )
                    }
                    .padding(10).frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 12) {
                        artwork(size: 34)
                        Text(application.reference.name).font(.body.bold()).lineLimit(
                            1
                        )
                        Spacer()
                        Text(LauncherCategory.title(application.category)).font(
                            .caption
                        ).foregroundStyle(.secondary)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(
                selected
                    ? Color.accentColor.opacity(0.18)
                    : Color.primary.opacity(hovered ? 0.06 : 0),
                in: .rect(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(
                    selected ? Color.accentColor : .clear,
                    lineWidth: 2
                )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain).disabled(interactionBlocked)
        .contextMenu {
            LauncherApplicationMenu(application: application, state: state, searchResult: searchResult, isSuggestion: isSuggestion)
            if isSuggestion {
                Divider()
                LauncherSuggestionActions(application: application, state: state)
            }
        }
        .onHover {
            hovered = $0
            if !$0 { hoveredBadge = nil }
        }
        .task(id: application.reference.url) {
            icon = state.icon(for: application)
        }
        .accessibilityLabel(Text(application.reference.name))
        .accessibilityValue(accessibilityStatus)
        .accessibilityHint(Text(.launcherOpenHint))
        .accessibilityActions {
            if isSuggestion { LauncherSuggestionActions(application: application, state: state) }
        }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        // The outer Button owns the native tooltip, so nested badge help cannot override it.
        .help(hoverHelp)
    }

    private var hoverHelp: Text {
        switch hoveredBadge {
        case .favorite where favorite: Text(.launcherFavoriteBadgeHelp)
        case .pinned where pinned: Text(.launcherPinnedBadgeHelp)
        default: Text(verbatim: application.reference.url.path)
        }
    }

    private var accessibilityStatus: Text {
        let status = pinned
            ? String(localized: running ? .launcherPinnedRunning : .launcherPinnedNotRunning)
            : String(localized: running ? .launcherRunning : .launcherNotRunning)
        return favorite ? Text(.launcherFavoriteStatus(status: status)) : Text(verbatim: status)
    }

    private func artwork(size: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "app.dashed").resizable().scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            if running {
                Circle().fill(.primary.opacity(0.65)).frame(width: 4, height: 4)
                    .offset(y: 5)
            }
            if busy {
                ProgressView().controlSize(.small).frame(
                    width: size,
                    height: size
                ).background(.regularMaterial, in: .circle)
            }
        }
        .overlay(alignment: .topLeading) {
            if favorite {
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.31, height: size * 0.31)
                    .background(Color.orange.gradient, in: .circle)
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.45), lineWidth: 0.75)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                    .contentShape(.circle)
                    .onHover { inside in
                        if inside { hoveredBadge = .favorite }
                        else if hoveredBadge == .favorite { hoveredBadge = nil }
                    }
                    .offset(x: -size * 0.02, y: -size * 0.01)
            }
        }
        .overlay(alignment: .topTrailing) {
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: size * 0.19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .background(Color.accentColor, in: .circle)
                    .overlay {
                        Circle().strokeBorder(.background, lineWidth: 1.5)
                    }
                    .contentShape(.circle)
                    .onHover { inside in
                        if inside { hoveredBadge = .pinned }
                        else if hoveredBadge == .pinned { hoveredBadge = nil }
                    }
                    .offset(x: size * 0.04, y: -size * 0.02)
            }
        }
        .accessibilityHidden(true)
    }
}
