import SwiftUI

/// Binds the live feed to the popover's content view.
///
/// Kept separate from ``NotificationFeedPanelView`` so the content can be previewed with fixed
/// entries and every reader state, without a running reader.
struct NotificationFeedPanel: View {
    let feed: NotificationFeedController
    let state: NotificationFeedPanelState

    var body: some View {
        NotificationFeedPanelView(entries: feed.store.entries, status: feed.state, state: state)
    }
}
