import Foundation

/// A local recipe owns its signal threshold, calm interval, copy, destination, and snooze policy.
struct DiscoveryProposal: Identifiable {
    enum Signal: Hashable { case clipboardChanged }
    enum Destination: String { case clipboardMuseum }
    let id: String
    let signal: Signal
    let threshold: Int
    let calmInterval: TimeInterval
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let action: LocalizedStringResource
    let destination: Destination
    let snoozeInterval: TimeInterval

    static let catalog: [Self] = [
        Self(id: "clipboardMuseum", signal: .clipboardChanged, threshold: 3, calmInterval: 5,
             title: .discoveryMuseumTitle, message: .discoveryMuseumMessage,
             action: .discoveryMuseumOpen, destination: .clipboardMuseum, snoozeInterval: 86_400)
    ]
}
