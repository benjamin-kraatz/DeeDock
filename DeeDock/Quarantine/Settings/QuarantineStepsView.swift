import SwiftUI

/// The stamp's whole gesture vocabulary as three steps, so no paragraph has to explain it.
struct QuarantineStepsView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            QuarantineStep(symbol: "hand.point.up.left.fill", title: .quarantineStepArm,
                           detail: .quarantineStepArmDetail)
            QuarantineStepConnector()
            QuarantineStep(symbol: "seal.fill", title: .quarantineStepStamp,
                           detail: .quarantineStepStampDetail)
            QuarantineStepConnector()
            QuarantineStep(symbol: "arrow.uturn.backward", title: .quarantineStepRelease,
                           detail: .quarantineStepReleaseDetail)
        }
        .padding(.vertical, 4)
    }
}

private struct QuarantineStep: View {
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.quarantineStamp)
                .frame(width: 36, height: 36)
                .background(Color.quarantineStamp.opacity(0.14), in: .circle)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct QuarantineStepConnector: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
            .frame(height: 36)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Steps") {
    QuarantineStepsView()
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}
#endif
