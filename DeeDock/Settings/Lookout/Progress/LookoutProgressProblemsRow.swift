import SwiftUI

/// The progress card's last row: "12 skipped · 3 couldn't be read", with a disclosure that lists the reasons and
/// how many files each covers. Shown only when something was skipped or failed.
struct LookoutProgressProblemsRow: View {
    let skipped: Int
    let failed: Int
    let problems: [LookoutProgressDisplay.Problem]
    var reduceMotion = HubFilesMotion.reduceMotion

    @Environment(\.locale) private var locale
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if problems.isEmpty {
                // Counts without reasons: a line, not a disclosure.
                header
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(.lookoutProgressProblemsLabel))
                    .accessibilityValue(Text(verbatim: summary))
            } else {
                Button {
                    withAnimation(reduceMotion ? nil : HubStyle.motion) { expanded.toggle() }
                } label: {
                    header.contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(.lookoutProgressProblemsLabel))
                .accessibilityValue(Text(verbatim: summary))
                .accessibilityHint(Text(.lookoutProgressProblemsHint))
            }
            if expanded, !problems.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(problems) { problem in
                        HStack(spacing: 8) {
                            Text(verbatim: problem.reason)
                                .font(.system(size: 12))
                            Spacer(minLength: 8)
                            Text(verbatim: problem.count.formatted(.number.locale(locale)))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.leading, 18)
                .padding(.top, 8)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    /// The chevron (only with reasons to show) and the counts.
    private var header: some View {
        HStack(spacing: 8) {
            if !problems.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 10)
            }
            Text(verbatim: summary)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
    }

    private var summary: String {
        var parts: [String] = []
        if skipped > 0 { parts.append(LookoutProgressFormatting.localized(.lookoutProgressSkipped(skipped), locale)) }
        if failed > 0 { parts.append(LookoutProgressFormatting.localized(.lookoutProgressFailedCount(failed), locale)) }
        return parts.joined(separator: " · ")
    }
}

#if DEBUG
#Preview("Problems") {
    SettingsCard {
        LookoutProgressProblemsRow(skipped: 12, failed: 3, problems: LookoutProgressDisplay.Sample.readingMid.problems)
        LookoutProgressProblemsRow(skipped: 0, failed: 1, problems: [])
    }
    .frame(width: SettingsMetrics.columnWidth)
    .padding(SettingsMetrics.pageInset)
}
#endif
