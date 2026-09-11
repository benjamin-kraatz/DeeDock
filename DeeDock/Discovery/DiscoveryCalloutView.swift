import SwiftUI

/// A quiet, static callout with native controls. No animation is required for Reduce Motion.
struct DiscoveryCalloutView: View {
    let proposal: DiscoveryProposal
    let reduceTransparency: Bool
    let open: () -> Void
    let snooze: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "building.columns.fill")
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
                Button(proposal.action, action: open).buttonStyle(.borderedProminent)
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
                         open: {}, snooze: {}, dismiss: {})
        .padding()
}

#Preview("Discovery, German opaque") {
    DiscoveryCalloutView(proposal: DiscoveryProposal.catalog[0], reduceTransparency: true,
                         open: {}, snooze: {}, dismiss: {})
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark).padding()
}
