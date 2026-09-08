import Foundation
import SwiftUI

/// Visual observations are informational and never determine the watch's final outcome.
nonisolated enum WindowWatchObservation: Equatable, Sendable {
    case baseline, change, changing, settling, returned, reset, confirmed

    var label: LocalizedStringResource {
        switch self {
        case .baseline: .watchActivityBaseline
        case .change: .watchActivityChange
        case .changing: .watchActivityChanging
        case .settling: .watchActivitySettling
        case .returned: .watchActivityReturned
        case .reset: .watchActivityReset
        case .confirmed: .watchActivityConfirmed
        }
    }
}

/// Consecutive identical observations share one entry, with the most recent observation time.
struct WindowWatchActivityEntry: Identifiable {
    let id = UUID()
    let observation: WindowWatchObservation
    var date: Date
}

struct WindowWatchActivityView: View {
    let entries: [WindowWatchActivityEntry]
    @State private var expanded = false

    var body: some View {
        if let latest = entries.last {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entries.reversed()) { entry in
                        row(entry)
                    }
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(.watchActivityTitle).font(.callout)
                    if !expanded { row(latest) }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 12))
        }
    }

    private func row(_ entry: WindowWatchActivityEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.observation.label).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(entry.date, style: .time).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Observed changes") {
    WindowWatchActivityView(entries: [
        WindowWatchActivityEntry(observation: .change, date: Date(timeIntervalSince1970: 100)),
        WindowWatchActivityEntry(observation: .settling, date: Date(timeIntervalSince1970: 106))
    ]).padding().frame(width: 460)
}
