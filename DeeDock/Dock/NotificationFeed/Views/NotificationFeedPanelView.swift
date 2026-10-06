import SwiftUI

/// The notification feed popover: a header with the count and Clear, then the collected banners,
/// newest first.
///
/// Rows slide in from the top as banners arrive and fold away when removed or cleared. Reduce
/// Motion swaps the movement for a cross-fade; Reduce Transparency draws an opaque panel.
struct NotificationFeedPanelView: View {
    let entries: [NotificationFeedEntry]
    let status: NotificationFeedController.State
    let state: NotificationFeedPanelState
    var forceOpaqueBackground = false

    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Stable start for the relative-time refresh. Recreating it from `.now` would skip ticks.
    @State private var timelineAnchor = Date()

    private var motion: Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)
    }

    var body: some View {
        VStack(spacing: 0) {
            NotificationFeedHeader(count: entries.count, clear: { withAnimation(motion) { state.clearAll?() } })
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
        .dockPopoverChrome(state.chrome, opaque: reduceTransparency || forceOpaqueBackground)
    }

    @ViewBuilder private var content: some View {
        if entries.isEmpty {
            NotificationFeedEmptyView(status: status, openSettings: {
                state.prepareSettings?()
                openWindow.openDockSettings()
            })
            .transition(.opacity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    TimelineView(.periodic(from: timelineAnchor, by: 30)) { context in
                        VStack(spacing: 6) {
                            ForEach(entries) { entry in
                                row(entry, now: context.date)
                                    .id(entry.id)
                                    .transition(rowTransition)
                            }
                        }
                        .padding(10)
                    }
                }
                .scrollIndicators(.automatic)
                .onChange(of: state.selection) { _, selection in
                    guard let selection else { return }
                    withAnimation(motion) { proxy.scrollTo(selection) }
                }
            }
        }
    }

    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity
            : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                          removal: .scale(scale: 0.92).combined(with: .opacity))
    }

    private func row(_ entry: NotificationFeedEntry, now: Date) -> some View {
        let application = state.application?(entry)
        return NotificationFeedRow(
            entry: entry,
            icon: application.flatMap { state.icon?($0) },
            now: now,
            isNew: state.unreadOnOpen.contains(entry.id),
            isSelected: state.selection == entry.id,
            canOpen: application != nil,
            open: { state.open?(entry) },
            copy: { state.copy?(entry) },
            remove: { withAnimation(motion) { state.remove?(entry.id) } })
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
#Preview("Feed with entries") {
    NotificationFeedPanelView(entries: NotificationFeedPreviewData.entries, status: .listening,
                              state: NotificationFeedPreviewData.state())
        .frame(width: 380, height: 480)
}

#Preview("Feed, selection, dark") {
    let state = NotificationFeedPreviewData.state()
    state.selection = NotificationFeedPreviewData.entries[1].id
    return NotificationFeedPanelView(entries: NotificationFeedPreviewData.entries, status: .listening, state: state)
        .frame(width: 380, height: 480)
        .preferredColorScheme(.dark)
}

#Preview("Feed, opaque, German") {
    NotificationFeedPanelView(entries: NotificationFeedPreviewData.entries, status: .listening,
                              state: NotificationFeedPreviewData.state(), forceOpaqueBackground: true)
        .frame(width: 380, height: 480)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Empty") {
    NotificationFeedPanelView(entries: [], status: .listening, state: NotificationFeedPreviewData.state())
        .frame(width: 380, height: 480)
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
