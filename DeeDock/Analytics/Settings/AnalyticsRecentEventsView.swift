import SwiftUI

/// An expandable list of the events DOKK handed to the analytics backend since launch.
///
/// Event and property names are developer identifiers and are shown as they are sent, so they
/// stay out of the string catalog.
struct AnalyticsRecentEventsView: View {
    /// Newest first.
    let records: [AnalyticsRecord]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if records.isEmpty {
                Text(.analyticsRecentEmpty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } else {
                // Lazy, so a full log costs nothing until it is scrolled into view.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(records) { AnalyticsRecentEventRow(record: $0) }
                    }
                    .padding(.top, 6)
                }
                .frame(maxHeight: 220)
            }
        } label: {
            HStack {
                Text(.analyticsRecentTitle)
                Spacer(minLength: SettingsMetrics.controlSpacing)
                Text(records.count, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AnalyticsRecentEventRow: View {
    let record: AnalyticsRecord

    private var details: String {
        record.properties.values.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.displayText)" }.joined(separator: "  ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: record.name).font(.callout.monospaced().weight(.medium))
                Spacer(minLength: 8)
                Text(record.date, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            if !details.isEmpty {
                Text(verbatim: details)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Recently sent — empty") {
    AnalyticsRecentEventsView(records: []).frame(width: 560).padding()
}
#endif
