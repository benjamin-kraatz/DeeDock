import SwiftUI

/// One observation as a compact pill, for lists and side-by-side comparisons.
///
/// A badge is a count, a cleared badge, an app-supplied string, or nothing observable at all, and
/// those read very differently. The pill keeps the number legible on its own while an unavailable
/// observation stays visibly not-a-number, so an empty row is never mistaken for a zero.
struct BadgeValueChip: View {
    let value: BadgeObservation
    var prominent = false

    private var text: String? {
        switch value {
        case .count(let count): count.formatted(.number)
        case .text(let text): text
        default: nil
        }
    }

    /// The pill trims a badge to a glyph or two; VoiceOver still gets the full sentence.
    private var spoken: LocalizedStringResource {
        switch value {
        case .unknown: .badgeMemoryUnknown
        case .cleared: .badgeMemoryCleared
        case .count(let count): .badgeMemoryCount(Int(count))
        case .text(let text): .badgeMemoryText(text)
        }
    }

    var body: some View {
        Group {
            if let text {
                Text(verbatim: text)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            } else if value == .cleared {
                Text(.badgeMemoryCleared)
                    .foregroundStyle(.secondary)
            } else {
                Text(.badgeMemoryUnknown)
                    .foregroundStyle(.secondary)
            }
        }
        .font(prominent ? .title3.weight(.semibold) : .callout.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, prominent ? 10 : 8)
        .padding(.vertical, prominent ? 5 : 3)
        .background(.quaternary.opacity(0.7), in: .capsule)
        .accessibilityElement()
        .accessibilityLabel(Text(spoken))
    }
}

/// A signed comparison between two observations, colored by direction.
///
/// Growth is what the user came to see, so it is the colored case; a decrease reads as resolved
/// work. Values that cannot be compared numerically say so rather than showing a misleading zero.
struct BadgeDeltaChip: View {
    let delta: Int64?

    private var color: Color {
        guard let delta, delta != 0 else { return .secondary }
        return delta > 0 ? .orange : .green
    }

    var body: some View {
        Group {
            if let delta {
                Label {
                    Text(verbatim: delta.formatted(.number.sign(strategy: .always())))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: delta == 0 ? "equal" : delta > 0 ? "arrow.up" : "arrow.down")
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(color)
            } else {
                Text(.badgeMemoryNoDelta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }
}

#if DEBUG
#Preview("Values and deltas") {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            BadgeValueChip(value: .count(41), prominent: true)
            BadgeValueChip(value: .cleared)
            BadgeValueChip(value: .text("99+"))
            BadgeValueChip(value: .unknown)
        }
        HStack(spacing: 16) {
            BadgeDeltaChip(delta: 7)
            BadgeDeltaChip(delta: -12)
            BadgeDeltaChip(delta: 0)
            BadgeDeltaChip(delta: nil)
        }
    }
    .padding()
}
#endif
