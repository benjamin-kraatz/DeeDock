import SwiftUI

/// The steps the model proposed and the button that runs them all. Nothing runs until it is
/// clicked, and not before the answer is complete.
///
/// One step is the button itself, such as "Choose File > New Tab", with the field it types into
/// named beside it. Two or three steps are listed in a quiet tray above a "Run 3 Steps" button.
/// While the chain runs, a highlight slides to the current row, its number turns into a spinner
/// and then a check, and the button (`RobiRunButton`) reports the result where Run was.
struct RobiProposalView: View {
    let proposal: RobiProposal
    let runState: RobiRunState?
    let isReady: Bool
    let reduceMotion: Bool
    let run: () -> Void

    static let rowHeight: CGFloat = 24
    static let trayPadding: CGFloat = 4
    /// The gap between the tray and the button.
    private static let spacing: CGFloat = 8

    /// The height the proposal takes in the card, which the answer above it gives up. Every part
    /// has a fixed height so this stays exact; see `RobiAnswerText.maxHeight`.
    static func height(stepCount: Int) -> CGFloat {
        guard stepCount > 1 else { return RobiRunButton.height }
        return CGFloat(stepCount) * rowHeight + 2 * trayPadding + spacing + RobiRunButton.height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            if proposal.steps.count > 1 {
                RobiStepList(steps: proposal.steps, runState: runState, reduceMotion: reduceMotion)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                RobiRunButton(proposal: proposal, runState: runState, isReady: isReady, reduceMotion: reduceMotion, run: run)
                if proposal.steps.count == 1, let detail = proposal.steps[0].detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .transition(.opacity)
                }
            }
        }
        .animation(RobiMotion.morph(reduceMotion), value: proposal)
        .animation(RobiMotion.morph(reduceMotion), value: runState)
    }
}

/// Where one step is in a run.
enum RobiStepStatus: Equatable {
    case waiting, running, done, failed, skipped

    init(index: Int, runState: RobiRunState?) {
        switch runState {
        case nil: self = .waiting
        case let .running(current): self = index < current ? .done : index == current ? .running : .waiting
        case .done: self = .done
        case let .failed(failed): self = index < failed ? .done : index == failed ? .failed : .skipped
        }
    }

    var accessibilityValue: LocalizedStringResource? {
        switch self {
        case .waiting: nil
        case .running: .robiStepStatusRunning
        case .done: .robiStepStatusDone
        case .failed: .robiStepStatusFailed
        case .skipped: .robiStepStatusSkipped
        }
    }
}

/// Two or three steps in their tray, numbered, each showing its progress once the run starts.
///
/// Rows are identified by position: a step's number is what it is, the list never reorders, and
/// `RobiStep` carries no identity of its own. The running row's highlight is one view that moves
/// from row to row through a matched geometry group, so it slides rather than blinks.
private struct RobiStepList: View {
    let steps: [RobiStep]
    let runState: RobiRunState?
    let reduceMotion: Bool
    @Namespace private var highlight

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                RobiStepRow(step: step, number: index + 1, status: RobiStepStatus(index: index, runState: runState),
                            allDone: runState == .done, reduceMotion: reduceMotion, highlight: highlight)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(RobiProposalView.trayPadding)
        .background(shape.fill(Color.primary.opacity(0.045)))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.robiStepsLabel))
    }
}

/// One proposed step: its marker, the kind of thing it does, what it does, and for typing the
/// field it types into. Done rows recede, skipped rows fade, and the failed row keeps its weight
/// under an orange marker so the eye lands on it.
private struct RobiStepRow: View {
    let step: RobiStep
    let number: Int
    let status: RobiStepStatus
    /// Every step ran: the markers turn green together with the Run button.
    let allDone: Bool
    let reduceMotion: Bool
    let highlight: Namespace.ID

    var body: some View {
        HStack(spacing: 8) {
            RobiStepMarker(number: number, status: status, allDone: allDone, reduceMotion: reduceMotion)
            Image(systemName: step.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(step.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(status == .done ? .secondary : .primary)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if let detail = step.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: RobiProposalView.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if status == .running {
                let fill = RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(0.12))
                if reduceMotion {
                    fill.transition(.opacity)
                } else {
                    fill.matchedGeometryEffect(id: "running", in: highlight)
                }
            }
        }
        .opacity(status == .skipped ? 0.45 : 1)
        // The full title, for a long menu path or typed text that truncates in the row.
        .help(Text(step.title))
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.accessibilityValue.map { Text($0) } ?? Text(verbatim: ""))
    }
}

