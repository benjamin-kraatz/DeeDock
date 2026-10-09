import SwiftUI

/// The running job: icon, "Copying N items", a progress bar and percentage, "From → To",
/// pause/resume and cancel, and a "+N" chip for queued jobs.
struct HubFilesTransferProgress: View {
    let model: HubFilesModel
    let status: HubFilesTransferStatus

    @Environment(\.colorScheme) private var scheme

    private var isPaused: Bool { status.phase == .paused }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.kind == .copy ? "doc.on.doc" : "arrow.right.doc.on.clipboard")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            Text(verbatim: label)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
            HubFilesProgressBar(fraction: status.fraction, isPaused: isPaused)
                .frame(width: 250, height: 6)
                .layoutPriority(-1)
            Text(status.fraction, format: .percent.precision(.fractionLength(0)))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)
            Text(verbatim: "\(status.sourceName) → \(status.destinationName)")
                .lineLimit(1)
                .truncationMode(.middle)
            HubFilesRoundButton(symbol: isPaused ? "play.fill" : "pause.fill",
                                label: isPaused ? .hubFilesTransferResume : .hubFilesTransferPause) {
                model.togglePause(status.jobID)
            }
            HubFilesRoundButton(symbol: "xmark", label: .hubFilesTransferCancel) {
                model.cancelTransfer(status.jobID)
            }
            if status.queuedCount > 0 {
                Text(verbatim: "+\(status.queuedCount)")
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(HubFilesTheme(scheme).chip, in: .capsule)
                    .accessibilityLabel(Text(.hubFilesTransferQueued(status.queuedCount)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(status.fraction, format: .percent.precision(.fractionLength(0))))
    }

    private var label: String {
        let action = String(localized: status.kind == .copy ? .hubFilesCopying(status.itemCount) : .hubFilesMoving(status.itemCount))
        return isPaused ? String(localized: .hubFilesTransferPausedPrefix(action)) : action
    }
}

/// The 6 pt progress track with an accent gradient (gray while paused).
private struct HubFilesProgressBar: View {
    let fraction: Double
    let isPaused: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(HubFilesTheme(scheme).chipHighlight)
                Capsule()
                    .fill(isPaused ? AnyShapeStyle(.tertiary)
                          : AnyShapeStyle(LinearGradient(colors: [.accentColor, Color(red: 0.35, green: 0.78, blue: 0.98)],
                                                         startPoint: .leading, endPoint: .trailing)))
                    .frame(width: max(6, geometry.size.width * min(max(fraction, 0), 1)))
            }
        }
        .animation(HubFilesMotion.animation(.linear(duration: 0.2)), value: fraction)
        .accessibilityHidden(true)
    }
}

/// A 28 pt round control (pause/resume, cancel).
private struct HubFilesRoundButton: View {
    let symbol: String
    let label: LocalizedStringResource
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(hovered ? HubFilesTheme(scheme).chipHighlight : HubFilesTheme(scheme).chip, in: .circle)
                .contentShape(.circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.hubPress(scale: 0.88))
        .onHover { hovered = $0 }
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}
