import SwiftUI

/// Single- or multiple-choice options as chips.
///
/// When the author turned off the submit button, a single choice answers on click: the chip
/// fills and shows a checkmark, and the answer is submitted a moment later so the selection is
/// seen before the next question slides in. That delay is owned by a task keyed to the choice,
/// so it is cancelled if the card goes away first.
struct LauncherSurveyChoiceField: View {
    let choices: AnalyticsSurvey.Choices
    let order: [Int]
    let allowsMultiple: Bool
    let buttonText: String?
    /// Offered for optional questions.
    var skip: (() -> Void)?
    let submit: (AnalyticsSurveyAnswer) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Set<Int> = []
    @State private var committed: Int?

    private var submitsOnSelection: Bool { !allowsMultiple && choices.submitsOnSelection }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LauncherSurveyWrapLayout(spacing: 8) {
                ForEach(order, id: \.self) { index in chip(index) }
            }
            .disabled(committed != nil)
            if !submitsOnSelection || skip != nil {
                LauncherSurveySubmitRow(buttonText: buttonText, canSubmit: !selection.isEmpty && committed == nil,
                                        showsSubmit: !submitsOnSelection, skip: skip) {
                    submit(allowsMultiple ? .choices(selection.sorted()) : .choice(selection.first ?? 0))
                }
            }
        }
        .task(id: committed) {
            guard let committed else { return }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 420))
            guard !Task.isCancelled else { return }
            submit(.choice(committed))
        }
    }

    private func chip(_ index: Int) -> some View {
        let selected = selection.contains(index)
        return Button {
            withAnimation(LauncherSurveyMotion(reduceMotion: reduceMotion).feedback) { select(index) }
        } label: {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
                Text(verbatim: choices.options[index])
            }
        }
        .buttonStyle(LauncherSurveyChipStyle(isSelected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select(_ index: Int) {
        if allowsMultiple {
            if selection.remove(index) == nil { selection.insert(index) }
        } else {
            selection = [index]
            if submitsOnSelection { committed = index }
        }
    }
}

/// Skip (for optional questions) and the author's submit button, aligned to the trailing edge.
struct LauncherSurveySubmitRow: View {
    let buttonText: String?
    let canSubmit: Bool
    var showsSubmit = true
    var skip: (() -> Void)?
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            if let skip {
                Button(action: skip) { Text(.launcherSurveySkip) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            if showsSubmit {
                Button(action: submit) {
                    if let buttonText { Text(verbatim: buttonText) } else { Text(.launcherSurveySubmit) }
                }
                .buttonStyle(.glassProminent)
                .disabled(!canSubmit)
            }
        }
        .controlSize(.regular)
    }
}
