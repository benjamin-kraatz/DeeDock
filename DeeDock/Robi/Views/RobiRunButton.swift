import SwiftUI

/// The button that runs the proposal, and afterwards the run's result in the same place: its
/// play mark turns while the steps run, then the chip settles green with a check when every step
/// ran, or orange with the step it stopped at.
///
/// One step is the chip's own title, such as "Choose File > New Tab", so the button says what it
/// will do. Two or three steps read "Run 3 Steps" under their list. Return runs it once the answer
/// is complete: the card has no text field in that phase, so the key is free, and Esc stays with
/// Done. Disabled until the answer is complete and from the click until the card closes.
struct RobiRunButton: View {
    let proposal: RobiProposal
    let runState: RobiRunState?
    let isReady: Bool
    let reduceMotion: Bool
    let run: () -> Void

    /// Fixed, so the card's height budget (`RobiProposalView.height(stepCount:)`) holds.
    static let height: CGFloat = 28

    private var outcome: RobiRunOutcome { RobiRunOutcome(runState) }

    var body: some View {
        Button(action: run) {
            HStack(spacing: 7) {
                RobiRunGlyph(outcome: outcome, reduceMotion: reduceMotion)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(reduceMotion ? .identity : .opacity)
            }
        }
        .buttonStyle(RobiRunChipStyle(outcome: outcome, reduceMotion: reduceMotion))
        .disabled(!isReady || runState != nil)
        .keyboardShortcut(.defaultAction)
        .help(Text(title))
        .accessibilityValue(outcome.accessibilityValue.map { Text($0) } ?? Text(verbatim: ""))
    }

    /// What the chip says: the one step's name, or the count of steps and, afterwards, how the
    /// run ended. A single step keeps its name throughout; its glyph and colour tell the result.
    private var title: LocalizedStringResource {
        let count = proposal.steps.count
        guard count > 1 else { return proposal.steps[0].title }
        switch outcome {
        case .ready, .running: return .robiRunSteps(count)
        case .done: return .robiRanSteps(count)
        case let .failed(step): return .robiRunStoppedAt(step)
        }
    }
}

/// The run as the button shows it, from the model's `RobiRunState`.
enum RobiRunOutcome: Equatable {
    /// Nothing ran yet; the button is live once the answer is complete.
    case ready
    case running
    case done
    /// The run stopped at this step, numbered from 1.
    case failed(step: Int)

    init(_ runState: RobiRunState?) {
        switch runState {
        case nil: self = .ready
        case .running: self = .running
        case .done: self = .done
        case let .failed(index): self = .failed(step: index + 1)
        }
    }

    var accessibilityValue: LocalizedStringResource? {
        switch self {
        case .ready: nil
        case .running: .robiStepStatusRunning
        case .done: .robiStepStatusDone
        case .failed: .robiStepStatusFailed
        }
    }

    /// The chip's fill. Ready and running share the accent so the click changes nothing but the
    /// glyph; the result recolours the whole chip.
    var fill: Color {
        switch self {
        case .ready, .running: .accentColor
        case .done: .green
        case .failed: Color.orange.opacity(0.18)
        }
    }

    /// The chip's text and glyph.
    var ink: Color {
        if case .failed = self { return .orange }
        return .white
    }
}

/// The disc at the chip's start: a play mark, then the spinner, then a check or an exclamation
/// mark. Same size throughout, so the title never shifts.
private struct RobiRunGlyph: View {
    let outcome: RobiRunOutcome
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle().fill(outcome.ink.opacity(0.22))
            switch outcome {
            case .ready:
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    // A triangle looks centred when it sits a touch right of the disc's centre.
                    .offset(x: 0.5)
                    .transition(swap)
            case .running:
                RobiArcSpinner(color: outcome.ink, lineWidth: 1.8)
                    .padding(2.5)
                    .transition(swap)
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .transition(swap)
            case .failed:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .transition(swap)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    private var swap: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity)
    }
}

/// The Run button's chip. Not `RobiProminentButtonStyle`: that one dims when disabled, and this
/// button is disabled for the whole run, which must look alive, and afterwards, when it shows the
/// result. Only a button waiting for the answer to finish is dimmed.
///
/// On success a ring swells out of the chip and fades, the one flourish before Robi closes.
/// Reduce Motion drops the ring and the press scale; the colour changes stay, as fades.
struct RobiRunChipStyle: ButtonStyle {
    let outcome: RobiRunOutcome
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        RobiRunChip(configuration: configuration, outcome: outcome, reduceMotion: reduceMotion)
    }
}

private struct RobiRunChip: View {
    let configuration: ButtonStyleConfiguration
    let outcome: RobiRunOutcome
    let reduceMotion: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    /// True once the success ring has been sent on its way, or when the chip appeared already done.
    @State private var flourished = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 9, style: .continuous) }

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(outcome.ink)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(height: RobiRunButton.height)
            .background {
                shape.fill(outcome.fill)
                shape.fill(.white.opacity(configuration.isPressed ? 0 : hovering ? 0.1 : 0))
            }
            .overlay {
                if outcome == .done && !reduceMotion {
                    shape.strokeBorder(Color.green, lineWidth: 1.5)
                        .scaleEffect(flourished ? 1.22 : 1)
                        .opacity(flourished ? 0 : 0.9)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled || outcome != .ready ? 1 : 0.45)
            .animation(RobiMotion.feedback(reduceMotion), value: hovering)
            .animation(RobiMotion.feedback(reduceMotion), value: configuration.isPressed)
            .onHover { hovering = $0 && isEnabled }
            .onAppear { if outcome == .done { flourished = true } }
            .onChange(of: outcome) { _, outcome in
                guard outcome == .done else { flourished = false; return }
                withAnimation(.easeOut(duration: 0.55)) { flourished = true }
            }
    }
}

#if DEBUG
/// Every state of the chip, over a dark and a light card colour.
private struct RobiRunButtonGallery: View {
    let proposal: RobiProposal
    let dark: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RobiRunButton(proposal: proposal, runState: nil, isReady: false, reduceMotion: reduceMotion, run: {})
            RobiRunButton(proposal: proposal, runState: nil, isReady: true, reduceMotion: reduceMotion, run: {})
            RobiRunButton(proposal: proposal, runState: .running(index: 1), isReady: true, reduceMotion: reduceMotion, run: {})
            RobiRunButton(proposal: proposal, runState: .done, isReady: true, reduceMotion: reduceMotion, run: {})
            RobiRunButton(proposal: proposal, runState: .failed(index: 1), isReady: true, reduceMotion: reduceMotion, run: {})
        }
        .padding(16)
        .background(dark ? Color(red: 0.15, green: 0.16, blue: 0.19) : Color(red: 0.98, green: 0.98, blue: 1))
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

#Preview("Run chip: three steps, dark and light") {
    HStack(spacing: 0) {
        RobiRunButtonGallery(proposal: RobiPreviewData.steps, dark: true, reduceMotion: false)
        RobiRunButtonGallery(proposal: RobiPreviewData.steps, dark: false, reduceMotion: false)
    }
}
#Preview("Run chip: one step, German") {
    RobiRunButtonGallery(proposal: RobiProposal(steps: [.menu(path: "Shell > New Tab")]), dark: true, reduceMotion: false)
        .environment(\.locale, Locale(identifier: "de"))
}
#Preview("Run chip: Reduce Motion") {
    RobiRunButtonGallery(proposal: RobiPreviewData.steps, dark: false, reduceMotion: true)
}
#endif
