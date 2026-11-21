import SwiftUI

/// The scrolling activity list with the cards above it.
///
/// Cards appear only when their slot has content: the folder access card and the morning card on
/// the plain list, the Fits card while the window in front is read, the thread card for a Thread,
/// the search head while searching. Rows move with a spring when the list changes; with Reduce
/// Motion they crossfade.
struct FlixListView: View {
    let state: FlixPanelState
    let list: FlixListResult

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    cards
                    ForEach(list.sections) { section in
                        FlixGroupHeader(title: Text(section.group.title))
                        ForEach(section.rows) { row in
                            rowView(row).id(row.item.id)
                        }
                    }
                    if list.sections.isEmpty && !(state.searchActive && state.searchText.isEmpty) {
                        FlixEmptyState(searching: state.searchActive || state.filter != .all,
                                       historyEmpty: state.history.items.isEmpty)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .animation(state.reduceMotion ? .easeOut(duration: 0.15) : FlixStyle.rowSpring, value: list.order)
            }
            .scrollIndicators(.automatic)
            .onChange(of: state.cursor) { _, cursor in
                guard let cursor else { return }
                withAnimation(state.reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(cursor) }
            }
        }
    }

    @ViewBuilder private var cards: some View {
        if state.searchActive {
            FlixSearchHead(state: state)
        }
        if let like = state.intelligence.moreLikeThis, let source = state.history.item(like.sourceID) {
            FlixMoreLikeThisBar(name: source.name, count: like.resultIDs?.count, loading: like.resultIDs == nil,
                                clear: state.intelligence.clearMoreLikeThis)
        }
        if case .thread(let id) = state.filter, !state.searchActive, let thread = state.intelligence.thread(id) {
            FlixThreadCard(thread: thread, count: list.count, state: state)
        }
        if state.isPlainList {
            if !state.foldersAwaitingAccess.isEmpty, !state.accessCardDismissed {
                FlixFolderAccessCard(folders: state.foldersAwaitingAccess,
                                     allow: { state.requestFolderAccess?($0) },
                                     dismiss: { state.accessCardDismissed = true })
            }
            if let morning = state.intelligence.morning {
                FlixMorningCardView(card: morning, run: { run($0) }, dismiss: state.intelligence.dismissMorning)
            }
            if let offer = state.pageOffer {
                FlixSavePageCard(offer: offer, save: { state.savePage?() })
            }
            FlixFitsSection(state: state)
        }
    }

    private func rowView(_ row: FlixListRow) -> some View {
        let item = row.item
        return FlixRowView(
            item: item,
            context: FlixRowContext(match: row.match, isChild: row.isChild, versionCount: row.versionCount,
                                    versionGroup: row.versionGroup,
                                    isExpanded: row.versionGroup.map(state.expandedVersions.contains) ?? false,
                                    isNoise: row.isNoise,
                                    relation: item.link == nil ? nil : state.linkRelation?(item)),
            annotation: state.intelligence.annotation(for: item.id),
            selected: state.selection.contains(item.id),
            dimmed: state.drag?.itemIDs.contains(item.id) == true,
            now: state.now, policy: state.readPolicy,
            press: { state.press(item.id, command: $0, shift: $1) },
            click: { state.click(item.id, command: $0, shift: $1) },
            open: { state.open([item]) },
            beginDrag: { view, event in state.beginDrag?(dragIDs(for: item.id), view, event) },
            menu: { FlixContextMenu.make(for: state) },
            toggleVersions: {
                guard let group = row.versionGroup else { return }
                if state.expandedVersions.contains(group) { state.expandedVersions.remove(group) }
                else { state.expandedVersions.insert(group) }
            },
            moveSuggested: {
                guard let folder = state.intelligence.annotation(for: item.id)?.folderSuggestion else { return }
                state.move([item], into: URL(fileURLWithPath: folder))
            },
            renameSuggested: {
                guard let name = state.intelligence.annotation(for: item.id)?.renameSuggestion else { return }
                state.rename(item, to: name)
            })
    }

    /// A drag carries the whole selection when it starts on a selected row.
    private func dragIDs(for id: FlixItem.ID) -> [FlixItem.ID] {
        state.selection.contains(id) ? state.navigationOrder.filter(state.selection.contains) : [id]
    }

    private func run(_ action: FlixMorningCard.Action) {
        state.intelligence.dismissMorning()
        switch action.target {
        case .open(let ids): state.open(ids.compactMap(state.history.item))
        case .filter(let filter): state.filter = filter
        }
    }
}

/// "Just Now", "Today", …
struct FlixGroupHeader: View {
    let title: Text

    var body: some View {
        title
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Nothing to show: an empty history, or a filter or search that matches nothing.
struct FlixEmptyState: View {
    let searching: Bool
    let historyEmpty: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(historyEmpty ? .flixEmptyTitle : .flixNothingMatchesTitle)
                .font(.system(size: 14, weight: .semibold))
            Text(historyEmpty ? .flixEmptyMessage : .flixNothingMatchesMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 20)
    }
}
