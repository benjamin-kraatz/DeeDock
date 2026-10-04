import SwiftUI

/// The island's title and message. The copy dissolves through blur when the callout kind
/// or the phase changes.
struct UpdateIslandHeadline: View {
    let model: UpdateIslandModel
    let presentation: UpdatePresentation

    private struct Copy {
        let id: AnyHashable
        let title: LocalizedStringResource
        let message: LocalizedStringResource
    }

    /// Nil once a session has ended, so the island empties before it folds away instead of
    /// flashing idle copy.
    private var copy: Copy? {
        switch model.content {
        case .callout(let announcement):
            let version = announcement.version
            switch announcement.kind {
            case .available:
                return Copy(id: "available", title: .updatesAwarenessTitle,
                            message: .updatesAwarenessBody(version: version))
            case .ready:
                return Copy(id: "ready", title: .updatesReadyCalloutTitle,
                            message: .updatesReadyCalloutBody(version: version))
            case .installed:
                return Copy(id: "installed", title: .updatesInstalledCalloutTitle,
                            message: .updatesInstalledCalloutBody(version: version))
            }
        case .panel:
            guard presentation.phase != .idle else { return nil }
            return Copy(id: presentation.phase, title: presentation.title, message: presentation.summary)
        }
    }

    /// The panel names the offer's version beside its title while that offer is in play.
    /// A callout already has it in its message.
    private var offerVersion: String? {
        guard model.content == .panel,
              [.available, .downloading, .extracting, .ready].contains(presentation.phase) else { return nil }
        return presentation.offer?.version
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let copy {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(copy.title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        if let offerVersion {
                            UpdateVersionBadge(version: offerVersion)
                        }
                    }
                    Text(copy.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id(copy.id)
                .transition(.blurReplace)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Round close button at the island's trailing edge.
struct UpdateIslandCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(.updatesAwarenessDismiss, systemImage: "xmark", action: action)
            .labelStyle(.iconOnly)
            .tint(.secondary)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .help(Text(.updatesAwarenessDismiss))
    }
}

/// The phase's details under a hairline that sets them off from the header.
///
/// The island is only as tall as the details need. They scroll once they outgrow the height
/// the canvas offers.
struct UpdateIslandDetails: View {
    let presentation: UpdatePresentation
    let awareness: UpdateAwarenessStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            // A bare ScrollView would claim all offered height for a two-line phase, and a
            // flexible frame around this would centre short details in it.
            ViewThatFits(in: .vertical) {
                details
                ScrollView { details }
                    .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var details: some View {
        UpdatePanelDetails(presentation: presentation, awareness: awareness)
            // Body text and the idle switch must not inherit the island's large controls.
            .controlSize(.regular)
    }
}

/// The phase's actions along the island's bottom edge. Each action is tied to the callback
/// generation that produced this row.
struct UpdateIslandActions: View {
    let presentation: UpdatePresentation
    let action: (UpdateAction, UUID) -> Void

    var body: some View {
        let token = presentation.actionToken
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                buttons(token: token)
            }
            VStack(alignment: .trailing, spacing: 10) { buttons(token: token) }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonBorderShape(.capsule)
    }

    @ViewBuilder private func buttons(token: UUID) -> some View {
        ForEach(presentation.actions, id: \.self) { item in
            if item == presentation.actions.last {
                Button(presentation.title(for: item)) { action(item, token) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(presentation.title(for: item)) { action(item, token) }
                    .buttonStyle(.bordered)
            }
        }
    }
}
