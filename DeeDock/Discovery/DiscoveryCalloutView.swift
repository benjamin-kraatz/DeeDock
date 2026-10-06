import SwiftUI

/// A quiet, static callout with native controls. No animation is required for Reduce Motion.
struct DiscoveryCalloutView: View {
    let proposal: DiscoveryProposal
    let reduceTransparency: Bool
    /// Handles the primary button. Settings opens here because only a view has `openWindow`.
    let open: () -> DiscoveryProposal.FollowUp
    let snooze: () -> Void
    let dismiss: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: proposal.symbol)
                    .font(.title).foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(.tint.opacity(0.12), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(.discoveryTitle).font(.caption).foregroundStyle(.secondary)
                    Text(proposal.title).font(.headline)
                }
            }
            Text(proposal.message).font(.body).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(proposal.action) {
                    if open() == .openSettings { openWindow.openDockSettings() }
                }
                .buttonStyle(.borderedProminent)
                Button(.discoverySnooze, action: snooze).buttonStyle(.bordered)
            }
            Button(.discoveryDismiss, action: dismiss)
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 360, alignment: .leading)
        .background {
            if reduceTransparency { RoundedRectangle(cornerRadius: 22).fill(Color(nsColor: .windowBackgroundColor)) }
            else { RoundedRectangle(cornerRadius: 22).fill(.regularMaterial) }
        }
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.12)) }
        .onExitCommand(perform: snooze)
    }
}

#Preview("Discovery") {
    DiscoveryCalloutView(proposal: DiscoveryProposal.catalog[0], reduceTransparency: false,
                         open: { .none }, snooze: {}, dismiss: {})
        .padding()
}

#Preview("Notification feed announcement") {
    DiscoveryCalloutView(proposal: DiscoveryProposal.catalog[1], reduceTransparency: false,
                         open: { .none }, snooze: {}, dismiss: {})
        .padding()
}

#Preview("Notification feed announcement, German dark") {
    DiscoveryCalloutView(proposal: DiscoveryProposal.catalog[1], reduceTransparency: false,
                         open: { .none }, snooze: {}, dismiss: {})
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark).padding()
}

#Preview("Discovery, German opaque") {
    DiscoveryCalloutView(proposal: DiscoveryProposal.catalog[0], reduceTransparency: true,
                         open: { .none }, snooze: {}, dismiss: {})
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark).padding()
}
