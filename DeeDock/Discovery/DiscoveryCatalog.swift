import Foundation

/// A local recipe owns its signal threshold, calm interval, copy, destination, and snooze policy.
struct DiscoveryProposal: Identifiable {
    enum Signal: Hashable {
        case clipboardChanged
        /// Recorded once when Discovery starts. Announces a feature on the first launch that has
        /// it, and again on later launches until it is used, dismissed, or still snoozed.
        case launched
    }
    enum Destination: String { case clipboardMuseum, notificationFeed }
    /// What the callout still has to do after its destination handled the click.
    enum FollowUp { case none, openSettings }
    let id: String
    let signal: Signal
    let threshold: Int
    let calmInterval: TimeInterval
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let action: LocalizedStringResource
    let destination: Destination
    let snoozeInterval: TimeInterval
    /// The SF Symbol drawn in the callout's tile.
    var symbol = "building.columns.fill"

    static let catalog: [Self] = [
        Self(id: "clipboardMuseum", signal: .clipboardChanged, threshold: 3, calmInterval: 5,
             title: .discoveryMuseumTitle, message: .discoveryMuseumMessage,
             action: .discoveryMuseumOpen, destination: .clipboardMuseum, snoozeInterval: 86_400),
        // Waits a minute after launch, so the announcement never lands on top of start-up.
        Self(id: "notificationFeed", signal: .launched, threshold: 1, calmInterval: 60,
             title: .discoveryNotificationFeedTitle, message: .discoveryNotificationFeedMessage,
             action: .discoveryNotificationFeedTurnOn, destination: .notificationFeed, snoozeInterval: 86_400,
             symbol: "bell.badge.fill"),
    ]
}
