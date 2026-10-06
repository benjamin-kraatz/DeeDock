import SwiftUI

/// What the popover shows before anything was collected, for each reader state.
///
/// The listening state also says which notifications the feed cannot see, so an empty feed
/// during Focus does not read as a fault.
struct NotificationFeedEmptyView: View {
    let status: NotificationFeedController.State
    let openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating, isActive: status == .waiting && !reduceMotion)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if status == .needsAccess || status == .off {
                Button(action: openSettings) { Text(.notificationFeedOpenSettings) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch status {
        case .listening: "bell.slash"
        case .waiting: "hourglass"
        case .needsAccess, .off: "lock.shield"
        }
    }

    private var title: LocalizedStringResource {
        switch status {
        case .listening: .notificationFeedEmptyTitle
        case .waiting: .notificationFeedWaitingTitle
        case .needsAccess, .off: .notificationFeedNeedsAccessTitle
        }
    }

    private var message: LocalizedStringResource {
        switch status {
        case .listening: .notificationFeedEmptyMessage
        case .waiting: .notificationFeedWaitingMessage
        case .needsAccess, .off: .notificationFeedNeedsAccessMessage
        }
    }
}

#if DEBUG
#Preview("Empty states") {
    HStack(spacing: 0) {
        NotificationFeedEmptyView(status: .listening, openSettings: {})
        Divider()
        NotificationFeedEmptyView(status: .waiting, openSettings: {})
        Divider()
        NotificationFeedEmptyView(status: .needsAccess, openSettings: {})
    }
    .frame(width: 960, height: 320)
}
#endif
