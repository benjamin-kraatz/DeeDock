import SwiftUI

/// Makes a feed row swipeable: the row slides left over a red Clear action, which a click
/// commits. A folded stack's action reads Clear All and clears the whole stack.
///
/// The offset comes from ``NotificationFeedSwipeTracker``, which handles both the trackpad and
/// the mouse, so the two feel the same. Pulling right rubber-bands.
struct NotificationFeedSwipeRow<Content: View>: View {
    let id: NotificationFeedEntry.ID
    let isStack: Bool
    /// False for the peeking cards behind a folded stack.
    let isEnabled: Bool
    let tracker: NotificationFeedSwipeTracker
    @ViewBuilder let content: Content

    @State private var width: CGFloat = 0

    var body: some View {
        let reveal = tracker.reveal(for: id)
        content
            .offset(x: -reveal)
            .background(alignment: .trailing) {
                if reveal > 0 {
                    NotificationFeedSwipeAction(width: min(reveal, width), isStack: isStack) {
                        tracker.commitRevealed(id)
                    }
                }
            }
            .opacity(tracker.isCommitted(id) ? 0 : 1)
            .background { NotificationFeedSwipeProbe(id: id, isStack: isStack, isEnabled: isEnabled, tracker: tracker) }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .simultaneousGesture(drag, including: isEnabled ? .all : .subviews)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: NotificationFeedSwipePhysics.intentDistance)
            .onChanged { value in tracker.dragChanged(id, translation: value.translation, isStack: isStack) }
            .onEnded { value in tracker.dragEnded(id, velocity: value.velocity.width, isStack: isStack) }
    }
}

/// The red action uncovered behind a swiped row. The label appears once there is room for it.
private struct NotificationFeedSwipeAction: View {
    let width: CGFloat
    let isStack: Bool
    let commit: () -> Void

    var body: some View {
        Button(action: commit) {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape.fill(Color.red)
                .overlay(alignment: .trailing) {
                    Text(isStack ? .notificationFeedClearAll : .notificationFeedClearAction)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: NotificationFeedSwipePhysics.actionWidth)
                        .opacity(width > NotificationFeedSwipePhysics.labelThreshold ? 1 : 0)
                        .animation(.easeOut(duration: 0.12), value: width > NotificationFeedSwipePhysics.labelThreshold)
                }
                .frame(width: max(0, width))
                .clipShape(shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        // VoiceOver and the keyboard reach the same command through the row's own actions.
        .accessibilityHidden(true)
    }
}
