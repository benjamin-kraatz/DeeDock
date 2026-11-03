import SwiftUI

/// One sender's notifications: a plain row for a single entry, a stack for several.
///
/// A click or → unfolds a stack in place under a small header; Show Less or ← folds it back.
/// The stack's ✕, its header's ✕, and its context menu clear the sender's notifications, folding
/// the rows into the front card before it fades. A folded stack swipes as a whole.
struct NotificationFeedGroupView: View {
    let group: NotificationFeedGroup
    let now: Date
    let state: NotificationFeedPanelState
    let reduceMotion: Bool

    @State private var hovered = false

    private var isExpanded: Bool { state.isExpanded(group) }
    private var motion: Animation? { NotificationFeedMotion.layout(reduceMotion: reduceMotion) }

    var body: some View {
        VStack(spacing: 6) {
            if isExpanded {
                NotificationFeedGroupHeader(
                    sender: group.appName ?? String(localized: .notificationFeedSystemSender),
                    count: group.entries.count,
                    showsClear: hovered,
                    showLess: { withAnimation(motion) { state.setExpanded(group, false) } },
                    clear: { state.clearGroup?(group, .hoverX) })
                .transition(.opacity.animation(.easeOut(duration: reduceMotion ? 0.15 : 0.22)))
            }
            NotificationFeedStackLayout(isExpanded: isExpanded || !group.isStack) {
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, at: index)
                        .id(entry.id)
                        .zIndex(Double(-index))
                        .transition(state.leaveStyle(for: entry.id).transition(edge: state.chrome.edge,
                                                                               reduceMotion: reduceMotion))
                }
            }
        }
        .onHover { hovered = $0 }
    }

    private func row(_ entry: NotificationFeedEntry, at index: Int) -> some View {
        let placement = NotificationFeedRowPlacement(index: index, count: group.entries.count,
                                                     isFolded: group.isStack && !isExpanded)
        let application = state.application?(entry)
        return NotificationFeedSwipeRow(id: entry.id, isStack: placement.isStackFront, isEnabled: !placement.isPeek,
                                        tracker: state.swipe) {
            NotificationFeedRow(entry: entry,
                                icon: application.flatMap { state.icon?($0) },
                                now: now,
                                isNew: state.unreadOnOpen.contains(entry.id),
                                isSelected: state.selection == entry.id,
                                placement: placement,
                                actions: actions(for: entry, placement: placement, canOpen: application != nil))
        }
    }

    private func actions(for entry: NotificationFeedEntry, placement: NotificationFeedRowPlacement,
                         canOpen: Bool) -> NotificationFeedRowActions {
        let open: (() -> Void)? = canOpen ? { state.open?(entry) } : nil
        let expand = { withAnimation(motion) { state.setExpanded(group, true) } }
        return NotificationFeedRowActions(
            primary: {
                // The release of a swipe is not a click, and a click elsewhere first closes an open swipe.
                guard !state.swipe.swallowsTap else { return }
                if state.swipe.hasRevealed { state.swipe.closeRevealed(); return }
                if placement.isStackFront {
                    state.selection = entry.id
                    expand()
                } else {
                    open?()
                }
            },
            open: open,
            copy: { state.copy?(entry) },
            dismiss: { method in
                if placement.isStackFront { state.clearGroup?(group, method) }
                else { state.remove?(entry.id, method) }
            },
            expand: placement.isStackFront ? expand : nil,
            collapse: group.isStack && isExpanded
                ? { withAnimation(motion) { state.setExpanded(group, false) } } : nil)
    }
}
