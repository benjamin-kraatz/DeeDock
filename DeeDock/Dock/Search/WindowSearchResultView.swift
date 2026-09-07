import SwiftUI

/// Reuses Window Peek's card artwork without its hover capture lifecycle.
struct WindowSearchResultView: View {
    let result: WindowSearchResult
    let thumbnail: CGImage?
    let selected: Bool
    let action: () -> Void

    private var summary: ApplicationWindowSummary {
        result.source?.window ?? ApplicationWindowSummary(
            token: ApplicationWindowToken(sessionID: result.id, id: result.id),
            processIdentifier: result.source?.processIdentifier ?? 0, title: result.title,
            frame: nil, isMinimized: false, isMain: false)
    }
    private var icon: NSImage {
        if let pid = result.source?.processIdentifier,
           let image = NSRunningApplication(processIdentifier: pid)?.icon { return image }
        return NSImage(systemSymbolName: result.capsuleID == nil ? "macwindow" : "archivebox", accessibilityDescription: nil) ?? NSImage()
    }
    private var settings: DockSettings {
        var settings = DockSettings.defaults
        settings.windowPeekLayout = .list
        settings.windowPeekStyle = .captioned
        return settings
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            WindowPeekCardView(card: WindowPeekCard(window: summary, thumbnail: thumbnail),
                appIcon: icon, settings: settings, selected: selected, action: action)
                .frame(width: 230, height: 100)
                .accessibilityLabel(Text(verbatim: result.applicationName + " " + result.title))
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: result.applicationName).font(.headline)
                Text(result.evidence.label).font(.caption.weight(.semibold))
                Text(verbatim: result.excerpt).font(.callout).lineLimit(4)
                if let date = result.date {
                    Text(date, format: .dateTime.year().month().day().hour().minute()).font(.caption)
                }
                if let source = result.source, source.window == nil, source.candidate?.id == 0 || source.candidate == nil {
                    Text(.windowSearchAppOnly).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

#Preview("Search evidence") {
    WindowSearchResultView(result: WindowSearchResult(id: UUID(), title: "Invoice September",
        applicationName: "Preview", evidence: .text, excerpt: "Invoice 1042 · Total €125.00",
        score: 100, date: Date(timeIntervalSince1970: 1_788_768_000), source: nil, capsuleID: nil),
        thumbnail: nil, selected: true, action: {})
        .padding().frame(width: 680)
}
