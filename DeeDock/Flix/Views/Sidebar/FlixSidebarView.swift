import SwiftUI

/// The sidebar: activity types, ✦ Threads, kinds, Smart Filters, Favorites, and the ✦ tip card.
///
/// Counts follow the noise switch. Favorites take drops of Flix rows: a folder moves them there
/// (with Undo), an app opens them with it.
struct FlixSidebarView: View {
    let state: FlixPanelState

    var body: some View {
        let base = baseItems
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(FlixFilter.Activity.allCases.filter { showsLinkFilter($0 == .links, base: base) }, id: \.self) { activity in
                    FlixSidebarRow(title: Text(activity.title), glyph: .symbol(activity.symbol),
                                   count: base.count(where: activity.matches),
                                   selected: state.filter == .activity(activity)) { state.filter = .activity(activity) }
                }
                if state.intelligence.hasThreads {
                    FlixSidebarHeader(title: Text(.flixSidebarThreads), intelligent: true)
                    ForEach(state.intelligence.threads) { thread in
                        let members = Set(thread.memberIDs)
                        FlixSidebarRow(title: Text(verbatim: thread.name), glyph: .emoji(thread.emoji),
                                       count: base.count { members.contains($0.id) },
                                       selected: state.filter == .thread(thread.id)) { state.filter = .thread(thread.id) }
                    }
                }
                FlixSidebarHeader(title: Text(.flixSidebarKinds))
                ForEach(FlixFilter.Kind.allCases.filter { showsLinkFilter($0 == .webDocuments, base: base) }, id: \.self) { kind in
                    FlixSidebarRow(title: Text(kind.title), glyph: .symbol(kind.symbol),
                                   count: base.count(where: kind.matches),
                                   selected: state.filter == .kind(kind)) { state.filter = .kind(kind) }
                }
                FlixSidebarHeader(title: Text(.flixSidebarSmartFilters))
                ForEach(state.history.smartFilters) { filter in
                    FlixSidebarRow(title: Text(verbatim: filter.name), glyph: .emoji(filter.emoji),
                                   count: base.count { filter.matches($0, now: state.now, semantic: semantic) },
                                   selected: state.filter == .smart(filter.id)) { state.filter = .smart(filter.id) }
                        .contextMenu {
                            Button(role: .destructive) {
                                if state.filter == .smart(filter.id) { state.filter = .all }
                                state.history.removeSmartFilter(filter.id)
                            } label: { Text(.flixSmartFilterDelete) }
                        }
                }
                FlixSidebarRow(title: Text(.flixNewSmartFilter), glyph: state.intelligence.canGenerateSmartFilters
                               ? .sparkle : .symbol("plus"), count: nil, selected: false, quiet: true) {
                    state.intelligence.resetSmartFilterDraft()
                    state.sheet = .smartFilter
                }
                if !state.history.favorites.isEmpty {
                    FlixSidebarHeader(title: Text(.flixSidebarFavorites))
                    ForEach(state.history.favorites) { favorite in
                        FlixFavoriteRow(favorite: favorite, state: state,
                                        count: favorite.kind == .folder ? base.count { $0.isInside(favorite.path) } : nil)
                    }
                }
                if let tip = state.intelligence.filterTip {
                    FlixFilterTipCard(tip: tip, make: {
                        state.intelligence.dismissFilterTip()
                        state.addSmartFilter(tip.proposal)
                    }, dismiss: state.intelligence.dismissFilterTip)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.never)
        .background(Color.primary.opacity(0.035))
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
#endif
