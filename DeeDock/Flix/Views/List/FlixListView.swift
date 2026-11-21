import SwiftUI

/// The scrolling activity list with the cards above it.
///
/// Cards appear only when their slot has content (``FlixListCards``).
///
/// Motion, from the mockup:
/// - On open, the cards and the first rows rise one after another (``FlixEntrance``).
/// - When the list changes, rows that stay slide to their new place (``FlixMotion/row``); rows,
///   older versions, and cards that arrive fade up eight points; those that leave fade.
/// - An item that arrives while the panel is open gets an accent rim that fades.
///
/// With Reduce Motion nothing slides: changes crossfade.
struct FlixListView: View {
    let state: FlixPanelState
    let list: FlixListResult

    /// Items that arrived while the panel was open, each highlighted until its fade ends.
    @State private var fresh: Set<FlixItem.ID> = []

    var body: some View {
        let stagger = FlixListStagger(list: list)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    FlixListCards(state: state, count: list.count)
                        .flixEntrance(0, state: state)
                    ForEach(list.sections) { section in
                        FlixGroupHeader(title: Text(section.group.title))
                            .flixEntrance(stagger.headers[section.group], state: state)
                            .transition(.opacity)
                        ForEach(section.rows) { row in
                            rowView(row)
                                .id(row.item.id)
                                .flixEntrance(stagger.rows[row.id], state: state)
                                .transition(FlixMotion.rise(reduceMotion: state.reduceMotion, index: stagger.rows[row.id]))
                        }
                    }
                    if list.sections.isEmpty, let kind = emptyKind {
                        FlixEmptyState(kind: kind)
                            .flixEntrance(1, state: state)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .animation(state.motion(FlixMotion.row), value: list.order)
                .animation(state.motion(FlixMotion.row), value: cardsKey)
            }
            .scrollIndicators(.automatic)
            // Rows scrolled past the top, for `max_scrolled_rows`. Rounded to whole rows, so the
            // callback runs once per row, not per pixel.
            .onScrollGeometryChange(for: Int.self) { geometry in
                max(0, Int(geometry.contentOffset.y / FlixStyle.rowHeight))
            } action: { _, rows in
                state.metrics?.scrolled(rows: rows)
            }
            .onChange(of: state.cursor) { _, cursor in
                guard let cursor else { return }
                withAnimation(state.reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(cursor) }
            }
            .onChange(of: state.history.items.first?.id) { old, new in markFresh(old: old, new: new) }
        }
    }

    /// Why the list is empty, or nil while a result is still loading or search waits for typing.
    private var emptyKind: FlixEmptyState.Kind? {
        if state.searchActive, state.searchText.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        if state.searchActive, state.intelligence.query == .understanding { return nil }
        if let like = state.intelligence.moreLikeThis { return like.resultIDs == nil ? nil : .nothingSimilar }
        if state.history.items.isEmpty { return .noHistory }
        if state.searchActive { return .noResults }
        return .emptyFilter
    }

    /// What the cards above the rows show, as a value: a change animates them in and out.
    private var cardsKey: [String] {
        var key: [String] = []
        switch state.intelligence.fits {
        case .hidden: break
        case .reading: key.append("fits:reading")
        case .ready(let result): key.append("fits:\(result.fits.count)")
        }
        switch state.intelligence.query {
        case .idle: break
        case .understanding: key.append("understanding")
        case .understood(let tokens, _): key.append(contentsOf: tokens.map(\.id.uuidString))
        }
        if let like = state.intelligence.moreLikeThis { key.append(like.resultIDs == nil ? "like:loading" : "like") }
        if state.intelligence.morning != nil { key.append("morning") }
        if let offer = state.pageOffer { key.append(offer.isSaved ? "page:saved" : "page") }
        if !state.foldersAwaitingAccess.isEmpty, !state.accessCardDismissed { key.append("access") }
        if state.searchActive { key.append(state.searchText.isEmpty ? "search:empty" : "search") }
        return key
    }

    /// Highlights an item that became the newest while the panel is on screen, for as long as the
    /// highlight's own fade lasts. Opening the panel or switching filters highlights nothing.
    private func markFresh(old: FlixItem.ID?, new: FlixItem.ID?) {
        guard state.phase == .shown, let new, new != old, let item = state.history.item(new) else { return }
        // The old newest item was removed: the next one moving up did not arrive.
        if let old {
            guard let previous = state.history.item(old), item.date > previous.date else { return }
        }
        fresh.insert(new)
        // Clears a view-local flag once the highlight has faded; harmless if the list is gone.
        Task {
            try? await Task.sleep(for: .seconds(1.7))
            fresh.remove(new)
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
                                    relation: item.link == nil ? nil : state.linkRelation?(item),
                                    highlight: row.match == .name && state.intelligence.query == .idle ? state.searchText : nil,
                                    isFresh: fresh.contains(item.id)),
            annotation: state.intelligence.annotation(for: item.id),
            selected: state.selection.contains(item.id),
            dimmed: state.drag?.itemIDs.contains(item.id) == true,
            now: state.now, policy: state.readPolicy, reduceMotion: state.reduceMotion,
            press: { state.press(item.id, command: $0, shift: $1) },
            click: { state.click(item.id, command: $0, shift: $1) },
            open: { state.open([item], origin: .list) },
            beginDrag: { view, event in state.beginDrag?(dragIDs(for: item.id), view, event, .list) },
            menu: { FlixContextMenu.make(for: state) },
            toggleVersions: {
                guard let group = row.versionGroup else { return }
                state.toggleVersions(group, count: row.versionCount)
            },
            moveSuggested: { state.moveToSuggestedFolder(item) },
            renameSuggested: { state.renameToSuggestion(item) },
            actions: FlixRowActions(state: state, item: item))
    }

    /// A drag carries the whole selection when it starts on a selected row.
    private func dragIDs(for id: FlixItem.ID) -> [FlixItem.ID] {
        state.selection.contains(id) ? state.navigationOrder.filter(state.selection.contains) : [id]
    }
}

/// The place of the list's first headers and rows in the opening stagger. The cards share index 0.
struct FlixListStagger {
    private(set) var headers: [FlixTimeGroup: Int] = [:]
    private(set) var rows: [String: Int] = [:]

    init(list: FlixListResult) {
        var index = 1
        for section in list.sections {
            guard index < FlixMotion.staggerCount else { return }
            headers[section.group] = index
            index += 1
            for row in section.rows {
                guard index < FlixMotion.staggerCount else { return }
                rows[row.id] = index
                index += 1
            }
        }
    }
}

/// "Just Now", "Today", …
struct FlixGroupHeader: View {
    let title: Text

    var body: some View {
        title
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(FlixStyle.faint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 3)
            .accessibilityAddTraits(.isHeader)
    }
}
