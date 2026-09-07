import SwiftUI

/// A dated text preview and explicit navigation for a saved source. It never captures on appearance.
struct SessionBreadcrumbSourceView: View {
    let reference: SessionCapsuleWindowReference
    let navigator: SessionCapsuleSourceNavigator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: reference.windowTitle ?? reference.applicationName).font(.headline)
            Text(verbatim: reference.applicationName).font(.caption).foregroundStyle(.secondary)
            statusLabel.font(.caption).foregroundStyle(.secondary)
            if let time = reference.capturedAt ?? reference.observedAt {
                Text(time, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(.breadcrumbUnknownDate).font(.caption).foregroundStyle(.secondary)
            }
            if let preview = reference.textPreview {
                Text(.breadcrumbHistoricalPreview).font(.caption.weight(.semibold))
                Text(verbatim: preview).font(.callout).textSelection(.enabled)
            } else {
                Text(.breadcrumbNoPreview).font(.caption).foregroundStyle(.secondary)
            }
            if let link = reference.link, reference.reopeningURL != nil {
                Text(verbatim: link).font(.caption).lineLimit(2).textSelection(.enabled)
            }
            if let name = reference.documentName {
                Text(verbatim: name).font(.caption).textSelection(.enabled)
            }
            ViewThatFits(in: .horizontal) {
                HStack { actions }
                VStack(alignment: .leading) { actions }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .capsuleReadingCard()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var statusLabel: some View {
        switch navigator.statuses[reference.id] ?? .checking {
        case .checking: Text(.breadcrumbChecking)
        case .available: Text(.breadcrumbMatchAvailable)
        case .unavailable: Text(.breadcrumbWindowStale)
        case .unverified: Text(.breadcrumbWindowUnverified)
        case .ambiguous: Text(.breadcrumbWindowAmbiguous)
        }
    }

    @ViewBuilder private var actions: some View {
        Button(.breadcrumbShowWindow) { navigator.showWindow(reference) }
            .disabled(navigator.statuses[reference.id] != .available)
        Button(.breadcrumbOpenApp) { navigator.openApp(reference) }
            .disabled(reference.bundleIdentifier == nil)
        if reference.reopeningURL != nil {
            Button(.breadcrumbOpenLink) { navigator.openLink(reference) }
                .help(reference.link ?? "")
        }
        if reference.documentBookmark != nil {
            Button(.breadcrumbOpenDocument) { navigator.openDocument(reference) }
                .help(reference.documentName ?? "")
        }
    }
}