/// A step's number in a ring, which becomes a spinner while the step runs and then a filled disc
/// with a check, or with an exclamation mark if the step could not run. Skipped steps keep their
/// number; the row around them fades.
private struct RobiStepMarker: View {
    let number: Int
    let status: RobiStepStatus
    let allDone: Bool
    let reduceMotion: Bool

    static let size: CGFloat = 18

    var body: some View {
        ZStack {
            switch status {
            case .waiting, .skipped:
                Circle().strokeBorder(Color.primary.opacity(0.28), lineWidth: 1.5)
                Text(number, format: .number)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            case .running:
                RobiArcSpinner(color: .accentColor, lineWidth: 2)
                    .padding(1)
                    .transition(swap)
            case .done:
                Circle().fill(allDone ? Color.green : Color.accentColor)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(swap)
            case .failed:
                Circle().fill(Color.orange)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(swap)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
    }

    private var swap: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity)
    }
}

extension RobiStep {
    /// What the step does, as the card names it.
    var title: LocalizedStringResource {
        switch self {
        case let .menu(path): .robiStepMenu(path)
        case let .press(_, label): .robiStepPress(label)
        case let .toggle(_, label, on): on ? .robiStepToggleOn(label) : .robiStepToggleOff(label)
        case let .type(_, _, text): .robiStepType(text)
        }
    }

    /// The smaller line beside the title: the field a typing step goes into. Nil for the others,
    /// whose title names their target already.
    var detail: LocalizedStringResource? {
        guard case let .type(_, label, _) = self else { return nil }
        return .robiStepTypeField(label)
    }

    var symbol: String {
        switch self {
        case .menu: "menubar.rectangle"
        case .press: "cursorarrow.click"
        case .toggle: "switch.2"
        case .type: "character.cursor.ibeam"
        }
    }
}

#if DEBUG
/// Plays a run through from waiting to done, then stops at the second step, then starts over,
/// at the pace the controller uses, so the sliding highlight, the markers and the chip can be
/// watched together.
private struct RobiProposalRunPreview: View {
    let dark: Bool
    let reduceMotion: Bool
    @State private var runState: RobiRunState?

    var body: some View {
        RobiProposalView(proposal: RobiPreviewData.steps, runState: runState, isReady: true,
                         reduceMotion: reduceMotion, run: {})
            .padding(16)
            .frame(width: RobiMetrics.cardWidth)
            .background(dark ? Color(red: 0.15, green: 0.16, blue: 0.19) : Color(red: 0.98, green: 0.98, blue: 1))
            .environment(\.colorScheme, dark ? .dark : .light)
            .task { await replay() }
    }

    private func replay() async {
        let script: [(RobiRunState?, Double)] = [
            (nil, 1.2), (.running(index: 0), 0.7), (.running(index: 1), 0.7), (.running(index: 2), 0.7), (.done, 1.6),
            (nil, 1.2), (.running(index: 0), 0.7), (.running(index: 1), 0.7), (.failed(index: 1), 2.2),
        ]
        while !Task.isCancelled {
            for (state, wait) in script {
                runState = state
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
            }
        }
    }
}

#Preview("Proposal: run plays through, dark") { RobiProposalRunPreview(dark: true, reduceMotion: false) }
#Preview("Proposal: run plays through, light, Reduce Motion") { RobiProposalRunPreview(dark: false, reduceMotion: true) }
#Preview("Proposal: one step with a field") {
    RobiProposalView(proposal: RobiProposal(steps: [.type(element: 4, label: "Search", text: "meeting Thursday")]),
                     runState: nil, isReady: true, reduceMotion: false, run: {})
        .padding(16)
        .frame(width: RobiMetrics.cardWidth)
}
#Preview("Proposal: long labels, German, second failed") {
    RobiProposalView(proposal: RobiProposal(steps: [
        .menu(path: "Ablage > Exportieren als > PDF mit allen Kommentaren und Anhängen…"),
        .type(element: 2, label: "Betreff der Nachricht an das gesamte Team", text: "Protokoll der Besprechung vom Donnerstag, mit allen Beschlüssen"),
        .toggle(element: 3, label: "Nur ungelesene Nachrichten anzeigen", on: true),
    ]), runState: .failed(index: 1), isReady: true, reduceMotion: false, run: {})
        .padding(16)
        .frame(width: RobiMetrics.cardWidth)
        .environment(\.locale, Locale(identifier: "de"))
}
#endif
