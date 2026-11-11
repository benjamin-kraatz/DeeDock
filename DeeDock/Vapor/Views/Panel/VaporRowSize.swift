import SwiftUI

/// Size and file count on a row: a "Calculating…" shimmer while measuring, a count-up when the
/// size arrives, or "—" when the folder can't be read.
///
/// The count-up plays once per row, only when the measurement arrives while the row is shown.
/// A row that appears already measured shows its size straight away.
struct VaporRowSize: View {
    let measurement: VaporMeasurement
    let reduceMotion: Bool

    /// 0…1 of the way through the count-up; 1 shows the real values.
    @State private var progress: Double = 1

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            switch measurement {
            case .pending:
                VaporShimmerText(text: Text(.vaporRowCalculating), reduceMotion: reduceMotion)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(verbatim: " ")
                    .font(.system(size: 11))
            case .unreadable:
                Text(verbatim: "—")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: " ")
                    .font(.system(size: 11))
            case .measured(let bytes, let files):
                VaporCountingText(target: Double(bytes), progress: progress) { VaporCopy.size(Int64($0)) }
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                VaporCountingText(target: Double(files), progress: progress) {
                    String(localized: .vaporFileCount(Int($0.rounded())))
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .onChange(of: measurement) { old, new in
            guard old.isPending, case .measured = new, !reduceMotion else { return }
            progress = 0.001
            withAnimation(VaporMotion.countUp) { progress = 1 }
        }
    }

    /// The row's VoiceOver value.
    static func accessibilityValue(_ measurement: VaporMeasurement) -> String {
        switch measurement {
        case .pending: String(localized: .vaporRowCalculating)
        case .unreadable: String(localized: .vaporSizeUnavailable)
        case .measured(let bytes, let files):
            String(localized: .vaporAccessibilityJoined(VaporCopy.size(bytes), String(localized: .vaporFileCount(files))))
        }
    }
}

/// Text that shows `format(target × progress)` and animates `progress`, so a number counts up.
private struct VaporCountingText: View, Animatable {
    let target: Double
    var progress: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Text(verbatim: format(max(target * progress, target * 0.001)))
    }
}

/// Text with a light band sweeping across it, for values still being worked out. Still under
/// Reduce Motion.
struct VaporShimmerText: View {
    let text: Text
    let reduceMotion: Bool

    @State private var phase: CGFloat = 0

    var body: some View {
        text
            .foregroundStyle(.tertiary)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .primary, location: 0.5),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.8)
                            .offset(x: -proxy.size.width * 0.8 + phase * proxy.size.width * 1.8)
                    }
                    .mask(text)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

/// The folder's tag; orange for a folder that isn't a known cache.
struct VaporTagChip: View {
    let classification: VaporClassification

    var body: some View {
        let known = classification.isKnown
        Text(VaporCopy.tag(classification))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(known ? AnyShapeStyle(.secondary) : AnyShapeStyle(VaporStyle.warning))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(known ? VaporStyle.chip : VaporStyle.warning.opacity(0.15),
                        in: .rect(cornerRadius: 6, style: .continuous))
    }
}
