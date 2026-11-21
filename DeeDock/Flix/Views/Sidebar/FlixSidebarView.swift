import SwiftUI

/// The sidebar: activity types, ✦ Threads, kinds, Smart Filters, Favorites, and the ✦ tip card.
///
/// Counts follow the noise switch. Favorites take drops of Flix rows: a folder moves them there
/// (with Undo), an app opens them with it. The selection pill slides between rows when the filter
/// changes, sections and rows that come and go fade in place, and a Smart Filter added while the
/// panel is open is washed violet for a moment. With Reduce Motion the pill jumps and the rest
/// crossfades.
struct FlixSidebarView: View {
    let state: FlixPanelState

    @Namespace private var selection
    /// The Smart Filter added since the panel opened, washed until it fades.
    @State private var bornFilter: FlixSmartFilter.ID?

    var body: some View {
        let base = baseItems
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    activityRows(base)
                    if state.intelligence.hasThreads { threadRows(base) }
                    kindRows(base)
                    smartFilterRows(base)
                    if !state.history.favorites.isEmpty { favoriteRows(base) }
                    if let tip = state.intelligence.filterTip {
                        FlixFilterTipCard(tip: tip, make: { state.acceptFilterTip(tip) }, dismiss: state.dismissFilterTip)
                            .transition(FlixMotion.rise(reduceMotion: state.reduceMotion))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .animation(state.reduceMotion ? nil : state.motion(FlixMotion.pill), value: state.filter)
                .animation(state.motion(FlixMotion.row), value: structure)
            }
            .scrollIndicators(.never)
            .onChange(of: state.history.smartFilters.map(\.id)) { old, new in
                guard state.phase == .shown, let added = new.first(where: { !old.contains($0) }) else { return }
                bornFilter = added
                withAnimation(FlixMotion.resolved(FlixMotion.row, reduceMotion: state.reduceMotion)) {
                    proxy.scrollTo(added, anchor: .center)
                }
            }
        }
        .background(FlixStyle.pane)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.flixSidebarLabel))
    }

    // MARK: Sections

    @ViewBuilder private func activityRows(_ base: [FlixItem]) -> some View {
        ForEach(FlixFilter.Activity.allCases.filter { showsLinkFilter($0 == .links, base: base) }, id: \.self) { activity in
            row(Text(activity.title), .symbol(activity.symbol), count: base.count(where: activity.matches),
                filter: .activity(activity))
        }
    }

    @ViewBuilder private func threadRows(_ base: [FlixItem]) -> some View {
        FlixSidebarHeader(title: Text(.flixSidebarThreads), intelligent: true)
        ForEach(state.intelligence.threads) { thread in
            let members = Set(thread.memberIDs)
            row(Text(verbatim: thread.name), .emoji(thread.emoji), count: base.count { members.contains($0.id) },
                filter: .thread(thread.id))
                .help(Text(verbatim: thread.name))
                .transition(.opacity)
        }
    }

    @ViewBuilder private func kindRows(_ base: [FlixItem]) -> some View {
        FlixSidebarHeader(title: Text(.flixSidebarKinds))
        ForEach(FlixFilter.Kind.allCases.filter { showsLinkFilter($0 == .webDocuments, base: base) }, id: \.self) { kind in
            row(Text(kind.title), .symbol(kind.symbol), count: base.count(where: kind.matches), filter: .kind(kind))
        }
    }

    @ViewBuilder private func smartFilterRows(_ base: [FlixItem]) -> some View {
        FlixSidebarHeader(title: Text(.flixSidebarSmartFilters))
        ForEach(state.history.smartFilters) { filter in
            row(Text(verbatim: filter.name), .emoji(filter.emoji),
                count: base.count { filter.matches($0, now: state.now, semantic: semantic) },
                filter: .smart(filter.id), born: bornFilter == filter.id)
                .help(Text(verbatim: filter.name))
                .contextMenu {
                    Button(role: .destructive) {
                        state.removeSmartFilter(filter.id)
                    } label: { Text(.flixSmartFilterDelete) }
                }
                .id(filter.id)
                .transition(FlixMotion.rise(reduceMotion: state.reduceMotion))
        }
        FlixSidebarRow(title: Text(.flixNewSmartFilter), glyph: state.intelligence.canGenerateSmartFilters
                       ? .sparkle : .symbol("plus"), count: nil, selected: false, quiet: true) {
            state.intelligence.resetSmartFilterDraft()
            state.sheet = .smartFilter
        }
        .help(Text(.flixNewSmartFilter))
    }

    @ViewBuilder private func favoriteRows(_ base: [FlixItem]) -> some View {
        FlixSidebarHeader(title: Text(.flixSidebarFavorites))
        ForEach(state.history.favorites) { favorite in
            FlixFavoriteRow(favorite: favorite, state: state,
                            count: favorite.kind == .folder ? base.count { $0.isInside(favorite.path) } : nil,
                            selectionNamespace: selection)
                .transition(FlixMotion.rise(reduceMotion: state.reduceMotion))
        }
    }

    private func row(_ title: Text, _ glyph: FlixSidebarGlyph, count: Int, filter: FlixFilter,
                     born: Bool = false) -> some View {
        FlixSidebarRow(title: title, glyph: glyph, count: count, selected: state.filter == filter, born: born,
                       selectionNamespace: selection) { state.filter = filter }
    }

    // MARK: Inputs

    /// What makes rows come and go: the threads, Smart Filters, Favorites, and the tip.
    private var structure: [String] {
        (state.intelligence.hasThreads ? state.intelligence.threads.map(\.id) : [])
            + state.history.smartFilters.map(\.id.uuidString) + state.history.favorites.map(\.id.uuidString)
            + [state.intelligence.filterTip?.id ?? ""]
    }

    private var semantic: (String, FlixItem) -> Bool? {
        { [intelligence = state.intelligence] topic, item in intelligence.semanticMatch(topic: topic, item: item) }
    }

    /// Links and Web documents appear while web links are on, or while links are in the history.
    private func showsLinkFilter(_ isLinkFilter: Bool, base: [FlixItem]) -> Bool {
        !isLinkFilter || state.settings.tracksLinks || base.contains { $0.kind == .link }
    }

    /// The items counts are taken from: noise left out while it is hidden.
    private var baseItems: [FlixItem] {
        guard state.settings.hidesNoise, !state.showNoise else { return state.history.items }
        return state.history.items.filter {
            !(state.intelligence.annotations[$0.id]?.isNoise ?? FlixNoiseRules.isNoise(path: $0.path))
        }
    }
}

#if DEBUG
#Preview("Sidebar") {
    FlixSidebarView(state: FlixPreviewData.panelState(withIntelligence: true))
        .frame(width: FlixStyle.sidebarWidth, height: 560)
}

#Preview("Sidebar, German, light") {
    FlixSidebarView(state: FlixPreviewData.panelState(withIntelligence: true))
        .frame(width: FlixStyle.sidebarWidth, height: 560)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.light)
}

#Preview("Sidebar, plain") {
    FlixSidebarView(state: FlixPreviewData.panelState())
        .frame(width: FlixStyle.sidebarWidth, height: 420)
}
#endif
