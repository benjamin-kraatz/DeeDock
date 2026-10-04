import SwiftUI

/// The plain-language account of what is and is not collected, shared by Settings and the tour
/// so the two can never disagree.
enum AnalyticsDisclosure {
    struct Item: Identifiable {
        let symbol: String
        let text: LocalizedStringResource
        var id: String { text.key }
    }

    static let collected: [Item] = [
        Item(symbol: "cursorarrow.click.2", text: .analyticsCollectedFeatures),
        Item(symbol: "slider.horizontal.3", text: .analyticsCollectedSettings),
        Item(symbol: "number", text: .analyticsCollectedCounts),
        Item(symbol: "desktopcomputer", text: .analyticsCollectedSystem),
    ]

    static let neverCollected: [Item] = [
        Item(symbol: "app.dashed", text: .analyticsNeverNames),
        Item(symbol: "character.cursor.ibeam", text: .analyticsNeverText),
        Item(symbol: "doc.text", text: .analyticsNeverContent),
    ]

    /// The full event list and collection rules.
    static let documentationURL = URL(string: "https://github.com/benjamin-kraatz/DeeDock/blob/main/docs/ANALYTICS.md")!
}

/// Two columns: what is shared, and what stays on the Mac. They stack when the width is short
/// or the text is large.
struct AnalyticsDisclosureColumns: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) { columns }
            VStack(alignment: .leading, spacing: 14) { columns }
        }
    }

    @ViewBuilder private var columns: some View {
        AnalyticsDisclosureColumn(title: .analyticsCollectedTitle, symbol: "checkmark.circle.fill", tint: .green,
                                  items: AnalyticsDisclosure.collected)
        AnalyticsDisclosureColumn(title: .analyticsNeverCollectedTitle, symbol: "lock.circle.fill", tint: .orange,
                                  items: AnalyticsDisclosure.neverCollected)
    }
}

private struct AnalyticsDisclosureColumn: View {
    let title: LocalizedStringResource
    let symbol: String
    let tint: Color
    let items: [AnalyticsDisclosure.Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label { Text(title).font(.subheadline.weight(.semibold)) } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .accessibilityAddTraits(.isHeader)
            ForEach(items) { item in
                Label { Text(item.text) } icon: {
                    Image(systemName: item.symbol).foregroundStyle(.secondary)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("What is collected") {
    AnalyticsDisclosureColumns().padding().frame(width: 560)
}

#Preview("What is collected — narrow, large text") {
    AnalyticsDisclosureColumns().padding().frame(width: 300).dynamicTypeSize(.accessibility2)
}
#endif
