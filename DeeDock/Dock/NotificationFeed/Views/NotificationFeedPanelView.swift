import SwiftUI

/// The notification feed popover: a header with the count and Clear All, then the collected
/// banners grouped by sender, newest first.
///
/// Rows slide in from the top as banners arrive. Leaving rows animate by what removed them:
/// they shrink away, drop toward the dock when their app opened, or fly out under a swipe; the
/// rest spring into place. Reduce Motion swaps every movement for a 150 ms cross-fade; Reduce
/// Transparency draws an opaque panel.
struct NotificationFeedPanelView: View {
    let entries: [NotificationFeedEntry]
    let status: NotificationFeedController.State
    let state: NotificationFeedPanelState
    var forceOpaqueBackground = false
    /// Exercises the Reduce Motion path in previews, which cannot set the system preference.
    var forceReduceMotion = false

    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Stable start for the relative-time refresh. Recreating it from `.now` would skip ticks.
    @State private var timelineAnchor = Date()

    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }
    private var motion: Animation? { NotificationFeedMotion.layout(reduceMotion: reduceMotion) }

    var body: some View {
        VStack(spacing: 0) {
            NotificationFeedHeader(count: entries.count, clear: { state.clearAll?() })
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            Divider().opacity(entries.isEmpty ? 0 : 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            NotificationFeedFooter()
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
        }
        .animation(motion, value: entries.map(\.id))
        .animation(motion, value: state.selection)
        .animation(motion, value: state.expanded)
        .dockPopoverChrome(state.chrome, opaque: reduceTransparency || forceOpaqueBackground)
    }

    @ViewBuilder private var content: some View {
        if entries.isEmpty {
            NotificationFeedEmptyView(status: status, openSettings: {
                state.prepareSettings?()
                openWindow.openDockSettings()
            })
            .transition(.opacity.animation(.easeOut(duration: reduceMotion ? 0.15 : 0.25)))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    TimelineView(.periodic(from: timelineAnchor, by: 30)) { context in
                        VStack(spacing: 6) {
                            ForEach(NotificationFeedGrouping.groups(entries)) { group in
                                NotificationFeedGroupView(group: group, now: context.date, state: state,
                                                          reduceMotion: reduceMotion)
                                    .transition(state.leaveStyle(for: group.front.id)
                                        .transition(edge: state.chrome.edge, reduceMotion: reduceMotion))
                            }
                        }
                        .padding(10)
                    }
                }
                .scrollIndicators(.automatic)
                // Scrolls only on an explicit request from keyboard navigation. Selection changes
                // from arrivals and removals must not move the list under the person's pointer.
                .onChange(of: state.scrollRequest) { _, request in
                    guard let request else { return }
                    withAnimation(motion) { proxy.scrollTo(request.target) }
                }
            }
        }
    }
}

/// A one-line reminder of how the feed handles what it reads.
private struct NotificationFeedFooter: View {
    var body: some View {
        Label { Text(.notificationFeedPrivacyFootnote) } icon: { Image(systemName: "lock.fill") }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Grouped") {
    NotificationFeedPanelView(entries: NotificationFeedPreviewData.entries, status: .listening,
                              state: NotificationFeedPreviewData.state())
        .frame(width: 380, height: 480)
}

#Preview("Grouped, dark, selection") {
    let state = NotificationFeedPreviewData.state()
    state.selection = NotificationFeedPreviewData.entries[3].id
    return NotificationFeedPanelView(entries: NotificationFeedPreviewData.entries, status: .listening, state: state)
        .frame(width: 380, height: 480)
        .preferredColorScheme(.dark)
}

#Preview("Expanded stack") {
    let state = NotificationFeedPreviewData.state()
    if let mail = NotificationFeedGrouping.groups(NotificationFeedPreviewData.entries).first(where: { $0.appName == "Mail" }) {
        state.setExpanded(mail, true)
    }
    return NotificationFeedPanelView(entries: NotificationFeedPreviewData.entries, status: .listening, state: state)
        .frame(width: 380, height: 480)
}

#Preview("Expanded stack, dark, German") {
    let state = NotificationFeedPreviewData.state()
    if let messages = NotificationFeedGrouping.groups(NotificationFeedPreviewData.entries).first(where: { $0.appName == "Messages" }) {
        state.setExpanded(messages, true)
    }
    return NotificationFeedPanelView(entries: NotificationFeedPreviewData.entries, status: .listening, state: state)
        .frame(width: 380, height: 480)
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Grouped, opaque, dark") {
    NotificationFeedPanelView(entries: NotificationFeedPreviewData.entries, status: .listening,
                              state: NotificationFeedPreviewData.state(), forceOpaqueBackground: true)
        .frame(width: 380, height: 480)
        .preferredColorScheme(.dark)
}

#Preview("Mid-swipe, light") {
    let state = NotificationFeedPreviewData.state()
    state.swipe.previewReveal(NotificationFeedPreviewData.entries[1].id, by: 96)
    return NotificationFeedPanelView(entries: NotificationFeedPreviewData.entries, status: .listening, state: state)
        .frame(width: 380, height: 480)
        .preferredColorScheme(.light)
}

#Preview("Stack swipe, dark") {
    let state = NotificationFeedPreviewData.state()
    state.swipe.previewReveal(NotificationFeedPreviewData.entries[3].id, by: NotificationFeedSwipePhysics.actionWidth)
    return NotificationFeedPanelView(entries: NotificationFeedPreviewData.entries, status: .listening, state: state)
        .frame(width: 380, height: 480)
        .preferredColorScheme(.dark)
}

#Preview("Ungrouped, opaque, German") {
    NotificationFeedPanelView(entries: NotificationFeedPreviewData.singleEntries, status: .listening,
                              state: NotificationFeedPreviewData.state(), forceOpaqueBackground: true)
        .frame(width: 380, height: 480)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Reduce Motion") {
    NotificationFeedPanelView(entries: NotificationFeedPreviewData.entries, status: .listening,
                              state: NotificationFeedPreviewData.state(), forceReduceMotion: true)
        .frame(width: 380, height: 480)
}

#Preview("Empty") {
    NotificationFeedPanelView(entries: [], status: .listening, state: NotificationFeedPreviewData.state())
        .frame(width: 380, height: 480)
}

#Preview("Empty, dark") {
    NotificationFeedPanelView(entries: [], status: .listening, state: NotificationFeedPreviewData.state())
        .frame(width: 380, height: 480)
        .preferredColorScheme(.dark)
}

#Preview("Needs access") {
    NotificationFeedPanelView(entries: [], status: .needsAccess, state: NotificationFeedPreviewData.state())
        .frame(width: 380, height: 480)
}

#Preview("Waiting, German") {
    NotificationFeedPanelView(entries: [], status: .waiting, state: NotificationFeedPreviewData.state())
        .frame(width: 380, height: 480)
        .environment(\.locale, Locale(identifier: "de"))
}
#endif
