import SwiftUI

/// The coloured event part of a row's second line: "↓ Downloaded from billing.example.com".
struct FlixEventLabel: View {
    let item: FlixItem
    var selected = false
    /// Drops the "from …" part, for the caption line.
    var short = false

    static func text(for item: FlixItem, short: Bool = false) -> String {
        switch item.activity {
        case .opened: String(localized: .flixEventOpened)
        case .downloaded:
            if !short, let host = item.sourceHost { String(localized: .flixEventDownloadedFrom(host)) }
            else { String(localized: .flixEventDownloaded) }
        case .created: item.kind == .screenshot ? String(localized: .flixEventNewScreenshot) : String(localized: .flixEventNew)
        case .saved: String(localized: .flixEventSaved)
        case .link: item.link?.host ?? String(localized: .flixEventLink)
        case .kept: String(localized: .flixEventKept)
        }
    }

    var body: some View {
        Label {
            Text(Self.text(for: item, short: short))
        } icon: {
            Image(systemName: item.activity.symbol)
                .font(.system(size: 8.5, weight: .bold))
        }
        .labelStyle(FlixCompactLabelStyle())
        .fontWeight(.semibold)
        .foregroundStyle(selected ? Color.white : item.activity.tint)
    }
}

/// Icon and title with a three-point gap, for dense lines.
struct FlixCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

/// A short fact chip: "Due Dec 4" in orange, "€1,240" in green, "Needs signature" in red.
struct FlixFactChip: View {
    let fact: FlixFact
    var selected = false

    private var tint: Color? {
        switch fact.style {
        case .plain: nil
        case .due: .orange
        case .signature: .red
        case .money: .green
        }
    }

    var body: some View {
        Text(fact.text)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(selected ? Color.white : tint ?? .secondary)
            .background(selected ? Color.white.opacity(0.2) : (tint?.opacity(0.15) ?? FlixStyle.chip),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
    }
}

/// The "✦ by meaning" chip on a search result found by content rather than name.
struct FlixMeaningChip: View {
    var selected = false

    var body: some View {
        Text(.flixByMeaning)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(selected ? Color.white : FlixStyle.aiViolet)
            .background(selected ? Color.white.opacity(0.2) : FlixStyle.aiSoft,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
    }
}
