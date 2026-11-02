import SwiftUI

/// "Stored data" with the collector's status under it and the data on the trailing edge: its size and first day
/// ("2.4 MB · since 30 Oct"), "No data yet", or what is in progress with a spinner.
///
/// The status line reads like a plugin's: a small dot and a few words. It shows only while collection is on, so
/// the switch above is the single word on "off".
struct AppHealthDataStatusRow: View {
    let phase: AppHealthController.Phase
    let summary: AppHealthStorageSummary
    let activity: AppHealthController.StorageActivity
    var reduceMotion = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(.appHealthStoredData)
                if phase != .off {
                    AppHealthCollectorStatusLine(phase: phase)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            Spacer(minLength: SettingsMetrics.controlSpacing)
            HStack(spacing: 6) {
                if activity != .idle {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
                Text(data)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.25), value: activity)
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowVerticalInset)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var data: LocalizedStringResource {
        switch activity {
        case .exporting: return .appHealthExporting
        case .deleting: return .appHealthDeleting
        case .idle: break
        }
        guard summary.hasData, let oldest = summary.oldest else { return .appHealthDataEmpty }
        return .appHealthDataSummary(size: summary.bytes.formatted(.byteCount(style: .file)),
                                     date: oldest.formatted(.dateTime.day().month(.abbreviated)))
    }
}

/// "● Collecting every 20 seconds" or "● Paused while the Mac sleeps": a dot in the page tint while sampling runs,
/// a quiet one while it is paused. Nothing animates while idle; the dot's halo is a static shadow.
struct AppHealthCollectorStatusLine: View {
    let phase: AppHealthController.Phase

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sampling ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(nsColor: .tertiaryLabelColor)))
                .frame(width: 7, height: 7)
                .shadow(color: sampling ? SettingsPage.appHealth.tint.opacity(0.55) : .clear, radius: 3)
                .accessibilityHidden(true)
            Text(title)
                .contentTransition(.opacity)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var sampling: Bool { phase == .collecting }

    private var title: LocalizedStringResource {
        switch phase {
        case .collecting, .off: .appHealthStatusCollecting
        case .paused: .appHealthStatusPaused
        }
    }
}

#if DEBUG
#Preview("Data status rows") {
    let reference = Date(timeIntervalSince1970: 1_793_000_000)
    let withData = AppHealthStorageSummary(bytes: 2_400_000, oldest: reference.addingTimeInterval(-3 * 86_400), days: 4)
    SettingsCard {
        AppHealthDataStatusRow(phase: .off, summary: .empty, activity: .idle)
        AppHealthDataStatusRow(phase: .collecting, summary: withData, activity: .idle)
        AppHealthDataStatusRow(phase: .paused, summary: withData, activity: .idle)
        AppHealthDataStatusRow(phase: .collecting, summary: withData, activity: .exporting)
        AppHealthDataStatusRow(phase: .collecting, summary: withData, activity: .deleting)
    }
    .tint(SettingsPage.appHealth.tint)
    .padding(24)
    .frame(width: SettingsMetrics.columnWidth)
}
#endif
