import SwiftUI

/// One search hit: a preview tile, the window title, and the evidence that produced the match.
///
/// The row carries its own selection appearance rather than a list selection so keyboard movement
/// from the query field looks identical to pointer selection.
struct WindowSearchResultView: View {
    let result: WindowSearchResult
    let thumbnail: CGImage?
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    private var icon: NSImage? {
        guard let pid = result.source?.processIdentifier else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.icon
    }
    /// Metadata hits repeat the title in their excerpt, so only content evidence adds a line.
    private var showsExcerpt: Bool {
        switch result.evidence {
        case .metadata: false
        case .text, .capsule, .historicalOCR, .image: !result.excerpt.isEmpty
        }
    }
    private var opensAppOnly: Bool {
        guard let source = result.source else { return false }
        return source.window == nil && (source.candidate == nil || source.candidate?.id == 0)
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                WindowSearchThumbnailView(thumbnail: thumbnail, icon: icon,
                                          fallbackSymbol: result.capsuleID == nil ? "macwindow" : "archivebox")
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: result.title)
                        .font(.headline)
                        .lineLimit(1)
                    provenance
                    if showsExcerpt {
                        Text(verbatim: result.excerpt)
                            .font(.callout)
                            .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if opensAppOnly {
                        Label { Text(.windowSearchAppOnly) } icon: { Image(systemName: "arrow.up.forward.app") }
                            .font(.caption)
                            .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if let date = result.date {
                    Text(date, format: .dateTime.day().month().hour().minute())
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: .rect(cornerRadius: WindowSearchStyle.rowCorner))
            .contentShape(.rect(cornerRadius: WindowSearchStyle.rowCorner))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var background: AnyShapeStyle {
        if selected { return AnyShapeStyle(Color.accentColor) }
        if hovered { return AnyShapeStyle(.quaternary.opacity(0.6)) }
        return AnyShapeStyle(.quaternary.opacity(0.25))
    }

    /// App identity and evidence share one line so the row keeps a predictable height.
    private var provenance: some View {
        HStack(spacing: 6) {
            if !result.applicationName.isEmpty {
                Text(verbatim: result.applicationName)
                Text(verbatim: "·")
            }
            Image(systemName: result.evidence.symbol)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(result.evidence.tint))
            Text(result.evidence.label)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
        .lineLimit(1)
    }
}

/// A captured preview when one exists, and the app's icon when it does not.
///
/// Captured images stay in memory only, so the tile must render an honest placeholder rather than
/// implying a screenshot was taken.
struct WindowSearchThumbnailView: View {
    let thumbnail: CGImage?
    let icon: NSImage?
    var fallbackSymbol = "macwindow"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.7))
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: WindowSearchStyle.thumbnailSize.width, height: WindowSearchStyle.thumbnailSize.height)
        .clipShape(.rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        }
        .overlay(alignment: .bottomLeading) {
            if thumbnail != nil, let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
                    .frame(width: 18, height: 18)
                    .padding(4)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Result states") {
    VStack(spacing: 10) {
        WindowSearchResultView(result: WindowSearchResult(id: UUID(), title: "Invoice September",
            applicationName: "Preview", evidence: .text, excerpt: "Invoice 1042 · Total €125.00",
            score: 100, date: Date(timeIntervalSince1970: 1_788_768_000), source: nil, capsuleID: nil),
            thumbnail: nil, selected: true, action: {})
        WindowSearchResultView(result: WindowSearchResult(id: UUID(), title: "…/Projects/dzwei/DeeDock",
            applicationName: "Ghostty", evidence: .metadata, excerpt: "…/Projects/dzwei/DeeDock",
            score: 60, date: nil, source: nil, capsuleID: nil),
            thumbnail: nil, selected: false, action: {})
        WindowSearchResultView(result: WindowSearchResult(id: UUID(), title: "Quarterly review",
            applicationName: "Numbers", evidence: .image, excerpt: "A bar chart with an orange series",
            score: -1, date: Date(), source: nil, capsuleID: nil),
            thumbnail: nil, selected: false, action: {})
    }
    .padding()
    .frame(width: 640)
}
