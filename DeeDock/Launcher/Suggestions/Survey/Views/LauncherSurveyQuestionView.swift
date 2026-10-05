import SwiftUI

/// One survey question: the author's title and description above the matching answer field.
struct LauncherSurveyQuestionView: View {
    let question: AnalyticsSurvey.Question
    /// Display order of the options of a choice question.
    let choiceOrder: [Int]
    let textFocusChanged: (Bool) -> Void
    /// Receives the answer, or nil when an optional question is skipped.
    let submit: (AnalyticsSurveyAnswer?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: question.title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let detail = question.detail {
                    Text(verbatim: detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            field
        }
    }

    @ViewBuilder private var field: some View {
        let skip: (() -> Void)? = question.isOptional ? { submit(nil) } : nil
        switch question.kind {
        case let .singleChoice(choices), let .multipleChoice(choices):
            LauncherSurveyChoiceField(choices: choices, order: choiceOrder, allowsMultiple: isMultipleChoice,
                                      buttonText: question.buttonText, skip: skip, submit: submit)
        case let .rating(rating):
            LauncherSurveyRatingField(rating: rating, isOptional: question.isOptional,
                                      buttonText: question.buttonText, submit: submit)
        case let .open(limits):
            LauncherSurveyTextField(limits: limits, isOptional: question.isOptional, buttonText: question.buttonText,
                                    focusChanged: textFocusChanged, submit: submit)
        case .unsupported:
            // Unreachable: a survey with such a question is never offered.
            EmptyView()
        }
    }

    private var isMultipleChoice: Bool {
        if case .multipleChoice = question.kind { true } else { false }
    }
}
