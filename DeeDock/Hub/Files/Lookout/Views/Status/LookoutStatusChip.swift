import SwiftUI

/// Lookout's status at the trailing end of the search scope bar (the mockup's `.lchip`): a dot and a few words.
///
/// The dot is green when ready; the Lookout accent, breathing, while reading files or downloading (still under Reduce
/// Motion); orange when paused; red when stopped; gray when off or not set up. The words are `LookoutStatus.title`
/// and `detail` ("Reading files · 1,204 files left"); before setup it reads "Lookout off · **Set up**".
///
/// A click runs `onSetUpLookout` before setup and `onOpenLookoutSettings` after (phase 3 hooks).
struct LookoutStatusChip: View {
    let status: LookoutStatus
    /// The model download's progress while waiting for the model, when known.
    var downloadProgress: Double?
    var reduceMotion = HubFilesMotion.reduceMotion
    let onSetUpLookout: () -> Void
    let onOpenLookoutSettings: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        let theme = HubFilesTheme(scheme)
        Button(action: status == .notSetUp ? onSetUpLookout : onOpenLookoutSettings) {
            HStack(spacing: 7) {
                LookoutStatusDot(color: dotColor, breathes: breathes && !reduceMotion)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 10))
            .background(hovered ? theme.chipHighlight : theme.chip, in: .rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(HubFilesMotion.animation(.easeOut(duration: 0.2)), value: hovered)
        .help(Text(verbatim: help))
        .accessibilityLabel(Text(verbatim: plainLabel))
        .accessibilityHint(Text(status == .notSetUp ? .lookoutChipSetUpHint : .lookoutChipSettingsHint))
    }

    private var dotColor: Color {
        switch status {
        case .ready: LookoutTheme.ready
        case .indexing, .waitingForModel: LookoutTheme(scheme).accent
        case .paused: LookoutTheme.paused
        case .failed: LookoutTheme.failed
        case .notSetUp, .off: Color.secondary.opacity(0.6)
        }
    }

    private var breathes: Bool {
        switch status {
        case .indexing, .waitingForModel: true
        default: false
        }
    }

    /// The second part after " · ", if any: the files left, why reading waits, the download's progress.
    private var detail: String? {
        switch status {
        case .notSetUp: String(localized: LookoutStatus.notSetUp.title)
        case .waitingForModel: downloadProgress.map { $0.formatted(.percent.precision(.fractionLength(0))) }
        case .failed: nil   // a whole sentence: it's the tooltip instead
        default: status.detail
        }
    }

    private var title: String {
        String(localized: status == .notSetUp ? LookoutStatus.off.title : status.title)
    }

    private var label: AttributedString {
        var text = AttributedString(title)
        guard let detail else { return text }
        var tail = AttributedString(detail)
        if status == .notSetUp {
            tail.font = .system(size: 12, weight: .semibold)
            tail.foregroundColor = .primary
        }
        text += AttributedString(" · ") + tail
        return text
    }

    private var plainLabel: String {
        [title, detail].compactMap { $0 }.joined(separator: ", ")
    }

    private var help: String {
        if case .failed(let failure) = status { return failure.message }
        return plainLabel
    }
}

/// The 7 pt status dot; while Lookout works it breathes down to 35 % and back every 1.6 s.
private struct LookoutStatusDot: View {
    let color: Color
    let breathes: Bool

    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(breathes && dim ? 0.35 : 1)
            .onAppear { startBreathing() }
            .onChange(of: breathes) { startBreathing() }
            .accessibilityHidden(true)
    }

    private func startBreathing() {
        guard breathes else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { dim = false }
            return
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
    }
}

#Preview("Status chips") {
    VStack(alignment: .trailing, spacing: 10) {
        LookoutStatusChip(status: .notSetUp, onSetUpLookout: {}, onOpenLookoutSettings: {})
        LookoutStatusChip(status: .waitingForModel, downloadProgress: 0.42, onSetUpLookout: {}, onOpenLookoutSettings: {})
        LookoutStatusChip(status: .indexing(remaining: 1_204, progress: 0.3), onSetUpLookout: {}, onOpenLookoutSettings: {})
        LookoutStatusChip(status: .indexing(remaining: 1_204, progress: 0.3), reduceMotion: true,
                          onSetUpLookout: {}, onOpenLookoutSettings: {})
        LookoutStatusChip(status: .ready, onSetUpLookout: {}, onOpenLookoutSettings: {})
        LookoutStatusChip(status: .paused(.lowPowerMode), onSetUpLookout: {}, onOpenLookoutSettings: {})
        LookoutStatusChip(status: .failed(LookoutFailure(kind: .service)), onSetUpLookout: {}, onOpenLookoutSettings: {})
        LookoutStatusChip(status: .off, onSetUpLookout: {}, onOpenLookoutSettings: {})
    }
    .padding(20)
    .background(.regularMaterial)
}
