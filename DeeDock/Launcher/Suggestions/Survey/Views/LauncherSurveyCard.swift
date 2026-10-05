import SwiftUI

/// The App Recommendations survey, drawn in place below the suggested apps.
///
/// One card carries the whole conversation: each answer slides the next question in from the
/// trailing edge while the card springs to its new height, the badge morphs from sparkles to a
/// checkmark for the thank-you, and a light runs once around the edge on every step. Closing
/// it mid-way leaves a one-line confirmation that also offers to stop asking.
struct LauncherSurveyCard: View {
    let survey: LauncherSuggestionSurvey
    /// Reports whether the open-answer field has keyboard focus.
    var textFocusChanged: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = 0

    private var motion: LauncherSurveyMotion { LauncherSurveyMotion(reduceMotion: reduceMotion) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LauncherSurveyBadge(symbol: symbol)
            VStack(alignment: .leading, spacing: 10) {
                if survey.currentQuestion != nil { header }
                content
                    .id(survey.phase)
                    .transition(motion.step)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background { LauncherSurveyCardBackground(pulse: pulse) }
        .animation(motion.morph, value: survey.phase)
        .onAppear { pulse += 1 }
        .onChange(of: survey.answeredCount) { pulse += 1 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.launcherSurveyAccessibilityLabel))
    }

    private var symbol: String {
        switch survey.phase {
        case .thanks: "checkmark"
        case .dismissed: "hand.wave.fill"
        case .asking, .closed: "sparkles"
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(.launcherSurveyEyebrow)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            let progress = survey.progress
            if progress.total > 1 {
                LauncherSurveyProgress(completed: progress.completed, total: progress.total)
            }
            Spacer(minLength: 0)
            Button { survey.dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(LauncherSurveyIconButtonStyle())
                .help(Text(.launcherSurveyClose))
                .accessibilityLabel(Text(.launcherSurveyClose))
        }
        .frame(minHeight: 30)
    }

    @ViewBuilder private var content: some View {
        switch survey.phase {
        case .asking:
            if let current = survey.currentQuestion {
                LauncherSurveyQuestionView(question: current.question,
                                           choiceOrder: survey.choiceOrders[current.question.id] ?? [],
                                           textFocusChanged: textFocusChanged) { answer in
                    survey.answer(answer, toQuestionAt: current.index)
                }
            }
        case .thanks:
            if let appearance = survey.survey?.appearance {
                LauncherSurveyThanksView(appearance: appearance, close: survey.close)
                    .padding(.top, 5)
            }
        case .dismissed:
            LauncherSurveyDismissedView(stopAsking: survey.stopAsking, close: survey.close)
                .padding(.top, 5)
        case .closed:
            EmptyView()
        }
    }
}
