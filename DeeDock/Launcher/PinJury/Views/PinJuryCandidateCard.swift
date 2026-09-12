import AppKit
import SwiftUI

/// Presents the exact local evidence supplied to the jurors for one candidate.
struct PinJuryCandidateCard: View {
    let candidate: PinJuryCandidate
    let isIncumbent: Bool
    @State private var icon: NSImage?

    private var accent: Color { isIncumbent ? .blue : .purple }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                applicationIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(isIncumbent ? .pinJuryIncumbent : .pinJuryChallenger)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(verbatim: candidate.application.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Image(systemName: isIncumbent ? "pin.fill" : "arrow.up.right")
                    .font(.headline)
                    .foregroundStyle(accent.opacity(0.7))
                    .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 12) {
                PinJuryEvidenceMetric(value: candidate.evidence.activations, label: .pinJuryActivations)
                PinJuryEvidenceMetric(value: candidate.evidence.recentActivations, label: .pinJuryRecentActivations)
                PinJuryEvidenceMetric(value: candidate.evidence.activeDays, label: .pinJuryActiveDays)
            }
            Divider()
            HStack(spacing: 5) {
                Image(systemName: "clock").accessibilityHidden(true)
                if let days = candidate.evidence.daysSinceUse {
                    Text(.pinJuryDaysSinceUse(days))
                } else {
                    Text(.pinJuryNoRecordedUse)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PinJuryStyle.card, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(isIncumbent ? .pinJuryIncumbent : .pinJuryChallenger))
        .task(id: candidate.application.url) {
            // Preview fixtures never query installed apps. Real icons load once per URL,
            // outside body evaluation while token streaming updates the conversation.
            guard !candidate.application.url.path.hasPrefix("/Preview/") else { return }
            icon = NSWorkspace.shared.icon(forFile: candidate.application.url.path)
        }
    }

    private var applicationIcon: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(accent)
                    .padding(5)
            }
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }
}

private struct PinJuryEvidenceMetric: View {
    let value: Int
    let label: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value, format: .number)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
